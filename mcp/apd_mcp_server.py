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
APD_VERSION_FILE = APD_PLUGIN_ROOT / "VERSION"
CORE_DIR = APD_PLUGIN_ROOT / "bin" / "core"
CDX_DIR = APD_PLUGIN_ROOT / "bin" / "adapter" / "cdx"

mcp = FastMCP("apd")


def _read_version() -> str:
    # Prefer the runtime-neutral VERSION file. Fall back to the CC plugin
    # manifest only if the primary file is missing (older checkouts).
    if APD_VERSION_FILE.exists():
        try:
            v = APD_VERSION_FILE.read_text().strip()
            if v:
                return v
        except OSError:
            pass
    legacy = APD_PLUGIN_ROOT / ".claude-plugin" / "plugin.json"
    if legacy.exists():
        try:
            data = json.loads(legacy.read_text())
            return data.get("version", "unknown")
        except (json.JSONDecodeError, OSError):
            pass
    return "unknown"


def _codex_env(project_dir: Path | None = None) -> dict:
    """Environment overlay that marks the subprocess as Codex-initiated.

    Framework scripts check APD_RUNTIME to decide whether to apply
    Codex-specific behavior (e.g. skipping sub-agent dispatch checks in
    pipeline-advance, since Codex has no Task tool).
    """
    env = os.environ.copy()
    env["APD_RUNTIME"] = "codex"
    env["APD_PROJECT_DIR"] = str(project_dir or _project_dir())
    return env


def _run_script(path: Path, *args: str, timeout: int = 30) -> dict:
    """Run an APD script and return a structured result.

    Always pins both cwd and APD_PROJECT_DIR to the resolved project root so
    pure-Codex projects also work when Codex is launched from a subdirectory.
    """
    if not path.exists():
        return {"ok": False, "error": f"{path.name} not found at {path}"}
    project = _project_dir()
    try:
        result = subprocess.run(
            ["bash", str(path), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(project),
            env=_codex_env(project),
        )
        return {
            "ok": result.returncode == 0,
            "exit_code": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": f"{path.name} timed out after {timeout}s"}


def _run_core(script: str, *args: str, timeout: int = 30) -> dict:
    """Run a bin/core/* script and return a structured result."""
    return _run_script(CORE_DIR / script, *args, timeout=timeout)


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
    }


@mcp.tool()
def apd_doctor() -> dict:
    """Run the Codex-specific APD self-check.

    Returns raw doctor output so the model can surface issues to the user
    before starting a pipeline.
    """
    return _run_script(CDX_DIR / "codex-doctor", timeout=10)


def _agents_dir(project: Path) -> Path | None:
    """Pick the agent registry dir the resolver would — .claude/agents first
    (CC is source of truth on hybrid projects), .apd/agents fallback."""
    cc = project / ".claude" / "agents"
    if cc.is_dir():
        return cc
    neutral = project / ".apd" / "agents"
    if neutral.is_dir():
        return neutral
    return None


def _parse_agent_frontmatter(path: Path) -> dict:
    """Extract YAML frontmatter fields without pulling a YAML dep.

    Supports: name, description, model, effort, maxTurns, memory, color,
    permissionMode, readonly (scalars) and scope (list). Scope items may be
    `- foo/` entries in a list block or a flow-style `[a, b]`. Unknown
    fields are preserved as strings.
    """
    try:
        text = path.read_text()
    except OSError:
        return {}
    if not text.startswith("---"):
        return {}
    # Extract frontmatter (between first two `---` lines)
    parts = text.split("\n---", 2)
    if len(parts) < 2:
        return {}
    body = parts[0].lstrip("-\n")
    result: dict = {}
    current_list_key: str | None = None
    for raw in body.split("\n"):
        line = raw.rstrip()
        if not line:
            current_list_key = None
            continue
        if current_list_key and line.startswith(("  - ", "    - ", "\t- ")):
            item = line.lstrip(" \t-").strip()
            result.setdefault(current_list_key, []).append(item)
            continue
        current_list_key = None
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        key = key.strip()
        val = val.strip()
        if val == "":
            # Potentially a list block following
            current_list_key = key
            result.setdefault(key, [])
        elif val.startswith("[") and val.endswith("]"):
            inner = val[1:-1].strip()
            items = [s.strip().strip('"').strip("'") for s in inner.split(",")] if inner else []
            result[key] = items
        else:
            # Strip surrounding quotes
            if (val.startswith('"') and val.endswith('"')) or \
               (val.startswith("'") and val.endswith("'")):
                val = val[1:-1]
            result[key] = val
    # Coerce numeric-ish fields
    for numeric in ("maxTurns",):
        if numeric in result and isinstance(result[numeric], str):
            try:
                result[numeric] = int(result[numeric])
            except ValueError:
                pass
    return result


def _read_done(done: Path) -> dict:
    """Parse a .done file produced by the validator.

    Line 1 is `<epoch>|<human-time>[|<task>]`; line 2 is the HMAC
    signature (ignored here — verification is pipeline-advance's job).
    """
    if not done.is_file():
        return {"done": False}
    try:
        first = done.read_text().splitlines()[0]
    except OSError:
        return {"done": False}
    parts = first.split("|", 2)
    out = {"done": True}
    if parts:
        try:
            out["ts"] = int(parts[0])
        except ValueError:
            out["ts"] = 0
    if len(parts) > 1:
        out["time"] = parts[1]
    if len(parts) > 2:
        out["task"] = parts[2]
    return out


@mcp.tool()
def apd_pipeline_state() -> dict:
    """Return structured pipeline state for the active project.

    Reads `<project>/.apd/pipeline/` and returns a JSON-friendly
    snapshot the orchestrator can branch on without parsing the text
    output of `apd_advance_pipeline('status')`.

    Shape:
      {
        "ok": True,
        "project_dir": "...",
        "pipeline_dir": "...",
        "steps": {
          "spec":     {"done": bool, "ts": int, "time": str, "task": str?},
          "builder":  {"done": bool, "ts": int, "time": str},
          "reviewer": {"done": bool, "ts": int, "time": str},
          "verifier": {"done": bool, "ts": int, "time": str}
        },
        "spec_card":           {"exists": bool, "criteria_count": int, "hash_frozen": bool},
        "implementation_plan": {"exists": bool},
        "adversarial":         {"pending": bool, "total": int, "accepted": int, "dismissed": int} | null,
        "reviewed_files":      int,
        "verified_cache":      {"ts": int, "age": int, "fresh": bool} | null,
        "next_step":           "spec" | "builder" | "reviewer" | "verifier" | "commit" | None
      }
    """
    project = _project_dir()
    pipeline_dir = project / ".apd" / "pipeline"
    state: dict = {
        "ok": True,
        "project_dir": str(project),
        "pipeline_dir": str(pipeline_dir),
        "steps": {},
        "spec_card": {"exists": False, "criteria_count": 0, "hash_frozen": False},
        "implementation_plan": {"exists": False},
        "adversarial": None,
        "reviewed_files": 0,
        "verified_cache": None,
        "next_step": "spec",
    }
    if not pipeline_dir.is_dir():
        return state

    # Step .done files
    for step in ("spec", "builder", "reviewer", "verifier"):
        state["steps"][step] = _read_done(pipeline_dir / f"{step}.done")

    # Next step to advance — first step that isn't done; "commit" if all done
    order = ("spec", "builder", "reviewer", "verifier")
    nxt: str | None = "commit"
    for step in order:
        if not state["steps"][step].get("done"):
            nxt = step
            break
    state["next_step"] = nxt

    # spec-card.md
    spec_card = pipeline_dir / "spec-card.md"
    if spec_card.is_file():
        try:
            text = spec_card.read_text()
            # Count R* lines only inside Acceptance criteria section
            import re
            ac_match = re.search(r"Acceptance criteria.*?(?=\n\*\*[A-Z]|\Z)", text, re.S)
            block = ac_match.group(0) if ac_match else text
            criteria = len(re.findall(r"^\s*-\s+R\d+\s*:", block, re.M))
        except OSError:
            criteria = 0
        state["spec_card"] = {
            "exists": True,
            "criteria_count": criteria,
            "hash_frozen": (pipeline_dir / ".spec-hash").is_file(),
        }

    # implementation-plan.md
    if (pipeline_dir / "implementation-plan.md").is_file():
        state["implementation_plan"] = {"exists": True}

    # Adversarial
    adv_summary = pipeline_dir / ".adversarial-summary"
    adv_pending = pipeline_dir / ".adversarial-pending"
    if adv_summary.is_file():
        try:
            line = adv_summary.read_text().strip()
            parts = line.removeprefix("ADVERSARIAL:").split(":")
            if len(parts) == 3:
                state["adversarial"] = {
                    "pending": False,
                    "total": int(parts[0]),
                    "accepted": int(parts[1]),
                    "dismissed": int(parts[2]),
                }
        except (OSError, ValueError):
            state["adversarial"] = {"pending": False, "total": 0, "accepted": 0, "dismissed": 0}
    elif adv_pending.is_file():
        state["adversarial"] = {"pending": True, "total": 0, "accepted": 0, "dismissed": 0}

    # Reviewed files scope captured by the reviewer step
    reviewed = pipeline_dir / ".reviewed-files"
    if reviewed.is_file():
        try:
            state["reviewed_files"] = sum(1 for _ in reviewed.read_text().splitlines() if _.strip())
        except OSError:
            pass

    # Verifier cache timestamp
    vts = pipeline_dir / "verified.timestamp"
    if vts.is_file():
        try:
            ts = int(vts.read_text().strip())
            import time as _t
            age = int(_t.time()) - ts
            state["verified_cache"] = {"ts": ts, "age": age, "fresh": age < 120}
        except (OSError, ValueError):
            pass

    return state


@mcp.tool()
def apd_list_agents() -> dict:
    """List all agent definitions in the active project's registry.

    Reads .claude/agents/ (CC and hybrid projects) or .apd/agents/ (pure
    Codex), whichever exists — matches what the resolver picks at runtime.

    Returns {"ok": True, "agents_dir": <path>, "agents": [...]}. Each agent
    entry has name, description, model, effort, maxTurns, scope (list),
    readonly (bool), plus any other frontmatter fields the template
    carries.

    Intended use: orchestrator calls this once per pipeline, caches the
    result, and passes the matching `scope` list to apd_guard_write before
    every write. That way scope boundaries stay coherent with the agent
    files instead of being re-typed in each tool call.
    """
    project = _project_dir()
    agents_dir = _agents_dir(project)
    if agents_dir is None:
        return {
            "ok": True,
            "agents_dir": None,
            "agents": [],
            "note": "no agent registry found — create .apd/agents/ or .claude/agents/",
        }
    agents: list[dict] = []
    for md in sorted(agents_dir.glob("*.md")):
        fm = _parse_agent_frontmatter(md)
        if not fm:
            continue
        # Normalize: ensure name falls back to filename stem, scope is always a list
        fm.setdefault("name", md.stem)
        if "scope" in fm and not isinstance(fm["scope"], list):
            fm["scope"] = []
        fm.setdefault("scope", [])
        # Coerce readonly to bool
        if "readonly" in fm and isinstance(fm["readonly"], str):
            fm["readonly"] = fm["readonly"].lower() in ("true", "yes", "1")
        fm["file"] = str(md)
        agents.append(fm)
    return {
        "ok": True,
        "agents_dir": str(agents_dir),
        "agents": agents,
    }


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
                env=_codex_env(project),
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
