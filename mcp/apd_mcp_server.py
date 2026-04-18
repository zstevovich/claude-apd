#!/usr/bin/env python3
"""APD MCP server — exposes APD pipeline operations as MCP tools.

Phase 2 walking skeleton. Starts with apd_ping to prove the wiring end-to-end.
Real tools (apd_advance_pipeline, apd_dispatch_agent, apd_guard_write,
apd_adversarial_pass) land in subsequent commits.

Requires: pip install 'mcp>=1.0' (or invoke via `uvx --from mcp ...`).
"""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

from mcp.server.fastmcp import FastMCP

APD_PLUGIN_ROOT = Path(__file__).resolve().parent.parent
APD_PLUGIN_MANIFEST = APD_PLUGIN_ROOT / ".claude-plugin" / "plugin.json"

mcp = FastMCP("apd")


def _read_version() -> str:
    if APD_PLUGIN_MANIFEST.exists():
        try:
            data = json.loads(APD_PLUGIN_MANIFEST.read_text())
            return data.get("version", "unknown")
        except json.JSONDecodeError:
            pass
    return "unknown"


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
        "runtime": "codex",
        "phase": "2-alpha",
    }


@mcp.tool()
def apd_doctor() -> dict:
    """Run APD self-check — delegates to bin/core/pipeline-doctor.

    Returns raw doctor output so the model can surface issues to the user
    before starting a pipeline.
    """
    doctor = APD_PLUGIN_ROOT / "bin" / "core" / "pipeline-doctor"
    if not doctor.exists():
        return {"ok": False, "error": f"pipeline-doctor not found at {doctor}"}
    try:
        result = subprocess.run(
            ["bash", str(doctor)],
            capture_output=True,
            text=True,
            timeout=10,
            cwd=os.getcwd(),
        )
        return {
            "ok": result.returncode == 0,
            "exit_code": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "pipeline-doctor timed out after 10s"}


if __name__ == "__main__":
    mcp.run()
