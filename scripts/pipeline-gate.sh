#!/bin/bash
# APD Pipeline Gate — blocks commit if pipeline steps are not completed

source "$(dirname "$0")/lib/resolve-project.sh"

mkdir -p "$PIPELINE_DIR"

MISSING=()

for step in spec builder reviewer verifier; do
    if [ ! -f "$PIPELINE_DIR/$step.done" ]; then
        MISSING+=("$step")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "BLOCKED: Pipeline steps are not completed!" >&2
    echo "" >&2
    echo "  Pipeline: Spec -> Builder -> Reviewer -> Verifier -> Commit" >&2
    echo "" >&2

    for step in spec builder reviewer verifier; do
        if [ -f "$PIPELINE_DIR/$step.done" ]; then
            echo "  [DONE] $step" >&2
        else
            echo "  [----] $step <- MISSING" >&2
        fi
    done

    echo "" >&2
    echo "Use pipeline-advance.sh to advance:" >&2
    echo "  bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh spec \"Task name\"" >&2
    echo "  bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh builder" >&2
    echo "  bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh reviewer" >&2
    echo "  bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh verifier" >&2
    echo "" >&2
    echo "Or: pipeline-advance.sh skip \"Reason\" for urgent hotfixes." >&2
    exit 2
fi

echo "Pipeline gate: ALL 4 STEPS COMPLETED — commit allowed." >&2
exit 0
