#!/bin/bash
# APD Lockfile Guard — sprečava modifikaciju lock fajlova

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

BASENAME=$(basename "$FILE_PATH")

case "$BASENAME" in
  package-lock.json|pnpm-lock.yaml|yarn.lock|packages.lock.json|composer.lock|Gemfile.lock|poetry.lock|Cargo.lock|go.sum)
    echo "BLOKIRANO: Lock fajl '$BASENAME' ne sme biti menjan direktno." >&2
    echo "Koristi package manager za ažuriranje." >&2
    exit 2
    ;;
esac

exit 0
