#!/bin/bash
# APD Pipeline Post-Commit — resets pipeline AFTER a successful commit
# Registered as PostToolUse hook for Bash tool
#
# Why PostToolUse and not PreToolUse:
#   PreToolUse executes BEFORE the commit — if the commit fails (merge conflict,
#   disk full, pre-commit hook), the pipeline is already reset and the next commit
#   passes without the pipeline. PostToolUse executes only AFTER the tool runs
#   successfully — if the commit fails, the hook is not triggered.

source "$(dirname "$0")/lib/resolve-project.sh"

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Only react to successful APD commits
if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 " && echo "$COMMAND" | grep -qiE "git commit"; then
  # Check if pipeline exists (it may already be reset)
  if [ -d "$PIPELINE_DIR" ] && ls "$PIPELINE_DIR"/*.done &>/dev/null 2>&1; then
    bash "$SCRIPT_DIR/pipeline-advance.sh" reset >/dev/null 2>&1
    echo "Pipeline reset after successful commit." >&2
  fi
fi

exit 0
