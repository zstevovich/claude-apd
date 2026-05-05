#!/usr/bin/env python3
"""APD MCP server — exposes APD pipeline operations as MCP tools.

Phase 2 server. Each tool is a thin wrapper around an existing bin/core/*
script so behavior stays consistent with the CC adapter.

Requires: `uv run --with mcp python apd_mcp_server.py` (or `pip install 'mcp>=1.0'`).
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
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


def _run_script(path: Path, *args: str, timeout: int = 30, env_extra: dict | None = None) -> dict:
    """Run an APD script and return a structured result.

    Always pins both cwd and APD_PROJECT_DIR to the resolved project root so
    pure-Codex projects also work when Codex is launched from a subdirectory.
    `env_extra` is overlaid on top of the Codex env so callers can surface
    additional variables (e.g. APD_VERIFY_SCOPE) without rebuilding the env.
    """
    if not path.exists():
        return {"ok": False, "error": f"{path.name} not found at {path}"}
    project = _project_dir()
    env = _codex_env(project)
    if env_extra:
        env.update(env_extra)
    try:
        result = subprocess.run(
            ["bash", str(path), *args],
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=str(project),
            env=env,
        )
        return {
            "ok": result.returncode == 0,
            "exit_code": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": f"{path.name} timed out after {timeout}s"}


def _run_core(script: str, *args: str, timeout: int = 30, env_extra: dict | None = None) -> dict:
    """Run a bin/core/* script and return a structured result."""
    return _run_script(CORE_DIR / script, *args, timeout=timeout, env_extra=env_extra)


_PROJECT_MARKERS = (".codex", "AGENTS.md", ".claude", "CLAUDE.md")


def _is_project_root(path: Path) -> bool:
    for marker in _PROJECT_MARKERS:
        candidate = path / marker
        if candidate.is_dir() or candidate.is_file():
            return True
    return False


def _codex_workspace_from_request() -> Path | None:
    """Extract the user's project root from Codex's per-call MCP _meta.

    Codex 0.124+ attaches `_meta["x-codex-turn-metadata"]` to every
    tools/call request. The value contains a `workspaces` map keyed by
    absolute repo-root path. Reading this is the only way to discover the
    user's working directory after v6.0 plugin self-containment, because
    Codex spawns the MCP server with cwd = plugin cache root, not the
    user's project, and does not expose a CODEX_WORKING_DIR env var.

    Falls through silently if not running in a request context, the
    metadata header is missing, or `workspaces` is empty (non-git
    project) — caller falls back to env/git/cwd resolution.
    """
    try:
        from mcp.server.lowlevel.server import request_ctx
    except ImportError:
        return None
    try:
        ctx = request_ctx.get()
    except LookupError:
        return None
    meta = getattr(ctx, "meta", None)
    if meta is None:
        return None
    extra = getattr(meta, "model_extra", None) or {}
    turn_meta = extra.get("x-codex-turn-metadata")
    if not isinstance(turn_meta, dict):
        return None
    workspaces = turn_meta.get("workspaces")
    if not isinstance(workspaces, dict) or not workspaces:
        return None
    # First key is the canonical repo root for this turn
    return Path(next(iter(workspaces)))


def _project_dir() -> Path:
    """Resolve the active project directory.

    Priority: APD_PROJECT_DIR env → Codex MCP request _meta workspaces
    (v6.0+) → git toplevel (if it carries a project marker) → walk up
    from cwd looking for a marker → cwd. Codex-native markers (.codex/,
    AGENTS.md) are checked alongside legacy CC markers (.claude/,
    CLAUDE.md) so hybrid and pure-Codex projects both resolve.

    The Codex _meta source is what makes the post-v6.0 plugin-cache cwd
    layout work: without it the walk-up algorithm would resolve the user
    home (~/.codex/) instead of the actual project.
    """
    env = os.environ.get("APD_PROJECT_DIR")
    if env:
        return Path(env)
    codex_ws = _codex_workspace_from_request()
    if codex_ws is not None:
        return codex_ws
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


def _project_relative_path(project: Path, file_path: str) -> str | None:
    """Return a normalized project-relative path, or None if it escapes."""
    target = Path(file_path).expanduser()
    if not target.is_absolute():
        target = project / target
    try:
        resolved = target.resolve(strict=False)
        project_resolved = project.resolve(strict=False)
        return resolved.relative_to(project_resolved).as_posix()
    except (OSError, ValueError):
        return None


def _record_guarded_write(project: Path, apd_role: str, file_path: str) -> None:
    """Record a short-lived proof that apd_guard_write cleared this target.

    Codex file-edit hooks use this cache to enforce the "call guard before
    every write" rule for apply_patch/Edit/Write tools. The cache lives under
    .apd/pipeline so normal file edits cannot forge it without hitting the
    protected pipeline-state guards.
    """
    rel = _project_relative_path(project, file_path)
    if not rel:
        return
    pipeline_dir = project / ".apd" / "pipeline"
    try:
        pipeline_dir.mkdir(parents=True, exist_ok=True)
        with (pipeline_dir / ".guarded-writes").open("a", encoding="utf-8") as fh:
            fh.write(f"{int(time.time())}|{rel}|{apd_role}\n")
    except OSError:
        pass


def _budget_status(value: int, green_max: int, yellow_max: int) -> str:
    """Classify a budget counter as green/yellow/red.

    green  — value is well inside the recommended budget
    yellow — value is approaching the limit; consider decomposing
    red    — value is past the yellow threshold; strongly consider splitting

    All three budgets are advisory — no gate blocks on status.
    """
    if value <= green_max:
        return "green"
    if value <= yellow_max:
        return "yellow"
    return "red"


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
        "budgets": {
          "spec_criteria":  {"value": int, "budget_green": 4, "budget_yellow": 7, "status": "green"|"yellow"|"red"},
          "reviewed_files": {"value": int, "lean_budget": 4,   "status": "green"|"yellow"|"red"},
          "verifier_duration_s": int | null
        },
        "next_step":           "spec" | "builder" | "reviewer" | "verifier" | "commit" | None
      }

    Budgets are advisory visibility — no gate blocks on status. Use
    them to decide Lean vs Full (reviewed_files `green` with ≤ 2
    criteria = Lean-eligible) or to notice when a task is sprawling
    past the recommended size.
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

    # Soft phase budgets — advisory only, no gate enforces status.
    # Spec criteria: green 1-4 (comfortable), yellow 5-7 (approaching the
    # hard limit of 7 enforced by pipeline-advance spec).
    # Reviewed files: green 0-4 (Lean-eligible when criteria also ≤ 2),
    # yellow 5-6 (borderline — prefer Full), red 7+ (consider splitting
    # the task across multiple pipeline cycles).
    # Verifier duration: time elapsed between reviewer.done and
    # verifier.done; null until verifier completes. No threshold — the
    # value is informational and project-dependent.
    spec_count = state["spec_card"]["criteria_count"]
    reviewed_count = state["reviewed_files"]

    verifier_duration: int | None = None
    reviewer_ts = state["steps"].get("reviewer", {}).get("ts", 0)
    verifier_ts = state["steps"].get("verifier", {}).get("ts", 0)
    if reviewer_ts and verifier_ts and verifier_ts >= reviewer_ts:
        verifier_duration = verifier_ts - reviewer_ts

    state["budgets"] = {
        "spec_criteria": {
            "value": spec_count,
            "budget_green": 4,
            "budget_yellow": 7,
            "status": _budget_status(spec_count, 4, 7),
        },
        "reviewed_files": {
            "value": reviewed_count,
            "lean_budget": 4,
            "status": _budget_status(reviewed_count, 4, 6),
        },
        "verifier_duration_s": verifier_duration,
    }

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

    Intended use: orchestrator calls this once per pipeline to discover
    which roles exist and which is currently active. Scope enforcement on
    writes happens inside apd_guard_write(role, file_path) — the server
    re-reads scope from this same registry, so clients cannot widen it by
    passing inflated path lists.
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

    The `reviewer` step also writes `.adversarial-pending` (when the
    project ships an adversarial-reviewer agent and the spec has not opted
    out) — that marker is the green light for `apd:apd_adversarial_pass`.
    Calling `apd_adversarial_pass` before `reviewer.done` is signed is
    refused by the pre-flight gate (v6.1 B1).
    """
    allowed = {"spec", "builder", "reviewer", "verifier", "init",
               "status", "stats", "metrics", "reset", "rollback"}
    if step not in allowed:
        return {"ok": False, "error": f"unknown step '{step}'. Allowed: {sorted(allowed)}"}
    args = [step] + ([arg] if arg else [])
    return _run_core("pipeline-advance", *args, timeout=30)


@mcp.tool()
def apd_guard_write(apd_role: str, file_path: str) -> dict:
    """Check whether a Write/Edit target falls inside `apd_role`'s configured scope.

    The parameter is named `apd_role` (not `role`) on purpose: Codex 0.121.0's
    multi_agent feature treats a literal `role` field in MCP tool arguments as
    a request to switch agent context, which surfaces as a "Role mismatch"
    approval prompt on every call. The APD-prefixed name sidesteps that
    detection without changing semantics.

    Scope is read from the server-side agent registry (.claude/agents/<apd_role>.md
    on CC/hybrid projects, .apd/agents/<apd_role>.md on pure-Codex), NOT from
    client arguments. This closes the earlier loophole where the orchestrator
    could widen its own scope by passing inflated `allowed_paths`.

    - apd_role is required and must match a file in the agent registry.
    - readonly agents (frontmatter `readonly: true`) always BLOCK.
    - Agents with no `scope` list ALLOW all writes (unscoped role).

    Wraps bin/core/guard-scope. Exit 2 = BLOCK, exit 0 = ALLOW.
    """
    if not apd_role:
        return {"ok": False, "error": "apd_role is required"}
    if not file_path:
        return {"ok": False, "error": "file_path is required"}

    # apd_role must be a bare identifier — reject any path separators, parent
    # refs, or whitespace. Without this, a client could pass "../../outside"
    # to make an attacker-placed outside.md (with scope: [/]) the authority.
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", apd_role) or apd_role in (".", ".."):
        return {"ok": False, "error": f"invalid apd_role '{apd_role}' — must match [A-Za-z0-9_.-]+"}

    project = _project_dir()
    agents_dir = _agents_dir(project)
    if agents_dir is None:
        return {
            "ok": False,
            "error": "no agent registry found — create .apd/agents/ or .claude/agents/",
        }

    agent_file = agents_dir / f"{apd_role}.md"
    # Defense in depth: the resolved agent file must live directly inside
    # agents_dir. If the basename whitelist ever misses something, this
    # still confines registry lookups to the project-owned agents dir.
    try:
        agents_dir_resolved = agents_dir.resolve()
        agent_file_resolved = agent_file.resolve()
        if agent_file_resolved.parent != agents_dir_resolved:
            raise ValueError("escapes agents dir")
    except (OSError, ValueError):
        return {
            "ok": False,
            "error": f"apd_role '{apd_role}' resolves outside {agents_dir}",
        }

    if not agent_file.exists():
        return {
            "ok": False,
            "error": f"unknown apd_role '{apd_role}' — no file at {agent_file}",
        }

    fm = _parse_agent_frontmatter(agent_file)
    if not fm:
        return {
            "ok": False,
            "error": f"could not parse agent frontmatter at {agent_file}",
        }

    readonly = fm.get("readonly", False)
    if isinstance(readonly, str):
        readonly = readonly.lower() in ("true", "yes", "1")
    if readonly:
        return {
            "ok": False,
            "exit_code": 2,
            "stdout": "",
            "stderr": f"apd_role '{apd_role}' is read-only — writes blocked by registry",
        }

    scope = fm.get("scope", [])
    if not isinstance(scope, list):
        scope = []

    result = _run_core("guard-scope", "--file-path", file_path, *scope, timeout=5)
    if result.get("ok") is True:
        _record_guarded_write(project, apd_role, file_path)
    return result


_VERIFY_SCOPES = ("full", "fast")


@mcp.tool()
def apd_verify_step(scope: str = "full") -> dict:
    """Run the project-level verify-all script.

    Looks up a per-project verifier in Codex-native (.codex/bin/verify-all.sh)
    first, then legacy CC (.claude/bin/verify-all.sh) as fallback for hybrid
    setups. If neither exists, delegates to the framework default at
    bin/core/verify-all.

    scope — selects how much work the verifier does:
      "full" (default) — complete build + test suite; use before advancing
                         the verifier gate and on pre-commit checks.
      "fast"           — build + targeted tests only (touched files'
                         direct test deps). For iteration during the
                         builder REFACTOR cycle, where the goal is a quick
                         signal rather than exhaustive verification.

    The scope is exposed to verify-all.sh via the `APD_VERIFY_SCOPE`
    environment variable. A verify-all.sh that has not been customised for
    fast mode will still honor the request by running its full logic —
    that's always safe, just not the optimisation the caller hoped for.

    pipeline-advance verifier always runs with "full" (it invokes
    verify-all.sh directly without the env var set).
    """
    scope = (scope or "full").strip().lower()
    if scope not in _VERIFY_SCOPES:
        return {
            "ok": False,
            "error": f"invalid scope '{scope}' — must be one of {_VERIFY_SCOPES}",
        }

    project = _project_dir()
    env = _codex_env(project)
    env["APD_VERIFY_SCOPE"] = scope
    for rel in (".codex/bin/verify-all.sh", ".claude/bin/verify-all.sh"):
        project_verify = project / rel
        if not project_verify.exists():
            continue
        try:
            result = subprocess.run(
                ["bash", str(project_verify)],
                capture_output=True, text=True, timeout=300, cwd=str(project),
                env=env,
            )
            return {
                "ok": result.returncode == 0,
                "exit_code": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "source": "project",
                "scope": scope,
            }
        except subprocess.TimeoutExpired:
            return {"ok": False, "error": f"{rel} timed out after 300s", "scope": scope}
    result = _run_core("verify-all", timeout=300, env_extra={"APD_VERIFY_SCOPE": scope})
    result["source"] = "framework"
    result["scope"] = scope
    return result


_ADV_NOTES_MIN_CHARS = 80


@mcp.tool()
def apd_adversarial_pass(total: int, accepted: int, dismissed: int, notes: str = "") -> dict:
    """Record the result of an adversarial review pass.

    Writes `ADVERSARIAL:<total>:<accepted>:<dismissed>` to
    `$PIPELINE_DIR/.adversarial-summary` so `pipeline-advance` can include the
    findings in the session log when the pipeline closes.

    total     — findings raised by the adversarial reviewer
    accepted  — findings the builder acted on
    dismissed — findings the builder rejected with rationale
    notes     — free-text rationale. REQUIRED (>= 80 chars) when total == 0
                so a "0 findings" pass cannot be a silent rubber-stamp.
                Describe which categories were examined (regressions,
                concurrency, edge cases, contract drift, security) and why
                nothing was flagged. For total > 0 notes is informational.

    On Codex there is no sub-agent dispatch log to verify the reviewer
    actually ran, so the empty-pass loophole — writing ADVERSARIAL:0:0:0
    without any review — is closed here at the recording step instead.

    Pre-flight gate (v6.1 B1): refuses when `reviewer.done` is absent or
    `.adversarial-pending` is missing. The order must be
    builder → reviewer.done → adversarial → verifier; the marker is
    written by `apd:apd_advance_pipeline('reviewer')`.
    """
    if total < 0 or accepted < 0 or dismissed < 0:
        return {"ok": False, "error": "counts must be non-negative"}
    if accepted + dismissed > total:
        return {"ok": False, "error": "accepted + dismissed cannot exceed total"}

    notes = (notes or "").strip()
    if total == 0 and len(notes) < _ADV_NOTES_MIN_CHARS:
        return {
            "ok": False,
            "error": (
                f"adversarial pass with 0 findings requires substantive notes "
                f"(>= {_ADV_NOTES_MIN_CHARS} chars). Describe which categories "
                "you examined — regressions, concurrency, edge cases, contract "
                "drift, security — and why nothing was flagged. An empty "
                "0/0/0 record is not accepted, and `notes` shorter than the "
                "minimum reads as a rubber-stamp."
            ),
        }

    pipeline_dir = _project_dir() / ".apd" / "pipeline"
    if not pipeline_dir.is_dir():
        return {"ok": False, "error": f"pipeline dir does not exist: {pipeline_dir}"}

    # Adversarial pre-flight gate (v6.1 B1) — record only after the regular
    # reviewer has signed reviewer.done and pipeline-advance reviewer has
    # written .adversarial-pending as the green light. Blocks the
    # orchestrator from recording an adversarial pass against stale or
    # not-yet-reviewed code.
    if not (pipeline_dir / "reviewer.done").is_file():
        return {
            "ok": False,
            "error": (
                "adversarial pass refused: reviewer.done is not present. "
                "Order: builder → reviewer (signs reviewer.done) → adversarial → "
                "verifier. Run apd:apd_advance_pipeline('reviewer') first; it "
                "creates .adversarial-pending as the green light to record."
            ),
        }
    if not (pipeline_dir / ".adversarial-pending").is_file():
        return {
            "ok": False,
            "error": (
                "adversarial pass refused: .adversarial-pending marker is "
                "absent. Either adversarial was opted out for this task "
                "(small spec — see spec-card.md `adversarial: skip`) or it "
                "has already been recorded. Inspect .adversarial-summary "
                "to confirm."
            ),
        }

    summary = pipeline_dir / ".adversarial-summary"
    line = f"ADVERSARIAL:{total}:{accepted}:{dismissed}"
    if notes:
        summary.write_text(f"{line}\n\nNotes:\n{notes}\n")
    else:
        summary.write_text(f"{line}\n")
    return {"ok": True, "path": str(summary), "line": line}


@mcp.tool()
def apd_pipeline_metrics(limit: int = 0) -> dict:
    """Read recent pipeline run metrics from .apd/memory/pipeline-metrics.log.

    Each line records one completed pipeline cycle: timestamps for every
    phase, status, adversarial summary, and agent counts. The log is
    pipe-delimited:

        epoch|task|spec_ts|builder_ts|reviewer_ts|verifier_ts|status
              |adv_total|adv_accepted|adv_dismissed
              |agents_total|agents_exhausted

    Args:
        limit: Return only the most recent N runs (0 = all, capped at 200).

    Returns:
        {"ok": True, "total": <int>, "runs": [<run dict>, ...]}
        Each run dict has timestamp, task, spec_ts, builder_ts, reviewer_ts,
        verifier_ts, status, adversarial_total, adversarial_accepted,
        adversarial_dismissed, agents_total, agents_exhausted.
        On parse failures the malformed line is skipped.
    """
    project = _project_dir()
    if not project:
        return {"ok": False, "error": "no project resolved"}

    metrics_log = project / ".apd" / "memory" / "pipeline-metrics.log"
    if not metrics_log.exists() or metrics_log.stat().st_size == 0:
        return {"ok": True, "total": 0, "runs": []}

    if limit < 0:
        limit = 0
    if limit > 200:
        limit = 200

    try:
        raw = metrics_log.read_text().splitlines()
    except OSError as e:
        return {"ok": False, "error": str(e)}

    lines = [ln for ln in raw if ln.strip() and not ln.startswith("#")]
    total = len(lines)
    if limit > 0:
        lines = lines[-limit:]

    def _int(s: str) -> int:
        try:
            return int(s)
        except (ValueError, TypeError):
            return 0

    runs: list[dict] = []
    for ln in lines:
        parts = ln.split("|")
        if len(parts) < 7:
            continue
        while len(parts) < 12:
            parts.append("")
        runs.append({
            "timestamp": parts[0],
            "task": parts[1],
            "spec_ts": _int(parts[2]),
            "builder_ts": _int(parts[3]),
            "reviewer_ts": _int(parts[4]),
            "verifier_ts": _int(parts[5]),
            "status": parts[6],
            "adversarial_total": _int(parts[7]),
            "adversarial_accepted": _int(parts[8]),
            "adversarial_dismissed": _int(parts[9]),
            "agents_total": _int(parts[10]),
            "agents_exhausted": _int(parts[11]),
        })

    return {"ok": True, "total": total, "runs": runs}


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
