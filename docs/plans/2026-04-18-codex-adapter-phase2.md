# Codex Adapter — Phase 2 Plan (Hybrid Enforcement)

**Supersedes:** `2026-04-18-codex-adapter-phase1.md` for the enforcement model. Phase 1 scaffolding (plugin.json, adapter shim) is kept structurally but its hooks-only assumption is dropped.

**Source of truth:** `.claude/memory/reference-codex-enforcement-layers.md`

## Goal

Ship a working APD experience on Codex CLI 0.121+ using Codex's **stable** enforcement surfaces. Do not wait for `codex_hooks` to graduate from experimental.

## Enforcement mapping

| APD guardrail | CC runtime | Codex runtime (new) |
|---|---|---|
| Write/Edit out-of-scope block | `guard-scope` hook (PreToolUse Write) | **Sandbox `writable_roots`** — OS-enforced, unbypassable |
| Bash write out-of-scope block | `guard-bash-scope` hook (PreToolUse Bash) | `hooks.json` PreToolUse Bash (same as CC) + sandbox as backup |
| Destructive git block | `guard-git` hook | `hooks.json` PreToolUse Bash with `matcher: "Bash"` + command sniff |
| Lockfile direct-edit block | `guard-lockfile` hook | Sandbox (lockfile not in `writable_roots` for agent role) |
| Pipeline state file protection | `guard-pipeline-state` hook | MCP tool — pipeline state modified only via `apd_advance_pipeline` |
| Agent dispatch tracking | `SubagentStart`/`SubagentStop` hooks | MCP tool — agents dispatched via `apd_dispatch_agent` |
| Signed `.done` step output | `validate-agent-*` Go binary | Unchanged — core/ binary runs from MCP tool handler |
| Session context injection | `session-start` stdout | `hooks.json` SessionStart (exists in Codex, stable-ish) OR model memory |

**Result:** stronger enforcement on writes (OS vs. hook), equal on Bash, coordinated via MCP for state machine.

## Architecture

```
apd-template/
├── .claude-plugin/plugin.json          # existing, CC
├── .codex-plugin/plugin.json           # existing, Codex — updated to declare MCP server
├── bin/
│   ├── core/                           # unchanged, runtime-agnostic
│   ├── adapter/cc/                     # unchanged
│   └── adapter/cdx/
│       ├── guard-bash-scope            # existing
│       ├── mcp-server                  # NEW — MCP server entrypoint (bash wrapper around Go/Node implementation)
│       └── apply-sandbox               # NEW — writes permission profile to project ~/.codex/config.toml
├── hooks/
│   ├── hooks.json                      # existing, CC
│   └── hooks.codex.json                # NEW purpose — installed at <repo>/.codex/hooks.json by apd init (NOT plugin-scoped)
└── mcp/
    └── apd-mcp-server.{go,py,js}        # NEW — implements MCP tools
```

## Phase 2 tasks

### Task 1 — Decide MCP implementation language

Options:
- **Go** — reuse `cmd/` tree, ship compiled binary like `validate-agent-*`. Pro: consistent with existing Go enforcement. Con: MCP SDK maturity.
- **Python** — official MCP Python SDK is mature, fast to iterate. Con: runtime dep on `python3` (already required by Codex's plugin-creator).
- **Node** — MCP TS SDK is reference implementation. Con: adds Node runtime dep.

**Recommendation:** Python. Matches Codex ecosystem conventions, official SDK, no new runtime. User confirms or picks alternative.

### Task 2 — Define MCP tool surface

Minimum viable tools:
- `apd_guard_write(path, content_preview)` → `{allow, reason}` — model can ask before writing (cooperative backup to sandbox)
- `apd_advance_pipeline(from_step, to_step, evidence)` → `{ok, signed_path}` — only path that mutates pipeline state
- `apd_dispatch_agent(agent_name, task)` → `{agent_id, scope_paths, sandbox_profile}` — returns the profile Codex should use for that agent's session
- `apd_verify_step(step_name)` → `{pass, report}` — runs verify-apd gates
- `apd_adversarial_pass(pipeline_id)` → `{pass, findings}` — mandatory gate before commit

Each tool is a thin wrapper around existing `bin/core/*` scripts.

### Task 3 — Sandbox profile generator

`bin/adapter/cdx/apply-sandbox` reads `.apd-config` + agent definitions and writes per-agent permission profiles to `<repo>/.codex/config.toml`:

```toml
[permissions.apd-builder-backend]
default = "workspace-write"
[permissions.apd-builder-backend.filesystem]
writable_roots = ["./src/backend", "./tests/backend", "./.apd/pipeline"]
```

When orchestrator dispatches backend-builder agent via `apd_dispatch_agent`, response includes `sandbox_profile: "apd-builder-backend"` — Codex uses that profile for the agent's exec session.

### Task 4 — Hooks.json at repo level

`apd init` writes `<repo>/.codex/hooks.json` with PreToolUse Bash pointing to `bin/adapter/cdx/guard-bash-scope`. Covers:
- Destructive git detection (`--no-verify`, force push, `rm -rf`)
- Out-of-scope bash writes that slip past sandbox (edge case)

NOT placed in plugin-scoped `./hooks.json` — Phase 1 test showed plugin-scoped hooks unreliable. User/repo scope is canonical per docs.

### Task 5 — Update `.codex-plugin/plugin.json`

Remove `"hooks": "./hooks/hooks.codex.json"` (plugin-scoped hooks unreliable).
Add `"mcpServers": "./.mcp.json"` — manifest points at Codex's standard MCP config which lists our server.

Create `.mcp.json` (user-level copy written by `apd init` to `~/.codex/config.toml` as `[mcp_servers.apd]` block).

### Task 6 — End-to-end smoke test

Test project `~/Projects/Test/codex-apd-test/` with:
- APD installed via `apd init` (writes hooks.json + mcp_servers entry + permission profiles to Codex config)
- Run `codex` in TUI, start fake pipeline, verify:
  - [ ] Write outside `writable_roots` blocked by Codex sandbox (OS-level)
  - [ ] `rm -rf` in Bash blocked by hooks.json
  - [ ] Pipeline can advance only via `apd_advance_pipeline` MCP tool
  - [ ] Adversarial review gate called via MCP before commit
  - [ ] Agent dispatch logged via MCP

### Task 7 — Tag + PR

`v4.8.0-alpha.1` when Task 6 passes. Draft PR with Phase 2 exit criteria checklist.

## Open questions for kickoff

1. MCP language (Go/Python/Node) — Python is recommendation
2. Do we ship the MCP server inside the plugin, or as a separate process the user installs via pip/npm?
3. `apd init` for Codex — does it modify user's `~/.codex/config.toml` (write permission profiles globally) or only repo-level `<repo>/.codex/config.toml`? Repo-level is safer and reversible.
4. Sandbox profiles per agent role (backend-builder, frontend-builder, reviewer) — do we generate one per agent or use one shared?

## Risk

Codex MCP + sandbox + hooks are all stable/mature — enforcement posture is **stronger** than CC APD for writes. Main risk is MCP tool discoverability (model may not know to call `apd_advance_pipeline` vs. doing a direct git commit). Mitigation: `apd init` installs a Codex skill (`skills/apd-workflow/SKILL.md`) that teaches the model the workflow, reusable between CC and Codex.
