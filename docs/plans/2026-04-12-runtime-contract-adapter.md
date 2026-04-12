# Runtime Contract — Adapter Layer Refactoring

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract CC-specific stdin parsing from 9 mixed guards into thin adapter shims, making core guards testable via CLI args.

**Architecture:** Each mixed guard splits into two files: `bin/adapter/cc/<guard>` (reads CC hook stdin JSON, extracts fields) and `bin/core/<guard>` (receives named args, executes policy logic). Hooks.json and agent templates point to adapter shims.

**Tech Stack:** Bash, jq (adapter only), POSIX args parsing (core)

---

### Task 1: Create adapter directory and guard-lockfile (proof of concept)

**Files:**
- Create: `bin/adapter/cc/guard-lockfile`
- Modify: `bin/core/guard-lockfile`

- [ ] **Step 1: Create the adapter directory**

```bash
mkdir -p bin/adapter/cc
```

- [ ] **Step 2: Create the CC adapter shim for guard-lockfile**

Create `bin/adapter/cc/guard-lockfile`:

```bash
#!/bin/bash
# CC adapter shim for guard-lockfile
# Reads Claude Code hook stdin JSON, passes normalized args to core

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../../core"

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

exec "$CORE_DIR/guard-lockfile" --file-path "$FILE_PATH" "$@"
```

```bash
chmod +x bin/adapter/cc/guard-lockfile
```

- [ ] **Step 3: Refactor core guard-lockfile to accept CLI args**

Replace the full content of `bin/core/guard-lockfile` with:

```bash
#!/bin/bash
# APD Lockfile Guard — prevents modification of lock files
# Interface: --file-path <path>

source "$(dirname "$0")/../lib/resolve-project.sh"
source "$(dirname "$0")/../lib/style.sh"
[ "$APD_ACTIVE" = false ] && exit 0

FILE_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file-path) FILE_PATH="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

BASENAME=$(basename "$FILE_PATH")

case "$BASENAME" in
  package-lock.json|pnpm-lock.yaml|yarn.lock|packages.lock.json|composer.lock|Gemfile.lock|poetry.lock|Cargo.lock|go.sum)
    echo "BLOCKED: Lock file '$BASENAME' must not be modified directly." >&2
    echo "Use the package manager to update." >&2
    log_block "lockfile-write" "$BASENAME"
    exit 2
    ;;
esac

exit 0
```

- [ ] **Step 4: Test core directly**

```bash
bash bin/core/guard-lockfile --file-path "package-lock.json"
# Expected: exit 2, "BLOCKED: Lock file 'package-lock.json'"

bash bin/core/guard-lockfile --file-path "src/main.ts"
# Expected: exit 0

bash bin/core/guard-lockfile --file-path ""
# Expected: exit 0
```

- [ ] **Step 5: Test adapter shim**

```bash
echo '{"tool_input":{"file_path":"package-lock.json"}}' | bash bin/adapter/cc/guard-lockfile
# Expected: exit 2, "BLOCKED"

echo '{"tool_input":{"file_path":"src/main.ts"}}' | bash bin/adapter/cc/guard-lockfile
# Expected: exit 0
```

- [ ] **Step 6: Commit**

```bash
git add bin/adapter/cc/guard-lockfile bin/core/guard-lockfile
git commit -m "refactor: split guard-lockfile into core + CC adapter shim"
```

---

### Task 2: guard-pipeline-state

**Files:**
- Create: `bin/adapter/cc/guard-pipeline-state`
- Modify: `bin/core/guard-pipeline-state`

- [ ] **Step 1: Create CC adapter shim**

Create `bin/adapter/cc/guard-pipeline-state`:

```bash
#!/bin/bash
# CC adapter shim for guard-pipeline-state
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../../core"

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

exec "$CORE_DIR/guard-pipeline-state" --file-path "$FILE_PATH" "$@"
```

```bash
chmod +x bin/adapter/cc/guard-pipeline-state
```

- [ ] **Step 2: Refactor core guard-pipeline-state**

Replace content of `bin/core/guard-pipeline-state` with:

```bash
#!/bin/bash
# APD Pipeline State Guard — blocks direct Write/Edit to .apd/pipeline/ internal files
#
# Only pipeline-advance (via Bash) should create .done, .agents, .spec-hash etc.
# Orchestrator MAY write: spec-card.md, implementation-plan.md, .adversarial-summary
# Orchestrator must NOT write: *.done, .agents, .spec-hash, .trace-summary, verified.timestamp
#
# Interface: --file-path <path>

source "$(dirname "$0")/../lib/resolve-project.sh"
source "$(dirname "$0")/../lib/style.sh"
[ "$APD_ACTIVE" = false ] && exit 0

FILE_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file-path) FILE_PATH="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

REL_PATH="${FILE_PATH#"$PROJECT_DIR"/}"

# Only guard .apd/pipeline/ paths
case "$REL_PATH" in
    .apd/pipeline/*)
        FILENAME=$(basename "$REL_PATH")
        # Allowed files — orchestrator writes these as part of pipeline workflow
        case "$FILENAME" in
            spec-card.md|implementation-plan.md|.adversarial-summary)
                exit 0
                ;;
            *)
                echo "BLOCKED: Direct write to pipeline state file: $FILENAME" >&2
                echo "" >&2
                echo "  Pipeline state is managed by pipeline-advance — do not write directly." >&2
                echo "  Use: bash .claude/bin/apd pipeline <command>" >&2
                log_block "pipeline-state-direct-write" "$FILENAME"
                exit 2
                ;;
        esac
        ;;
    *)
        exit 0
        ;;
esac
```

- [ ] **Step 3: Test core + adapter**

```bash
bash bin/core/guard-pipeline-state --file-path "$PWD/.apd/pipeline/spec.done"
# Expected: exit 2

bash bin/core/guard-pipeline-state --file-path "$PWD/.apd/pipeline/spec-card.md"
# Expected: exit 0

echo '{"tool_input":{"file_path":"'$PWD'/.apd/pipeline/.agents"}}' | bash bin/adapter/cc/guard-pipeline-state
# Expected: exit 2
```

- [ ] **Step 4: Commit**

```bash
git add bin/adapter/cc/guard-pipeline-state bin/core/guard-pipeline-state
git commit -m "refactor: split guard-pipeline-state into core + CC adapter shim"
```

---

### Task 3: guard-scope

**Files:**
- Create: `bin/adapter/cc/guard-scope`
- Modify: `bin/core/guard-scope`

- [ ] **Step 1: Create CC adapter shim**

Create `bin/adapter/cc/guard-scope`:

```bash
#!/bin/bash
# CC adapter shim for guard-scope
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../../core"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed." >&2
  exit 2
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

exec "$CORE_DIR/guard-scope" --file-path "$FILE_PATH" "$@"
```

```bash
chmod +x bin/adapter/cc/guard-scope
```

- [ ] **Step 2: Refactor core guard-scope**

Replace content of `bin/core/guard-scope` with:

```bash
#!/bin/bash
# APD Scope Guard — blocks Write/Edit operations outside the allowed scope
# Interface: --file-path <path> <allowed_path_1> <allowed_path_2> ...

source "$(dirname "$0")/../lib/resolve-project.sh"
source "$(dirname "$0")/../lib/style.sh"
[ "$APD_ACTIVE" = false ] && exit 0

FILE_PATH=""
ALLOWED_PATHS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file-path) FILE_PATH="$2"; shift 2 ;;
    *) ALLOWED_PATHS+=("$1"); shift ;;
  esac
done

if [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
  exit 0
fi

if [ -z "$FILE_PATH" ]; then
  exit 0
fi
REL_PATH="${FILE_PATH#"$PROJECT_DIR"/}"

if [[ "$REL_PATH" == /* ]]; then
  echo "BLOCKED: File $FILE_PATH is outside the project directory." >&2
  echo "Allowed paths: ${ALLOWED_PATHS[*]}" >&2
  log_block "out-of-scope-write" "$REL_PATH"
  exit 2
fi

for allowed in "${ALLOWED_PATHS[@]}"; do
  allowed="${allowed%/}/"
  if [[ "$REL_PATH" == "$allowed"* ]]; then
    exit 0
  fi
done

echo "BLOCKED: File $REL_PATH is outside the allowed scope." >&2
echo "Allowed paths: ${ALLOWED_PATHS[*]}" >&2
log_block "out-of-scope-write" "$REL_PATH"
exit 2
```

- [ ] **Step 3: Test**

```bash
bash bin/core/guard-scope --file-path "$PWD/src/test.ts" src/ tests/
# Expected: exit 0

bash bin/core/guard-scope --file-path "$PWD/apps/other.ts" src/ tests/
# Expected: exit 2

echo '{"tool_input":{"file_path":"'$PWD'/src/test.ts"}}' | bash bin/adapter/cc/guard-scope src/ tests/
# Expected: exit 0
```

- [ ] **Step 4: Commit**

```bash
git add bin/adapter/cc/guard-scope bin/core/guard-scope
git commit -m "refactor: split guard-scope into core + CC adapter shim"
```

---

### Task 4: guard-orchestrator

**Files:**
- Create: `bin/adapter/cc/guard-orchestrator`
- Modify: `bin/core/guard-orchestrator`

- [ ] **Step 1: Create CC adapter shim**

Create `bin/adapter/cc/guard-orchestrator`:

```bash
#!/bin/bash
# CC adapter shim for guard-orchestrator
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../../core"

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)

exec "$CORE_DIR/guard-orchestrator" --file-path "$FILE_PATH" --agent-id "$AGENT_ID" "$@"
```

```bash
chmod +x bin/adapter/cc/guard-orchestrator
```

- [ ] **Step 2: Refactor core guard-orchestrator**

Replace content of `bin/core/guard-orchestrator` with:

```bash
#!/bin/bash
# APD Orchestrator Guard — prevents the orchestrator from writing code files directly
# Agents have agent_id; orchestrator does not.
# If no agent_id → this is the orchestrator → block code file writes.
#
# Interface: --file-path <path> --agent-id <id>

source "$(dirname "$0")/../lib/resolve-project.sh"
source "$(dirname "$0")/../lib/style.sh"
[ "$APD_ACTIVE" = false ] && exit 0

FILE_PATH=""
AGENT_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file-path) FILE_PATH="$2"; shift 2 ;;
    --agent-id)  AGENT_ID="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# If this is an agent (has agent_id), allow — agents have their own guard-scope
if [ -n "$AGENT_ID" ]; then
  exit 0
fi

# No agent_id = orchestrator session
if [ -z "$FILE_PATH" ]; then
  exit 0
fi

REL_PATH="${FILE_PATH#"$PROJECT_DIR"/}"

# Always allow: APD infrastructure, config, documentation
case "$REL_PATH" in
  .claude/*|CLAUDE.md|.gitignore|*.md|docs/*|.apd-*|.env*|*.json|*.yaml|*.yml|*.toml|*.xml|*.lock)
    exit 0
    ;;
esac

# Determine code extensions based on stack (from userConfig or .apd-config)
STACK="${CLAUDE_PLUGIN_OPTION_STACK:-}"
[ -z "$STACK" ] && STACK=$(grep '^STACK=' "$CLAUDE_DIR/.apd-config" 2>/dev/null | cut -d= -f2-)

case "${STACK:-}" in
  php)
    CODE_EXT="php" ;;
  nodejs|node)
    CODE_EXT="js|ts|tsx|jsx|mjs|cjs" ;;
  python)
    CODE_EXT="py" ;;
  dotnet)
    CODE_EXT="cs|fs" ;;
  go)
    CODE_EXT="go" ;;
  java)
    CODE_EXT="java|kt|scala" ;;
  *)
    # Fallback: all common code extensions
    CODE_EXT="php|js|ts|tsx|jsx|py|rb|go|rs|java|cs|cpp|c|h|swift|kt|scala|vue|svelte" ;;
esac

# Also always block: shell scripts, SQL, HTML templates with code
CODE_EXT="${CODE_EXT}|sh|sql"

if echo "$REL_PATH" | grep -qE "\.(${CODE_EXT})$"; then
  echo "BLOCKED: Orchestrator cannot write code files directly." >&2
  echo "  File: $REL_PATH" >&2
  echo "  Dispatch the appropriate Builder agent instead." >&2
  echo "" >&2
  echo "  Available agents:" >&2
  if [ -d "$CLAUDE_DIR/agents" ]; then
    for agent_file in "$CLAUDE_DIR/agents"/*.md; do
      [ -f "$agent_file" ] || continue
      AGENT_NAME=$(basename "$agent_file" .md)
      echo "    - $AGENT_NAME" >&2
    done
  fi
  log_block "orchestrator-code-write" "$REL_PATH"
  exit 2
fi

# Allow everything else (config files, data files, etc.)
exit 0
```

- [ ] **Step 3: Test**

```bash
bash bin/core/guard-orchestrator --file-path "$PWD/src/main.ts" --agent-id ""
# Expected: exit 2 (orchestrator + code file)

bash bin/core/guard-orchestrator --file-path "$PWD/src/main.ts" --agent-id "abc123"
# Expected: exit 0 (agent)

bash bin/core/guard-orchestrator --file-path "$PWD/CLAUDE.md" --agent-id ""
# Expected: exit 0 (config file)
```

- [ ] **Step 4: Commit**

```bash
git add bin/adapter/cc/guard-orchestrator bin/core/guard-orchestrator
git commit -m "refactor: split guard-orchestrator into core + CC adapter shim"
```

---

### Task 5: guard-bash-scope

**Files:**
- Create: `bin/adapter/cc/guard-bash-scope`
- Modify: `bin/core/guard-bash-scope`

- [ ] **Step 1: Create CC adapter shim**

Create `bin/adapter/cc/guard-bash-scope`:

```bash
#!/bin/bash
# CC adapter shim for guard-bash-scope
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../../core"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

exec "$CORE_DIR/guard-bash-scope" --command "$COMMAND" "$@"
```

```bash
chmod +x bin/adapter/cc/guard-bash-scope
```

- [ ] **Step 2: Refactor core guard-bash-scope**

Replace the stdin parsing block (lines 21-24) with args parsing. The rest of the file stays identical — only the input mechanism changes.

Replace lines 1-28 of `bin/core/guard-bash-scope` with:

```bash
#!/bin/bash
# APD Bash Scope Guard — blocks Bash commands that write outside the allowed scope
# Complements guard-scope which protects Write/Edit operations
#
# Detects:
#   1. Shell write operations: redirect (>), tee, sed -i, cp, mv, dd, install
#   2. Runtime write operations: node -e, python -c, ruby -e, php -r, perl -e
#      with write functions (writeFileSync, open().write, file_put_contents...)
#
# Interface: --command <cmd> [allowed_path_1] [allowed_path_2] ...

source "$(dirname "$0")/../lib/resolve-project.sh"
source "$(dirname "$0")/../lib/style.sh"
[ "$APD_ACTIVE" = false ] && exit 0

COMMAND=""
ALLOWED_PATHS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --command) COMMAND="$2"; shift 2 ;;
    *) ALLOWED_PATHS+=("$1"); shift ;;
  esac
done

if [ -z "$COMMAND" ]; then
  exit 0
fi
```

Everything from line 30 onward (`# --- 0. Protected paths ---`) stays exactly the same. Remove the `if ! command -v jq` block (lines 16-19 of original) since core no longer uses jq.

- [ ] **Step 3: Test**

```bash
bash bin/core/guard-bash-scope --command "echo test > /tmp/outside.txt" src/
# Expected: exit 2

bash bin/core/guard-bash-scope --command "ls -la" src/
# Expected: exit 0

bash bin/core/guard-bash-scope --command "mkdir -p .apd/pipeline/fake"
# Expected: exit 2 (protected pipeline path, no allowed paths needed)

echo '{"tool_input":{"command":"echo test > /tmp/outside.txt"}}' | bash bin/adapter/cc/guard-bash-scope src/
# Expected: exit 2
```

- [ ] **Step 4: Commit**

```bash
git add bin/adapter/cc/guard-bash-scope bin/core/guard-bash-scope
git commit -m "refactor: split guard-bash-scope into core + CC adapter shim"
```

---

### Task 6: guard-git

**Files:**
- Create: `bin/adapter/cc/guard-git`
- Modify: `bin/core/guard-git`

- [ ] **Step 1: Create CC adapter shim**

Create `bin/adapter/cc/guard-git`:

```bash
#!/bin/bash
# CC adapter shim for guard-git
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../../core"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed. Required for guard-git." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)

exec "$CORE_DIR/guard-git" --command "$COMMAND" --agent-id "$AGENT_ID" --agent-type "$AGENT_TYPE" "$@"
```

```bash
chmod +x bin/adapter/cc/guard-git
```

- [ ] **Step 2: Refactor core guard-git**

Replace lines 1-38 (everything before `# Block --no-verify`) with:

```bash
#!/bin/bash
# APD Guard — blocks unauthorized git operations
# Subagents must not commit, push, or perform destructive operations
#
# Interface: --command <cmd> --agent-id <id> --agent-type <type>

source "$(dirname "$0")/../lib/resolve-project.sh"
[ "$APD_ACTIVE" = false ] && exit 0

COMMAND=""
AGENT_ID=""
AGENT_TYPE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --command)    COMMAND="$2"; shift 2 ;;
    --agent-id)   AGENT_ID="$2"; shift 2 ;;
    --agent-type) AGENT_TYPE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Log function — logs blocked actions with agent context
log_block() {
  local reason="$1"
  local log_file="$MEMORY_DIR/guard-audit.log"
  if [ -d "$MEMORY_DIR" ]; then
    local agent_info="${AGENT_ID:-orchestrator}"
    [ -n "$AGENT_TYPE" ] && agent_info="${agent_info}(${AGENT_TYPE})"
    echo "$(date +%Y-%m-%d\ %H:%M:%S)|BLOCK|${agent_info}|${reason}|${RAW_COMMAND:-$COMMAND}" >> "$log_file" 2>/dev/null
  fi
}

RAW_COMMAND="$COMMAND"

if [ -z "$COMMAND" ]; then
  exit 0
fi
COMMAND=$(echo "$COMMAND" | tr -s ' ' | sed 's/^ //')
STRIPPED_CMD=$(echo "$COMMAND" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*//')
NORMALIZED_GIT=$(echo "$STRIPPED_CMD" | sed -E 's/git[[:space:]]+(-[A-Za-z][[:space:]]+[^ ]+[[:space:]]+)*/git /g')
```

Everything from `# Block --no-verify` (line 42 of original) through `exit 0` (line 145) stays exactly the same.

- [ ] **Step 3: Test**

```bash
bash bin/core/guard-git --command "git commit -m test" --agent-id "" --agent-type ""
# Expected: exit 2 (no APD_ORCHESTRATOR_COMMIT=1)

bash bin/core/guard-git --command "git add ." --agent-id "" --agent-type ""
# Expected: exit 2 (mass staging)

bash bin/core/guard-git --command "git push --force" --agent-id "" --agent-type ""
# Expected: exit 2

bash bin/core/guard-git --command "git commit --no-verify -m test" --agent-id "" --agent-type ""
# Expected: exit 2

echo '{"tool_input":{"command":"git reset --hard HEAD"}}' | bash bin/adapter/cc/guard-git
# Expected: exit 2
```

- [ ] **Step 4: Commit**

```bash
git add bin/adapter/cc/guard-git bin/core/guard-git
git commit -m "refactor: split guard-git into core + CC adapter shim"
```

---

### Task 7: guard-secrets

**Files:**
- Create: `bin/adapter/cc/guard-secrets`
- Modify: `bin/core/guard-secrets`

- [ ] **Step 1: Create CC adapter shim**

Create `bin/adapter/cc/guard-secrets`:

```bash
#!/bin/bash
# CC adapter shim for guard-secrets
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../../core"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed." >&2
  exit 2
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

exec "$CORE_DIR/guard-secrets" --file-path "$FILE_PATH" --command "$COMMAND" "$@"
```

```bash
chmod +x bin/adapter/cc/guard-secrets
```

- [ ] **Step 2: Refactor core guard-secrets**

Replace content of `bin/core/guard-secrets` with:

```bash
#!/bin/bash
# APD Secrets Guard — prevents access to sensitive files
# Customize BLOCKED_PATTERNS for your project
#
# Interface: --file-path <path> --command <cmd>

source "$(dirname "$0")/../lib/resolve-project.sh"
source "$(dirname "$0")/../lib/style.sh"
[ "$APD_ACTIVE" = false ] && exit 0

FILE_PATH=""
COMMAND=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file-path) FILE_PATH="$2"; shift 2 ;;
    --command)   COMMAND="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# ===== CUSTOMIZE FOR YOUR PROJECT =====
BLOCKED_PATTERNS=(
  # Environment files
  '.env.production'
  '.env.staging'
  '.env.prod'
  # Keys and certificates
  '.pem'
  '.key'
  '.pfx'
  'id_rsa'
  'id_ed25519'
  'id_ecdsa'
  # Credential files
  'credentials.json'
  'service-account'
  '.sa.json'
  # Docker registry
  '.docker/config.json'
  # .NET specific (remove if not .NET)
  'appsettings.Production.json'
  'appsettings.Staging.json'
  'user-secrets'
)
# =======================================

if [ -n "$FILE_PATH" ]; then
  REL_PATH="${FILE_PATH#"$PROJECT_DIR"/}"
  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if [[ "$REL_PATH" == *"$pattern"* ]]; then
      echo "BLOCKED: Access to sensitive file: $REL_PATH" >&2
      log_block "secret-access" "$REL_PATH"
      exit 2
    fi
  done
fi

if [ -n "$COMMAND" ]; then
  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if [[ "$COMMAND" == *"$pattern"* ]]; then
      echo "BLOCKED: Command accesses sensitive file: $pattern" >&2
      log_block "secret-access" "$pattern"
      exit 2
    fi
  done
fi

exit 0
```

- [ ] **Step 3: Test**

```bash
bash bin/core/guard-secrets --file-path "config/.env.production" --command ""
# Expected: exit 2

bash bin/core/guard-secrets --file-path "" --command "cat id_rsa"
# Expected: exit 2

bash bin/core/guard-secrets --file-path "src/main.ts" --command ""
# Expected: exit 0
```

- [ ] **Step 4: Commit**

```bash
git add bin/adapter/cc/guard-secrets bin/core/guard-secrets
git commit -m "refactor: split guard-secrets into core + CC adapter shim"
```

---

### Task 8: track-agent

**Files:**
- Create: `bin/adapter/cc/track-agent`
- Modify: `bin/core/track-agent`

- [ ] **Step 1: Create CC adapter shim**

Create `bin/adapter/cc/track-agent`:

```bash
#!/bin/bash
# CC adapter shim for track-agent
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../../core"

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)

# Debug log — capture full hook input for analysis
MEMORY_DIR_RESOLVE="$(cd "$(dirname "$0")" && pwd)/../../core"
source "$CORE_DIR/../lib/resolve-project.sh" 2>/dev/null
if [ -d "${MEMORY_DIR:-}" ]; then
  AGENT_DEBUG_LOG="$MEMORY_DIR/agent-dispatch-debug.log"
  echo "=== $(date +"%Y-%m-%d %H:%M:%S") | $EVENT | $AGENT_TYPE ===" >> "$AGENT_DEBUG_LOG"
  echo "$INPUT" | jq '.' >> "$AGENT_DEBUG_LOG" 2>/dev/null
  echo "" >> "$AGENT_DEBUG_LOG"
fi

exec "$CORE_DIR/track-agent" --event "$EVENT" --agent-type "$AGENT_TYPE" --agent-id "$AGENT_ID" "$@"
```

```bash
chmod +x bin/adapter/cc/track-agent
```

Note: The debug log (raw JSON dump) stays in the adapter because it captures the CC-specific full payload. Core only gets normalized args.

- [ ] **Step 2: Refactor core track-agent**

Replace content of `bin/core/track-agent` with:

```bash
#!/bin/bash
# APD Agent Tracker — records agent start/stop events to pipeline state
# Writes to .apd/pipeline/.agents so pipeline-advance can verify
# that a real agent ran before marking a step complete.
#
# Interface: --event <SubagentStart|SubagentStop> --agent-type <name> --agent-id <id>

source "$(dirname "$0")/../lib/resolve-project.sh"
[ "$APD_ACTIVE" = false ] && exit 0
source "$(dirname "$0")/../lib/style.sh"

EVENT=""
AGENT_TYPE=""
AGENT_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --event)      EVENT="$2"; shift 2 ;;
    --agent-type) AGENT_TYPE="$2"; shift 2 ;;
    --agent-id)   AGENT_ID="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$AGENT_TYPE" ] || [ -z "$EVENT" ]; then
  exit 0
fi

mkdir -p "$PIPELINE_DIR"
AGENTS_LOG="$PIPELINE_DIR/.agents"
NOW_HUMAN=$(date +"%Y-%m-%d %H:%M:%S")

# Agent display color
ac=$(_agent_color "$AGENT_TYPE")

case "$EVENT" in
  SubagentStart)
    echo "${NOW_HUMAN}|start|${AGENT_TYPE}|${AGENT_ID}" >> "$AGENTS_LOG"
    printf "  %s☭%s %s%s%s%s\n" "$ac" "$R" "$ac" "$B" "$AGENT_TYPE" "$R" >&2
    # Pipeline step reminder — warn if orchestrator skipped pipeline-advance
    if [ -f "$PIPELINE_DIR/spec.done" ] && [ ! -f "$PIPELINE_DIR/builder.done" ]; then
        echo "" >&2
        echo "  ${RED}${B}WARNING: pipeline-advance builder was NOT called before dispatching agent.${R}" >&2
        echo "  ${RED}Run: bash .claude/bin/apd pipeline builder${R}" >&2
        echo "  ${RED}Pipeline will BLOCK at reviewer step without builder.done${R}" >&2
        echo "" >&2
    elif [ -f "$PIPELINE_DIR/builder.done" ] && [ ! -f "$PIPELINE_DIR/reviewer.done" ]; then
        if echo "$AGENT_TYPE" | grep -qiE 'adversarial'; then
            echo "" >&2
            echo "  ${RED}${B}WARNING: adversarial-reviewer dispatched before reviewer step.${R}" >&2
            echo "  ${RED}Pipeline flow: builder → reviewer → fix → adversarial${R}" >&2
            echo "  ${RED}Verifier will BLOCK if adversarial ran before reviewer.done${R}" >&2
            echo "" >&2
        fi
        if echo "$AGENT_TYPE" | grep -qiE 'review'; then
            echo "" >&2
            echo "  ${D}Reminder: Run 'bash .claude/bin/apd pipeline reviewer' after review completes${R}" >&2
        fi
    fi
    ;;
  SubagentStop)
    echo "${NOW_HUMAN}|stop|${AGENT_TYPE}|${AGENT_ID}" >> "$AGENTS_LOG"
    printf "  %s☭%s %s%s%s %sdone%s\n" "$ac" "$R" "$ac" "$AGENT_TYPE" "$R" "$D" "$R" >&2
    ;;
esac

exit 0
```

- [ ] **Step 3: Test**

```bash
bash bin/core/track-agent --event "SubagentStart" --agent-type "backend-api" --agent-id "abc123"
# Expected: exit 0, writes to .apd/pipeline/.agents

bash bin/core/track-agent --event "SubagentStop" --agent-type "backend-api" --agent-id "abc123"
# Expected: exit 0, appends stop entry
```

- [ ] **Step 4: Commit**

```bash
git add bin/adapter/cc/track-agent bin/core/track-agent
git commit -m "refactor: split track-agent into core + CC adapter shim"
```

---

### Task 9: pipeline-post-commit

**Files:**
- Create: `bin/adapter/cc/pipeline-post-commit`
- Modify: `bin/core/pipeline-post-commit`

- [ ] **Step 1: Create CC adapter shim**

Create `bin/adapter/cc/pipeline-post-commit`:

```bash
#!/bin/bash
# CC adapter shim for pipeline-post-commit
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_DIR="$SCRIPT_DIR/../../core"

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

exec "$CORE_DIR/pipeline-post-commit" --command "$COMMAND" "$@"
```

```bash
chmod +x bin/adapter/cc/pipeline-post-commit
```

- [ ] **Step 2: Refactor core pipeline-post-commit**

Replace content of `bin/core/pipeline-post-commit` with:

```bash
#!/bin/bash
# APD Pipeline Post-Commit — resets pipeline AFTER a successful commit
#
# Why PostToolUse and not PreToolUse:
#   PreToolUse executes BEFORE the commit — if the commit fails (merge conflict,
#   disk full, pre-commit hook), the pipeline is already reset and the next commit
#   passes without the pipeline. PostToolUse executes only AFTER the tool runs
#   successfully — if the commit fails, the hook is not triggered.
#
# Interface: --command <cmd>

source "$(dirname "$0")/../lib/resolve-project.sh"
[ "$APD_ACTIVE" = false ] && exit 0

COMMAND=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --command) COMMAND="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Only react to successful APD commits
if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 " && echo "$COMMAND" | grep -qiE "git commit"; then
  # Check if pipeline exists (it may already be reset)
  if [ -d "$PIPELINE_DIR" ] && ls "$PIPELINE_DIR"/*.done &>/dev/null 2>&1; then
    bash "$SCRIPT_DIR/pipeline-advance" reset >/dev/null 2>&1
    echo "Pipeline reset after successful commit." >&2
  fi
fi

exit 0
```

- [ ] **Step 3: Test**

```bash
bash bin/core/pipeline-post-commit --command "APD_ORCHESTRATOR_COMMIT=1 git commit -m 'test'"
# Expected: exit 0 (attempts reset if .done files exist)

bash bin/core/pipeline-post-commit --command "git status"
# Expected: exit 0 (ignored, not a commit)
```

- [ ] **Step 4: Commit**

```bash
git add bin/adapter/cc/pipeline-post-commit bin/core/pipeline-post-commit
git commit -m "refactor: split pipeline-post-commit into core + CC adapter shim"
```

---

### Task 10: Update hooks.json

**Files:**
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Update all guard paths from core/ to adapter/cc/**

In `hooks/hooks.json`, change these paths:

| Line | From | To |
|------|------|-----|
| 23 | `bin/core/guard-git` | `bin/adapter/cc/guard-git` |
| 33 | `bin/core/guard-bash-scope` | `bin/adapter/cc/guard-bash-scope` |
| 53 | `bin/core/guard-orchestrator` | `bin/adapter/cc/guard-orchestrator` |
| 63 | `bin/core/guard-pipeline-state` | `bin/adapter/cc/guard-pipeline-state` |
| 74 | `bin/core/guard-lockfile` | `bin/adapter/cc/guard-lockfile` |
| 87 | `bin/core/pipeline-post-commit` | `bin/adapter/cc/pipeline-post-commit` |
| 98 | `bin/core/track-agent` | `bin/adapter/cc/track-agent` |
| 108 | `bin/core/track-agent` | `bin/adapter/cc/track-agent` |

Paths that do NOT change (no stdin parsing, stay in core):
- `bin/core/session-start` (SessionStart/PostCompact — no stdin)
- `bin/core/guard-send-message` (PreToolUse SendMessage — no stdin)
- `bin/core/guard-permission-denied` (PermissionDenied — CC-only)

- [ ] **Step 2: Verify JSON is valid**

```bash
jq . hooks/hooks.json > /dev/null
# Expected: no output (valid JSON)
```

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "refactor: hooks.json points to adapter/cc/ shims"
```

---

### Task 11: Update agent templates

**Files:**
- Modify: `templates/agent-template.md`
- Modify: `templates/reviewer-template.md`
- Modify: `templates/adversarial-reviewer-template.md`

- [ ] **Step 1: Update agent-template.md**

Change all `bin/core/guard-*` paths to `bin/adapter/cc/guard-*`:

```
bin/core/guard-secrets   → bin/adapter/cc/guard-secrets
bin/core/guard-scope     → bin/adapter/cc/guard-scope
bin/core/guard-git       → bin/adapter/cc/guard-git
bin/core/guard-bash-scope → bin/adapter/cc/guard-bash-scope
```

- [ ] **Step 2: Update reviewer-template.md**

Change:
```
bin/core/guard-secrets → bin/adapter/cc/guard-secrets
bin/core/guard-git     → bin/adapter/cc/guard-git
```

- [ ] **Step 3: Update adversarial-reviewer-template.md**

Same changes as reviewer-template.md.

- [ ] **Step 4: Commit**

```bash
git add templates/agent-template.md templates/reviewer-template.md templates/adversarial-reviewer-template.md
git commit -m "refactor: agent templates point to adapter/cc/ shims"
```

---

### Task 12: Update verify-apd functional tests

**Files:**
- Modify: `bin/core/verify-apd`

- [ ] **Step 1: Update functional test invocations**

The functional tests in verify-apd (lines ~438-539) use `echo '{"tool_input":...}' | bash "$SCRIPT_DIR/guard-*"`. These must change to use CLI args since core guards no longer read stdin.

Replace each test block. Examples:

```bash
# guard-git: blocks git commit without prefix
# BEFORE: echo '{"tool_input":{"command":"git commit -m test"}}' | bash "$SCRIPT_DIR/guard-git"
# AFTER:
RESULT=$(bash "$SCRIPT_DIR/guard-git" --command "git commit -m test" --agent-id "" --agent-type "" 2>&1)
EXIT_CODE=$?
```

```bash
# guard-scope: blocks outside scope
# BEFORE: echo "{\"tool_input\":{\"file_path\":\"$PROJECT_DIR/outside/file.ts\"}}" | bash "$SCRIPT_DIR/guard-scope" src/
# AFTER:
RESULT=$(bash "$SCRIPT_DIR/guard-scope" --file-path "$PROJECT_DIR/outside/file.ts" src/ 2>&1)
EXIT_CODE=$?
```

```bash
# guard-bash-scope: blocks write outside scope
# BEFORE: echo '{"tool_input":{"command":"echo test > /tmp/outside.txt"}}' | bash "$SCRIPT_DIR/guard-bash-scope" src/
# AFTER:
RESULT=$(bash "$SCRIPT_DIR/guard-bash-scope" --command "echo test > /tmp/outside.txt" src/ 2>&1)
EXIT_CODE=$?
```

```bash
# guard-lockfile: blocks lock file
# BEFORE: echo "{\"tool_input\":{\"file_path\":\"$PROJECT_DIR/package-lock.json\"}}" | bash "$SCRIPT_DIR/guard-lockfile"
# AFTER:
RESULT=$(bash "$SCRIPT_DIR/guard-lockfile" --file-path "$PROJECT_DIR/package-lock.json" 2>&1)
EXIT_CODE=$?
```

Update ALL test blocks that pipe JSON to guards. Keep pass/fail assertions identical.

- [ ] **Step 2: Update the file existence checks**

The script checks for guard files in `$SCRIPT_DIR`. Add a check that `bin/adapter/cc/` exists and contains expected files:

```bash
# After existing guard checks (~line 148)
ADAPTER_DIR="$APD_PLUGIN_ROOT/bin/adapter/cc"
for adapter_script in guard-git guard-scope guard-bash-scope guard-lockfile guard-orchestrator guard-pipeline-state guard-secrets track-agent pipeline-post-commit; do
  if [ -x "$ADAPTER_DIR/$adapter_script" ]; then
    pass "Adapter shim: $adapter_script"
  else
    fail "Adapter shim missing or not executable: $adapter_script"
  fi
done
```

- [ ] **Step 3: Update hook path checks**

The hook registration checks (~line 222) verify `guard-git` appears in hooks.json. These still work because the check uses `grep -q 'guard-git'` which matches `adapter/cc/guard-git` too. Verify this is the case and add specificity if needed:

```bash
# Change grep to be specific about adapter path
if jq -e '...' "$PLUGIN_SETTINGS" 2>/dev/null | grep -q 'adapter/cc/guard-git'; then
```

- [ ] **Step 4: Run verify-apd**

```bash
bash bin/core/verify-apd
# Expected: all checks pass
```

- [ ] **Step 5: Commit**

```bash
git add bin/core/verify-apd
git commit -m "refactor: verify-apd uses CLI args for guard tests"
```

---

### Task 13: Update apd-init stale path detection

**Files:**
- Modify: `bin/core/apd-init`

- [ ] **Step 1: Add adapter path awareness to gap analysis**

In the existing project update section of apd-init, add detection for agents that still reference `bin/core/guard-scope` instead of `bin/adapter/cc/guard-scope`:

```bash
# After existing stale path detection
for agent_file in "$CLAUDE_DIR/agents"/*.md; do
  [ -f "$agent_file" ] || continue
  if grep -q 'bin/core/guard-scope' "$agent_file" 2>/dev/null; then
    AGENT_NAME=$(basename "$agent_file" .md)
    echo "  ${YELLOW}${B}STALE PATH:${R} $AGENT_NAME references bin/core/guard-scope — update to bin/adapter/cc/guard-scope" >&2
    sed -i.bak 's|bin/core/guard-scope|bin/adapter/cc/guard-scope|g' "$agent_file" && rm -f "${agent_file}.bak"
    sed -i.bak 's|bin/core/guard-bash-scope|bin/adapter/cc/guard-bash-scope|g' "$agent_file" && rm -f "${agent_file}.bak"
    sed -i.bak 's|bin/core/guard-git|bin/adapter/cc/guard-git|g' "$agent_file" && rm -f "${agent_file}.bak"
    sed -i.bak 's|bin/core/guard-secrets|bin/adapter/cc/guard-secrets|g' "$agent_file" && rm -f "${agent_file}.bak"
    echo "  ${GREEN}Fixed${R}" >&2
  fi
done
```

- [ ] **Step 2: Commit**

```bash
git add bin/core/apd-init
git commit -m "refactor: apd-init detects and fixes stale core/ paths in agents"
```

---

### Task 14: Final integration test

- [ ] **Step 1: Run verify-apd end-to-end**

```bash
bash bin/core/verify-apd
```

Expected: all checks pass including new adapter shim checks.

- [ ] **Step 2: Test each adapter shim with CC-format JSON**

```bash
echo '{"tool_input":{"command":"git commit -m test"}}' | bash bin/adapter/cc/guard-git
echo '{"tool_input":{"command":"echo x > /tmp/y"}}' | bash bin/adapter/cc/guard-bash-scope src/
echo '{"tool_input":{"file_path":"/project/src/test.ts"}}' | bash bin/adapter/cc/guard-scope src/
echo '{"tool_input":{"file_path":"/project/src/main.ts"},"agent_id":""}' | bash bin/adapter/cc/guard-orchestrator
echo '{"tool_input":{"file_path":"/project/.apd/pipeline/spec.done"}}' | bash bin/adapter/cc/guard-pipeline-state
echo '{"tool_input":{"file_path":"/project/package-lock.json"}}' | bash bin/adapter/cc/guard-lockfile
echo '{"tool_input":{"file_path":"/project/.env.production"}}' | bash bin/adapter/cc/guard-secrets
echo '{"hook_event_name":"SubagentStart","agent_type":"test","agent_id":"x"}' | bash bin/adapter/cc/track-agent
echo '{"tool_input":{"command":"git status"}}' | bash bin/adapter/cc/pipeline-post-commit
```

- [ ] **Step 3: Test each core guard directly (no JSON, no jq needed)**

```bash
bash bin/core/guard-lockfile --file-path "package-lock.json"
bash bin/core/guard-scope --file-path "$PWD/src/test.ts" src/
bash bin/core/guard-git --command "git add ." --agent-id "" --agent-type ""
bash bin/core/guard-bash-scope --command "cp x y" src/
bash bin/core/guard-orchestrator --file-path "$PWD/src/main.ts" --agent-id ""
bash bin/core/guard-pipeline-state --file-path "$PWD/.apd/pipeline/spec.done"
bash bin/core/guard-secrets --file-path ".env.production" --command ""
bash bin/core/track-agent --event "SubagentStart" --agent-type "test" --agent-id "abc"
bash bin/core/pipeline-post-commit --command "git status"
```

- [ ] **Step 4: Commit integration test confirmation**

```bash
git add -A
git commit -m "refactor: runtime contract adapter layer complete — Phase 2 of ADR-001"
```
