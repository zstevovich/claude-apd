#!/bin/bash
# APD Secrets Guard — sprečava pristup osetljivim fajlovima
# Prilagodi BLOCKED_PATTERNS za svoj projekat

if ! command -v jq &>/dev/null; then
  echo "GREŠKA: jq nije instaliran." >&2
  exit 2
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# ===== PRILAGODI ZA SVOJ PROJEKAT =====
BLOCKED_PATTERNS=(
  # Environment fajlovi
  '.env.production'
  '.env.staging'
  '.env.prod'
  # Ključevi i sertifikati
  '.pem'
  '.key'
  '.pfx'
  'id_rsa'
  'id_ed25519'
  'id_ecdsa'
  # Credential fajlovi
  'credentials.json'
  'service-account'
  '.sa.json'
  # Docker registry
  '.docker/config.json'
  # .NET specifično (ukloni ako nije .NET)
  'appsettings.Production.json'
  'appsettings.Staging.json'
  'user-secrets'
)
# =======================================

if [ -n "$FILE_PATH" ]; then
  REL_PATH="${FILE_PATH#$PROJECT_DIR/}"
  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if [[ "$REL_PATH" == *"$pattern"* ]]; then
      echo "BLOKIRANO: Pristup osetljivom fajlu: $REL_PATH" >&2
      exit 2
    fi
  done
fi

if [ -n "$COMMAND" ]; then
  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if [[ "$COMMAND" == *"$pattern"* ]]; then
      echo "BLOKIRANO: Komanda pristupa osetljivom fajlu: $pattern" >&2
      exit 2
    fi
  done
fi

exit 0
