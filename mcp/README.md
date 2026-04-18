# APD MCP Server

Exposes APD pipeline operations as Model Context Protocol tools for Codex runtime.

## Install

```bash
pip install --user -r mcp/requirements.txt
# or (isolated)
uvx --from mcp --with-requirements mcp/requirements.txt python mcp/apd_mcp_server.py
```

## Wire into Codex

Add to `<repo>/.codex/config.toml`:

```toml
[mcp_servers.apd]
command = "python3"
args = ["/absolute/path/to/apd-template/mcp/apd_mcp_server.py"]
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
