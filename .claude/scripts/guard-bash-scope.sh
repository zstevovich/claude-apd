#!/bin/bash
# APD Bash Scope Guard — upozorava na Bash komande koje pišu van dozvoljenog scope-a
# Komplementira guard-scope.sh koji štiti Write/Edit operacije

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

DANGEROUS_PATTERNS=('>>' '>' 'tee ' 'sed -i' 'sed --in-place' 'perl -i' 'cp ' 'mv ' 'dd ' 'install ')

HAS_WRITE_OP=false
for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if [[ "$COMMAND" == *"$pattern"* ]]; then
    HAS_WRITE_OP=true
    break
  fi
done

if [ "$HAS_WRITE_OP" = false ]; then
  exit 0
fi

PATHS_IN_CMD=$(echo "$COMMAND" | grep -oE '([~/]?[a-zA-Z0-9_./-]+)' 2>/dev/null || true)

for allowed in "${ALLOWED_PATHS[@]}"; do
  allowed="${allowed%/}/"
  if echo "$PATHS_IN_CMD" | grep -q "$allowed" 2>/dev/null; then
    exit 0
  fi
done

echo "BLOKIRANO: Bash komanda piše van dozvoljenog scope-a." >&2
echo "Dozvoljene putanje: ${ALLOWED_PATHS[*]}" >&2
exit 2
