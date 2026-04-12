# Runtime Contract — Adapter Layer Refactoring Design

## Overview

Extract CC-specific stdin parsing from 8 mixed guards into thin adapter shims (`bin/adapter/cc/`). Core guards in `bin/core/` receive normalized input via CLI args. Implements Phase 2 of ADR-001.

## Problem

Every guard script directly parses Claude Code hook stdin JSON (`jq -r '.tool_input.command'`). This creates two issues:

1. **Fragility** — CC protocol changes break all guards simultaneously.
2. **Untestability** — guards can only be tested by running inside CC hooks.

Analysis shows the coupling is shallow: all 8 mixed guards use the same 4-line pattern (`INPUT=$(cat); FIELD=$(echo "$INPUT" | jq ...)`), extracting 1-3 fields. The core policy logic (path checking, command scanning, extension matching) is already runtime-agnostic.

## Solution

### Directory layout

```
bin/
├── adapter/
│   └── cc/                          # Claude Code adapter shims
│       ├── guard-git
│       ├── guard-bash-scope
│       ├── guard-scope
│       ├── guard-orchestrator
│       ├── guard-pipeline-state
│       ├── guard-lockfile
│       ├── track-agent
│       └── pipeline-post-commit
├── core/                            # Runtime-agnostic (args interface)
│   ├── guard-git                    # Refactored: reads --command, --agent-id, --agent-type
│   ├── guard-bash-scope             # Refactored: reads --command + positional paths
│   ├── guard-scope                  # Refactored: reads --file-path + positional paths
│   ├── guard-orchestrator           # Refactored: reads --file-path, --agent-id
│   ├── guard-pipeline-state         # Refactored: reads --file-path
│   ├── guard-lockfile               # Refactored: reads --file-path
│   ├── track-agent                  # Refactored: reads --event, --agent-type, --agent-id
│   ├── pipeline-post-commit         # Refactored: reads --command
│   ├── guard-send-message           # Unchanged (no stdin, filesystem-only)
│   ├── guard-permission-denied      # Unchanged (CC-only telemetry, no core equivalent)
│   ├── session-start                # Unchanged (no stdin, deferred to Phase 3)
│   ├── pipeline-advance             # Unchanged (already core)
│   ├── pipeline-gate                # Unchanged (already core)
│   └── ...
```

### Adapter shim pattern

Each shim: reads CC stdin JSON, extracts fields, calls core with args.

```bash
#!/usr/bin/env bash
# CC adapter shim for guard-scope
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../../core"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

exec "$CORE_DIR/guard-scope" --file-path "$FILE_PATH" "$@"
```

### Core args interface

Each core guard replaces `INPUT=$(cat)` + `jq` with a `while` loop parsing named args:

```bash
FILE_PATH=""
ALLOWED_PATHS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file-path) FILE_PATH="$2"; shift 2 ;;
    *) ALLOWED_PATHS+=("$1"); shift ;;
  esac
done
```

### Args per guard

| Guard | Named args | Positional args |
|-------|-----------|----------------|
| guard-lockfile | `--file-path` | -- |
| guard-pipeline-state | `--file-path` | -- |
| guard-scope | `--file-path` | allowed paths |
| guard-orchestrator | `--file-path`, `--agent-id` | -- |
| guard-bash-scope | `--command` | allowed paths |
| guard-git | `--command`, `--agent-id`, `--agent-type` | -- |
| track-agent | `--event`, `--agent-type`, `--agent-id` | -- |
| pipeline-post-commit | `--command` | -- |

### hooks.json changes

All hook commands pointing to refactored guards change path from `core/` to `adapter/cc/`:

```json
// Before
"command": "bash ${CLAUDE_PLUGIN_ROOT}/bin/core/guard-scope src/ tests/"

// After
"command": "bash ${CLAUDE_PLUGIN_ROOT}/bin/adapter/cc/guard-scope src/ tests/"
```

Positional args (allowed paths) pass through the shim unchanged via `"$@"`.

### agent-template.md changes

Agent template hook paths update from `core/` to `adapter/cc/` for: `guard-scope`, `guard-bash-scope`, `guard-git`.

### apd-init changes

Generated agent files use `adapter/cc/` paths instead of `core/`.

### verify-apd changes

Test suite checks new `adapter/cc/` paths exist and are executable. Core guard testability checks added (direct args invocation without CC).

## What is NOT changed

- `guard-send-message` — no stdin, pure filesystem check
- `guard-permission-denied` — CC-only telemetry, no core logic to extract
- `session-start` — no stdin, complex CC coupling, deferred to Phase 3
- `pipeline-advance`, `pipeline-gate`, `pipeline-doctor` — already pure core
- `verify-trace`, `verify-contracts`, `verify-all` — already pure core
- `gh-sync`, `rotate-session-log` — already pure core
- Go binaries — already runtime-agnostic
- `resolve-project.sh` — mixed but not a guard; `CLAUDE_PLUGIN_ROOT` fallback is acceptable for now

## Migration order

Ordered by complexity (simplest first, establishes pattern):

1. `guard-lockfile` — 1 field, simplest guard, proof of concept
2. `guard-pipeline-state` — 1 field, nearly identical pattern
3. `guard-scope` — 1 field + positional args passthrough
4. `guard-orchestrator` — 2 fields, branches on `agent_id`
5. `guard-bash-scope` — command parsing + positional args
6. `guard-git` — most complex, 3 fields, many blocking rules
7. `track-agent` — 3 fields, different event type (SubagentStart/Stop)
8. `pipeline-post-commit` — 1 field, PostToolUse event

Each guard: create shim, refactor core to args, update hooks.json path, test both layers.

## Risks

- **Plugin cache:** Installed plugins have cached hooks.json. Path change applies on next `plugin update`. Must be backward-compatible during transition — keep core guards functional if called directly (they just won't receive args and will fail safely).
- **Existing projects:** Projects with generated agent files reference `core/` paths. `apd-init` update mode should detect and fix stale paths.
- **Command escaping:** `--command` arg for guard-git and guard-bash-scope can contain shell metacharacters. Double-quoting in shim (`"$COMMAND"`) handles this. Core must not eval the command string.

## Testability after refactoring

```bash
# Direct core testing — no CC required
bash bin/core/guard-lockfile --file-path "package-lock.json"
# exit 2 (blocked)

bash bin/core/guard-scope --file-path "src/auth/login.ts" src/ tests/
# exit 0 (allowed)

bash bin/core/guard-scope --file-path "apps/frontend/App.tsx" src/ tests/
# exit 2 (blocked)

bash bin/core/guard-orchestrator --file-path "src/main.ts" --agent-id ""
# exit 2 (blocked — orchestrator writing code)

bash bin/core/guard-orchestrator --file-path "src/main.ts" --agent-id "abc123"
# exit 0 (allowed — agent, not orchestrator)

bash bin/core/guard-git --command "git commit -m 'test'" --agent-id "" --agent-type ""
# exit 2 (blocked — missing APD_ORCHESTRATOR_COMMIT=1)
```
