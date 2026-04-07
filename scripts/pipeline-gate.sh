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
    echo "" >&2
    echo "  BLOCKED: Pipeline incomplete" >&2
    echo "" >&2

    for step in spec builder reviewer verifier; do
        if [ -f "$PIPELINE_DIR/$step.done" ]; then
            printf "    [OK] %s\n" "$step" >&2
        else
            printf "    [  ] %s  <-- missing\n" "$step" >&2
        fi
    done

    echo "" >&2
    echo "  Advance: pipeline-advance.sh <step>" >&2
    echo "  Init:    pipeline-advance.sh init \"reason\"" >&2
    echo "  Skip:    pipeline-advance.sh skip \"reason\"" >&2
    exit 2
fi

echo "Pipeline gate: all steps complete — commit allowed." >&2
exit 0
