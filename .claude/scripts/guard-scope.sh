#!/bin/bash
# APD Scope Guard — blokira Write/Edit operacije van dozvoljenog scope-a
# Korišćenje: bash guard-scope.sh <dozvoljena_putanja_1> <dozvoljena_putanja_2> ...

ALLOWED_PATHS=("$@")

if [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "GREŠKA: jq nije instaliran." >&2
  exit 2
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REL_PATH="${FILE_PATH#$PROJECT_DIR/}"

if [[ "$REL_PATH" == /* ]]; then
  echo "BLOKIRANO: Fajl $FILE_PATH je van projektnog direktorijuma." >&2
  echo "Dozvoljene putanje: ${ALLOWED_PATHS[*]}" >&2
  exit 2
fi

for allowed in "${ALLOWED_PATHS[@]}"; do
  allowed="${allowed%/}/"
  if [[ "$REL_PATH" == "$allowed"* ]]; then
    exit 0
  fi
done

echo "BLOKIRANO: Fajl $REL_PATH je van dozvoljenog scope-a." >&2
echo "Dozvoljene putanje: ${ALLOWED_PATHS[*]}" >&2
exit 2
