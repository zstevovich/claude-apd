#!/bin/bash
# APD Bash Scope Guard — blocks Bash commands that write outside the allowed scope
# Complements guard-scope.sh which protects Write/Edit operations
#
# Detects:
#   1. Shell write operations: redirect (>), tee, sed -i, cp, mv, dd, install
#   2. Runtime write operations: node -e, python -c, ruby -e, php -r, perl -e
#      with write functions (writeFileSync, open().write, file_put_contents...)

source "$(dirname "$0")/lib/resolve-project.sh"
[ "$APD_ACTIVE" = false ] && exit 0

ALLOWED_PATHS=("$@")

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# --- 0. Protected paths — ALWAYS enforced, even without ALLOWED_PATHS ---
# .pipeline/ state files must only be modified by pipeline-advance.sh (not direct Bash writes)
PROTECTED_PATHS=(".claude/.pipeline/" ".pipeline/")
SHELL_WRITE_CHECK=('>>' '>' 'tee ' 'sed -i' 'sed --in-place' 'cp ' 'mv ' 'dd ' 'install ')

for ppath in "${PROTECTED_PATHS[@]}"; do
  if [[ "$COMMAND" == *"$ppath"* ]]; then
    # Check if command contains a write operation targeting protected path
    for wp in "${SHELL_WRITE_CHECK[@]}"; do
      if [[ "$COMMAND" == *"$wp"* ]]; then
        echo "BLOCKED: Bash write to protected pipeline state directory." >&2
        echo "" >&2
        echo "  Do not write directly to .pipeline/ — use pipeline-advance.sh instead." >&2
        echo "  Allowed: bash \${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh <command>" >&2
        exit 2
      fi
    done
  fi
done

if [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
  exit 0
fi

# --- 1. Shell write operations ---
SHELL_WRITE_PATTERNS=('>>' '>' 'tee ' 'sed -i' 'sed --in-place' 'cp ' 'mv ' 'dd ' 'install ')

HAS_WRITE_OP=false
WRITE_TYPE=""

for pattern in "${SHELL_WRITE_PATTERNS[@]}"; do
  if [[ "$COMMAND" == *"$pattern"* ]]; then
    HAS_WRITE_OP=true
    WRITE_TYPE="shell"
    break
  fi
done

# --- 2. Runtime write operations ---
if [ "$HAS_WRITE_OP" = false ]; then

  # Node.js: node -e / node --eval with write operations
  if echo "$COMMAND" | grep -qE '(^|[;&|] *)node\s+(-e|--eval|--print)\s'; then
    if echo "$COMMAND" | grep -qiE 'writeFile|writeFileSync|appendFile|appendFileSync|createWriteStream|mkdirSync|copyFile'; then
      HAS_WRITE_OP=true
      WRITE_TYPE="node"
    fi
  fi

  # Python: python -c / python3 -c with write operations
  if echo "$COMMAND" | grep -qE '(^|[;&|] *)python[3]?\s+(-c)\s'; then
    if echo "$COMMAND" | grep -qiE "open\s*\(|\.write\s*\(|Path\s*\(|shutil\.|os\.rename|os\.replace|pathlib"; then
      HAS_WRITE_OP=true
      WRITE_TYPE="python"
    fi
  fi

  # Ruby: ruby -e with write operations
  if echo "$COMMAND" | grep -qE '(^|[;&|] *)ruby\s+(-e)\s'; then
    if echo "$COMMAND" | grep -qiE 'File\.(write|open|rename)|FileUtils\.(cp|mv|mkdir)'; then
      HAS_WRITE_OP=true
      WRITE_TYPE="ruby"
    fi
  fi

  # PHP: php -r with write operations
  if echo "$COMMAND" | grep -qE '(^|[;&|] *)php\s+(-r)\s'; then
    if echo "$COMMAND" | grep -qiE 'file_put_contents|fwrite|fopen|rename|copy|mkdir'; then
      HAS_WRITE_OP=true
      WRITE_TYPE="php"
    fi
  fi

  # Perl: perl -e with write operations
  if echo "$COMMAND" | grep -qE '(^|[;&|] *)perl\s+(-e)\s'; then
    if echo "$COMMAND" | grep -qiE 'open\s*\(|print\s+\$|File::Copy|rename'; then
      HAS_WRITE_OP=true
      WRITE_TYPE="perl"
    fi
  fi
fi

if [ "$HAS_WRITE_OP" = false ]; then
  exit 0
fi

# --- Check if paths in the command fall within the allowed scope ---
PATHS_IN_CMD=$(echo "$COMMAND" | grep -oE '([~/./]?[a-zA-Z0-9_./-]{2,})' 2>/dev/null || true)

for allowed in "${ALLOWED_PATHS[@]}"; do
  allowed="${allowed%/}/"
  if echo "$PATHS_IN_CMD" | grep -qF "$allowed" 2>/dev/null; then
    exit 0
  fi
done

if [ "$WRITE_TYPE" = "shell" ]; then
  echo "BLOCKED: Bash command writes outside the allowed scope." >&2
else
  echo "BLOCKED: Runtime write ($WRITE_TYPE) detected outside the allowed scope." >&2
fi
echo "Allowed paths: ${ALLOWED_PATHS[*]}" >&2
exit 2
