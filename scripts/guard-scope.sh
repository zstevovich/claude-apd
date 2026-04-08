#!/bin/bash
# APD Scope Guard — blocks Write/Edit operations outside the allowed scope
# Usage: bash guard-scope.sh <allowed_path_1> <allowed_path_2> ...

source "$(dirname "$0")/lib/resolve-project.sh"
[ "$APD_ACTIVE" = false ] && exit 0

ALLOWED_PATHS=("$@")

if [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed." >&2
  exit 2
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi
REL_PATH="${FILE_PATH#"$PROJECT_DIR"/}"

if [[ "$REL_PATH" == /* ]]; then
  echo "BLOCKED: File $FILE_PATH is outside the project directory." >&2
  echo "Allowed paths: ${ALLOWED_PATHS[*]}" >&2
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
exit 2
