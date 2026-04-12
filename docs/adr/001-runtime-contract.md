# ADR-001: APD Runtime Contract and Adapter Architecture

**Status:** Accepted
**Date:** 2026-04-12

## Context

APD enforcement works. Guards block, pipeline advances with signed steps, adversarial review catches issues. But every component implicitly depends on Claude Code's hook protocol — a protocol that is undocumented, versioned unpredictably, and has known quirks (e.g., `SendMessage` bypassing `SubagentStart`/`SubagentStop` hooks).

Today, the coupling surfaces in four places:

1. **Hook stdin JSON** — every guard reads `tool_input.command`, `tool_input.file_path`, `agent_id`, `agent_type`, `hook_event_name` from stdin. If CC changes field names, all guards break simultaneously.
2. **`agent_id` absence as orchestrator signal** — `guard-orchestrator` infers "top-level session" from `agent_id` being empty. This is undocumented CC behavior, not a stable API.
3. **`SendMessage` hook gap** — `guard-send-message` exists solely because CC's `SendMessage` skips `SubagentStart`/`SubagentStop`. A CC quirk encoded as a guard.
4. **stdout-as-context-injection** — `session-start` uses stdout to inject context into the model's window. Load-bearing but undocumented.

This makes APD fragile to CC updates and impossible to port to other runtimes (Copilot CLI, Codex, Gemini CLI, custom Agent SDK builds). The compiled Go binaries, pipeline state machine, and verification tools are already runtime-agnostic — the coupling is in the I/O layer, not the logic.

## Decision

### 1. Define the APD Runtime Contract

Every runtime adapter must deliver these seven events to the APD core:

| # | Event | Required Fields | Description |
|---|-------|----------------|-------------|
| 1 | **identity** | `role` (orchestrator\|agent), `agent_name`, `agent_id`, `session_id` | Who is executing. Orchestrator has no `agent_id`. |
| 2 | **dispatch_start** | `agent_name`, `agent_id`, `timestamp` | An agent has been dispatched. |
| 3 | **dispatch_stop** | `agent_name`, `agent_id`, `timestamp`, `exit_status` | An agent has finished. |
| 4 | **tool_request** | `tool_name`, `tool_input` (object), `identity` | A tool is about to execute. Guard response: `allow` or `block(reason)`. |
| 5 | **tool_result** | `tool_name`, `tool_input`, `exit_code`, `files_touched[]` | A tool has finished executing. |
| 6 | **transition_request** | `from_step`, `to_step`, `evidence` (object) | Request to advance the pipeline state machine. |
| 7 | **audit_entry** | `timestamp`, `event_type`, `actor`, `detail` | Append-only log of all significant actions. |

**Event format:** JSON, one object per event. The core never parses runtime-native formats directly.

**Guard protocol:** For `tool_request` events, the core returns a verdict:
```json
{ "action": "allow" }
{ "action": "block", "reason": "Write outside allowed paths: src/unrelated/file.ts" }
```

### 2. Classify all components as Core or Adapter

**Core** — runtime-agnostic, receives normalized contract events:

| Component | Role |
|-----------|------|
| `pipeline-advance` | State machine: spec → builder → reviewer → verifier → commit |
| `pipeline-gate` | Pre-commit verification of all signed `.done` files |
| `pipeline-doctor` | Read-only diagnostic reporter |
| `validate-agent-*` | Signed `.done` file creation and verification (Go binaries) |
| `verify-trace` | `@trace R*` acceptance criteria coverage checker |
| `verify-contracts` | Backend/frontend type contract validation |
| `verify-all` | Per-project build + test orchestration template |
| `rotate-session-log` | Session log archival |
| `gh-sync` | GitHub Projects v2 synchronization |
| `guard-pipeline-state` | Blocks direct writes to pipeline state files |
| `guard-lockfile` | Blocks direct edits to dependency lock files |
| `style.sh` | ANSI output and audit log writing |

**Adapter** (Claude Code) — translates CC hook protocol into contract events:

| Component | Role |
|-----------|------|
| `hooks.json` | CC event registration (all matchers, conditions, env vars) |
| `agent-template.md` | CC subagent definition with CC-proprietary frontmatter |
| `guard-send-message` | CC-specific workaround for `SendMessage` hook gap |
| `guard-permission-denied` | CC-specific `PermissionDenied` event telemetry |
| Skills (`skills/`) | CC skill format (YAML frontmatter, `Skill` tool invocation) |

**Mixed** (policy logic + CC I/O parsing — to be split):

| Component | Core logic | Adapter glue |
|-----------|-----------|--------------|
| `guard-git` | Git operation policy (no `--no-verify`, no force push, etc.) | Reads `tool_input.command` from CC hook stdin JSON |
| `guard-bash-scope` | Write-detection patterns, path enforcement | Reads `tool_input.command` from CC hook stdin JSON |
| `guard-scope` | Path-prefix enforcement | Reads `tool_input.file_path` from CC hook stdin JSON |
| `guard-orchestrator` | "Orchestrator must not write code" policy | Infers role from CC `agent_id` presence/absence |
| `track-agent` | Audit trail writing, dispatch-order warnings | Reads `hook_event_name`, `agent_type`, `agent_id` from CC hook stdin |
| `session-start` | Pipeline state surfacing, self-healing | Uses CC stdout-as-context-injection, CC version detection |
| `pipeline-post-commit` | Pipeline reset after commit | Reads `PostToolUse` CC hook event for `git commit` |
| `resolve-project.sh` | Git toplevel + `.apd-config` resolution | `CLAUDE_PLUGIN_ROOT` as primary path source |
| `apd-init` | Gap analysis, file generation | Reads `CLAUDE_PLUGIN_OPTION_*` CC userConfig env vars |
| `verify-apd` | Functional guard testing | CC version compatibility checks |

### 3. Establish the migration path

**Phase 1 — Name it (now).** Recognize the adapter boundary in documentation and mental model. No code changes.

**Phase 2 — Normalize the input layer.** Each mixed guard gets a thin adapter shim that reads CC-specific stdin and emits a normalized `tool_request` JSON. The guard's core logic receives the normalized event. This is a mechanical refactor — extract the `jq` parsing into a wrapper, pass the result as arguments or normalized stdin.

```
CC hook stdin → adapter shim → normalized tool_request → core guard logic → verdict
```

**Phase 3 — Second adapter.** When a second runtime is targeted (e.g., Copilot CLI, Agent SDK), implement its adapter shim. Core guards work unchanged.

## Consequences

**Positive:**
- CC protocol changes break only the adapter shim, not every guard
- Core logic becomes testable without CC — pipe in a `tool_request` JSON, assert the verdict
- Second runtime support becomes a bounded task (write adapter shims + event registration)
- Clear answer for every new feature: "does this belong in core or adapter?"
- Compiled Go binaries are already compliant — zero migration cost

**Negative:**
- Phase 2 adds an indirection layer to every guard (adapter shim + core)
- `guard-send-message` and `guard-permission-denied` have no core equivalent — they exist only because of CC quirks and will remain adapter-only
- Testing must now cover both layers: adapter parsing and core logic
- CC-specific workarounds (e.g., `SendMessage` gap) must still be maintained in the adapter even though they are architecturally distasteful

## Alternatives considered

**1. Full rewrite with a runtime abstraction SDK.**
Rejected. Over-engineering for the current single-runtime reality. The contract is a specification, not a framework — adapters are thin shims, not a plugin system.

**2. Keep the current implicit coupling.**
Rejected. Every CC version bump is a potential breakage across 15+ scripts. The `agent_id`-as-role-discriminator pattern is already fragile. The cost of formalization is low (documentation + mechanical refactoring), the risk of not doing it grows with every CC update.

**3. Wait for a second runtime before abstracting.**
Rejected in part. Phase 1 (naming) and Phase 2 (normalize inputs) are cheap and immediately improve testability. Phase 3 (second adapter) naturally waits for demand.
