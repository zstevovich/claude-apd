#!/bin/bash
# APD Agent Tracker — records agent start/stop events to pipeline state
# Called by SubagentStart and SubagentStop hooks.
# Writes to .claude/.pipeline/.agents so pipeline-advance.sh can verify
# that a real agent ran before marking a step complete.

source "$(dirname "$0")/lib/resolve-project.sh"
[ "$APD_ACTIVE" = false ] && exit 0

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)

if [ -z "$AGENT_TYPE" ] || [ -z "$EVENT" ]; then
  exit 0
fi

mkdir -p "$PIPELINE_DIR"
AGENTS_LOG="$PIPELINE_DIR/.agents"
NOW_HUMAN=$(date +"%Y-%m-%d %H:%M:%S")

case "$EVENT" in
  SubagentStart)
    echo "${NOW_HUMAN}|start|${AGENT_TYPE}|${AGENT_ID}" >> "$AGENTS_LOG"
    ;;
  SubagentStop)
    echo "${NOW_HUMAN}|stop|${AGENT_TYPE}|${AGENT_ID}" >> "$AGENTS_LOG"
    ;;
esac

exit 0
