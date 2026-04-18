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

## Tools (Phase 2 walking skeleton)

- `apd_ping` — health check; returns version + plugin root
- `apd_doctor` — runs `bin/core/pipeline-doctor` and returns output

## Coming in Phase 2

- `apd_advance_pipeline(from_step, to_step, evidence)`
- `apd_dispatch_agent(agent_name, task)`
- `apd_guard_write(path, content_preview)`
- `apd_adversarial_pass(pipeline_id)`
- `apd_verify_step(step_name)`
