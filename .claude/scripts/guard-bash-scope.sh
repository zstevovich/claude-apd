#!/bin/bash
# APD Bash Scope Guard — blokira Bash komande koje pišu van dozvoljenog scope-a
# Komplementira guard-scope.sh koji štiti Write/Edit operacije
#
# Detektuje:
#   1. Shell write operacije: redirect (>), tee, sed -i, cp, mv, dd, install
#   2. Runtime write operacije: node -e, python -c, ruby -e, php -r, perl -e
#      sa write funkcijama (writeFileSync, open().write, file_put_contents...)

ALLOWED_PATHS=("$@")

if [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "GREŠKA: jq nije instaliran." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# --- 1. Shell write operacije ---
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

# --- 2. Runtime write operacije ---
if [ "$HAS_WRITE_OP" = false ]; then

  # Node.js: node -e / node --eval sa write operacijama
  if echo "$COMMAND" | grep -qE '(^|[;&|] *)node\s+(-e|--eval|--print)\s'; then
    if echo "$COMMAND" | grep -qiE 'writeFile|writeFileSync|appendFile|appendFileSync|createWriteStream|mkdirSync|copyFile'; then
      HAS_WRITE_OP=true
      WRITE_TYPE="node"
    fi
  fi

  # Python: python -c / python3 -c sa write operacijama
  if echo "$COMMAND" | grep -qE '(^|[;&|] *)python[3]?\s+(-c)\s'; then
    if echo "$COMMAND" | grep -qiE "open\s*\(|\.write\s*\(|Path\s*\(|shutil\.|os\.rename|os\.replace|pathlib"; then
      HAS_WRITE_OP=true
      WRITE_TYPE="python"
    fi
  fi

  # Ruby: ruby -e sa write operacijama
  if echo "$COMMAND" | grep -qE '(^|[;&|] *)ruby\s+(-e)\s'; then
    if echo "$COMMAND" | grep -qiE 'File\.(write|open|rename)|FileUtils\.(cp|mv|mkdir)'; then
      HAS_WRITE_OP=true
      WRITE_TYPE="ruby"
    fi
  fi

  # PHP: php -r sa write operacijama
  if echo "$COMMAND" | grep -qE '(^|[;&|] *)php\s+(-r)\s'; then
    if echo "$COMMAND" | grep -qiE 'file_put_contents|fwrite|fopen|rename|copy|mkdir'; then
      HAS_WRITE_OP=true
      WRITE_TYPE="php"
    fi
  fi

  # Perl: perl -e sa write operacijama
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

# --- Proveri da li putanje u komandi spadaju u dozvoljeni scope ---
PATHS_IN_CMD=$(echo "$COMMAND" | grep -oE '([~/.]?[a-zA-Z0-9_./-]{2,})' 2>/dev/null || true)

for allowed in "${ALLOWED_PATHS[@]}"; do
  allowed="${allowed%/}/"
  if echo "$PATHS_IN_CMD" | grep -q "$allowed" 2>/dev/null; then
    exit 0
  fi
done

if [ "$WRITE_TYPE" = "shell" ]; then
  echo "BLOKIRANO: Bash komanda piše van dozvoljenog scope-a." >&2
else
  echo "BLOKIRANO: Runtime write ($WRITE_TYPE) detektovan van dozvoljenog scope-a." >&2
fi
echo "Dozvoljene putanje: ${ALLOWED_PATHS[*]}" >&2
exit 2
