#!/bin/bash
# APD Permission Denied Logger — loguje kada auto mode odbije akciju
# Registrovan kao PermissionDenied hook u settings.json

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // "orchestrator"' 2>/dev/null)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null)

AGENT_INFO="$AGENT_ID"
[ -n "$AGENT_TYPE" ] && AGENT_INFO="${AGENT_ID}(${AGENT_TYPE})"

LOG_DIR="$(cd "$(dirname "$0")/.." && pwd)/memory"
LOG_FILE="$LOG_DIR/guard-audit.log"

if [ -d "$LOG_DIR" ]; then
    echo "$(date +%Y-%m-%d\ %H:%M:%S)|PERMISSION_DENIED|${AGENT_INFO}|${TOOL_NAME}" >> "$LOG_FILE" 2>/dev/null
fi

exit 0
