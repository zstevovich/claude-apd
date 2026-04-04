#!/bin/bash
# APD Pipeline Post-Commit — resetuje pipeline POSLE uspešnog commita
# Registrovan kao PostToolUse hook za Bash tool
#
# Zašto PostToolUse a ne PreToolUse:
#   PreToolUse se izvršava PRE commita — ako commit padne (merge conflict,
#   disk full, pre-commit hook), pipeline je već resetovan i sledeći commit
#   prolazi bez pipeline-a. PostToolUse se izvršava tek POSLE uspešnog
#   izvršavanja tool-a — ako commit padne, hook se ne triggeruje.

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Samo reaguj na uspešne APD commit-e
if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 " && echo "$COMMAND" | grep -qiE "git commit"; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  PIPELINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/.pipeline"

  # Proveri da li pipeline postoji (možda je već resetovan)
  if [ -d "$PIPELINE_DIR" ] && ls "$PIPELINE_DIR"/*.done &>/dev/null 2>&1; then
    bash "$SCRIPT_DIR/pipeline-advance.sh" reset >/dev/null 2>&1
    echo "Pipeline resetovan posle uspešnog commita." >&2
  fi
fi

exit 0
