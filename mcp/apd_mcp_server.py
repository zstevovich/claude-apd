#!/usr/bin/env python3
"""APD MCP server — exposes APD pipeline operations as MCP tools.

Phase 2 server. Each tool is a thin wrapper around an existing bin/core/*
script so behavior stays consistent with the CC adapter.

Requires: `uv run --with mcp python apd_mcp_server.py` (or `pip install 'mcp>=1.0'`).
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from mcp.server.fastmcp import FastMCP

APD_PLUGIN_ROOT = Path(__file__).resolve().parent.parent
APD_PLUGIN_MANIFEST = APD_PLUGIN_ROOT / ".claude-plugin" / "plugin.json"
CORE_DIR = APD_PLUGIN_ROOT / "bin" / "core"

mcp = FastMCP("apd")


def _read_version() -> str:
    if APD_PLUGIN_MANIFEST.exists():
        try:
            data = json.loads(APD_PLUGIN_MANIFEST.read_text())
            return data.get("version", "unknown")
        except json.JSONDecodeError:
            pass
    return "unknown"


def _run_core(script: str, *args: str, timeout: int = 30) -> dict:
    """Run a bin/core/* script and return a structured result.

    cwd is inherited from the MCP server process, which Codex launches from
    the project directory — so resolve-project.sh resolves PROJECT_DIR
    correctly without extra wiring.
    """
    path = CORE_DIR / script
    if not path.exists():
        return {"ok": False, "error": f"{script} not found at {path}"}
    try:
        result = subprocess.run(
            ["bash", str(path), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=os.getcwd(),
        )
        return {
            "ok": result.returncode == 0,
            "exit_code": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": f"{script} timed out after {timeout}s"}


_PROJECT_MARKERS = (".codex", "AGENTS.md", ".claude", "CLAUDE.md")


def _is_project_root(path: Path) -> bool:
    for marker in _PROJECT_MARKERS:
        candidate = path / marker
        if candidate.is_dir() or candidate.is_file():
            return True
    return False


def _project_dir() -> Path:
    """Resolve the active project directory.

    Priority: APD_PROJECT_DIR env → git toplevel (if it carries a project
    marker) → walk up from cwd looking for a marker → cwd. Codex-native
    markers (.codex/, AGENTS.md) are checked alongside legacy CC markers
    (.claude/, CLAUDE.md) so hybrid and pure-Codex projects both resolve.
    """
    env = os.environ.get("APD_PROJECT_DIR")
    if env:
        return Path(env)
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5, cwd=os.getcwd(),
        )
        if out.returncode == 0:
            root = Path(out.stdout.strip())
            if _is_project_root(root):
                return root
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    cwd = Path(os.getcwd()).resolve()
    for candidate in [cwd, *cwd.parents]:
        if _is_project_root(candidate):
            return candidate
    return cwd


@mcp.tool()
def apd_ping() -> dict:
    """Health check for the APD MCP server.

    Returns APD version, plugin root path, and runtime info so the model can
    confirm APD is wired correctly before calling enforcement tools.
    """
    return {
        "ok": True,
        "version": _read_version(),
        "plugin_root": str(APD_PLUGIN_ROOT),
        "project_dir": str(_project_dir()),
        "runtime": "codex",
        "phase": "2-beta",
    }


@mcp.tool()
def apd_doctor() -> dict:
    """Run APD self-check — delegates to bin/core/pipeline-doctor.

    Returns raw doctor output so the model can surface issues to the user
    before starting a pipeline.
    """
    return _run_core("pipeline-doctor", timeout=10)


@mcp.tool()
def apd_advance_pipeline(step: str, arg: str = "") -> dict:
    """Advance the APD pipeline by one step.

    Wraps `bin/core/pipeline-advance`. Accepted step values:
      - "spec" (requires arg = task name)
      - "builder", "reviewer", "verifier"
      - "init" (requires arg = project description, first-run only)
      - "status", "stats", "metrics", "reset", "rollback"

    The script enforces lock-based serialization and writes timestamps to
    $PIPELINE_DIR. Exit code 0 = advance succeeded.
    """
    allowed = {"spec", "builder", "reviewer", "verifier", "init",
               "status", "stats", "metrics", "reset", "rollback"}
    if step not in allowed:
        return {"ok": False, "error": f"unknown step '{step}'. Allowed: {sorted(allowed)}"}
    args = [step] + ([arg] if arg else [])
    return _run_core("pipeline-advance", *args, timeout=30)


@mcp.tool()
def apd_guard_write(file_path: str, allowed_paths: list[str]) -> dict:
    """Check whether a Write/Edit target falls inside an agent's scope.

    Wraps `bin/core/guard-scope`. Pass the path the model wants to write and
    the list of allowed path prefixes for the active agent. Exit code 2 means
    BLOCK (out of scope); exit 0 means ALLOW.
    """
    if not file_path:
        return {"ok": False, "error": "file_path is required"}
    return _run_core("guard-scope", "--file-path", file_path, *allowed_paths, timeout=5)


@mcp.tool()
def apd_verify_step() -> dict:
    """Run the project-level verify-all script.

    Looks up a per-project verifier in Codex-native (.codex/bin/verify-all.sh)
    first, then legacy CC (.claude/bin/verify-all.sh) as fallback for hybrid
    setups. If neither exists, delegates to the framework default at
    bin/core/verify-all.
    """
    project = _project_dir()
    for rel in (".codex/bin/verify-all.sh", ".claude/bin/verify-all.sh"):
        project_verify = project / rel
        if not project_verify.exists():
            continue
        try:
            result = subprocess.run(
                ["bash", str(project_verify)],
                capture_output=True, text=True, timeout=300, cwd=str(project),
            )
            return {
                "ok": result.returncode == 0,
                "exit_code": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "source": "project",
            }
        except subprocess.TimeoutExpired:
            return {"ok": False, "error": f"{rel} timed out after 300s"}
    result = _run_core("verify-all", timeout=300)
    result["source"] = "framework"
    return result


@mcp.tool()
def apd_adversarial_pass(total: int, accepted: int, dismissed: int) -> dict:
    """Record the result of an adversarial review pass.

    Writes `ADVERSARIAL:<total>:<accepted>:<dismissed>` to
    `$PIPELINE_DIR/.adversarial-summary` so `pipeline-advance` can include the
    findings in the session log when the pipeline closes.

    total     — findings raised by the adversarial reviewer
    accepted  — findings the builder acted on
    dismissed — findings the builder rejected with rationale
    """
    if total < 0 or accepted < 0 or dismissed < 0:
        return {"ok": False, "error": "counts must be non-negative"}
    if accepted + dismissed > total:
        return {"ok": False, "error": "accepted + dismissed cannot exceed total"}
    pipeline_dir = _project_dir() / ".apd" / "pipeline"
    if not pipeline_dir.is_dir():
        return {"ok": False, "error": f"pipeline dir does not exist: {pipeline_dir}"}
    summary = pipeline_dir / ".adversarial-summary"
    summary.write_text(f"ADVERSARIAL:{total}:{accepted}:{dismissed}\n")
    return {"ok": True, "path": str(summary), "line": f"ADVERSARIAL:{total}:{accepted}:{dismissed}"}


def _bootstrap_shortcut() -> None:
    """Create .codex/bin/apd shortcut on server start.

    Codex has no reliable SessionStart hook, so the MCP server's own start
    doubles as the bootstrap moment. Only creates the shortcut when the
    resolved project already has a .codex/ dir (i.e., it is a real Codex
    project) so we don't leak files into random cwds.
    """
    project = _project_dir()
    if not (project / ".codex").is_dir():
        return
    plugin_apd = APD_PLUGIN_ROOT / "bin" / "apd"
    shortcut = project / ".codex" / "bin" / "apd"
    if shortcut.exists():
        try:
            if str(plugin_apd) in shortcut.read_text():
                return
        except OSError:
            pass
    shortcut.parent.mkdir(parents=True, exist_ok=True)
    shortcut.write_text(
        "#!/bin/bash\n"
        "# APD — shortcut to plugin entry point\n"
        "# Auto-generated by MCP server bootstrap (Codex session start)\n"
        f'exec bash "{plugin_apd}" "$@"\n'
    )
    shortcut.chmod(0o755)


if __name__ == "__main__":
    _bootstrap_shortcut()
    mcp.run()
