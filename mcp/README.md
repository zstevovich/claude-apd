# APD MCP Server

Exposes APD pipeline operations as Model Context Protocol tools for Codex runtime.

## Install

```bash
pip install --user -r mcp/requirements.txt
# or (isolated)
uvx --from mcp --with-requirements mcp/requirements.txt python mcp/apd_mcp_server.py
```

## Wire into Codex

Run the installer helper from your project directory:

```bash
/path/to/apd-template/bin/adapter/cdx/install-codex-config
```

This writes `<project>/.codex/config.toml` with the APD MCP entry. Idempotent — safe to re-run. Use `uv run --with mcp` so no system-wide Python changes are needed (`brew install uv` is the only prereq).

Manual alternative (if you prefer):

```toml
[mcp_servers.apd]
command = "uv"
args = ["run", "--with", "mcp", "python", "/absolute/path/to/apd-template/mcp/apd_mcp_server.py"]
```

Restart `codex`. The `apd_ping` tool should appear in the model's tool list.

## Tools

- `apd_ping` — health check; returns version, plugin root, project dir
- `apd_doctor` — runs `bin/core/pipeline-doctor`
- `apd_advance_pipeline(step, arg="")` — wraps `pipeline-advance spec|builder|reviewer|verifier|init|status|stats|metrics|reset|rollback`
- `apd_guard_write(role, file_path)` — scope is read from the agent registry (`.apd/agents/<role>.md` or `.claude/agents/<role>.md`), NOT client args. Readonly roles always BLOCK. Exit 2 = BLOCK, 0 = ALLOW.
- `apd_verify_step()` — runs project `.codex/bin/verify-all.sh` if present (or legacy `.claude/bin/verify-all.sh`; otherwise framework `bin/core/verify-all`)
- `apd_adversarial_pass(total, accepted, dismissed)` — writes `.adversarial-summary` for session log
- `apd_list_agents()` — returns every agent definition in `.apd/agents/` (or `.claude/agents/` on hybrid) with parsed frontmatter (name, scope, model, maxTurns, readonly)
- `apd_pipeline_state()` — structured snapshot of the pipeline: step `.done` files with timestamps, spec-card criteria count and freeze state, implementation-plan presence, adversarial summary, reviewed-files count, verifier cache, and the next step to advance

## Coming later

- `apd_dispatch_agent(agent_name, task)` — depends on Codex agent-dispatch semantics
