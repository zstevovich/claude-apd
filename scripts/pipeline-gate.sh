#!/bin/bash
# APD Pipeline Gate — blocks commit if pipeline steps are not completed

source "$(dirname "$0")/lib/resolve-project.sh"
[ "$APD_ACTIVE" = false ] && exit 0
source "$(dirname "$0")/lib/style.sh"

mkdir -p "$PIPELINE_DIR"

MISSING=()

for step in spec builder reviewer verifier; do
    if [ ! -f "$PIPELINE_DIR/$step.done" ]; then
        MISSING+=("$step")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    apd_blocked "Pipeline incomplete" >&2
    echo "" >&2

    for step in spec builder reviewer verifier; do
        if [ -f "$PIPELINE_DIR/$step.done" ]; then
            printf "    ${MARK_DONE} %s\n" "$step" >&2
        else
            printf "    ${MARK_TODO} %s  ${D}← missing${R}\n" "$step" >&2
        fi
    done

    echo "" >&2
    echo "    Use: pipeline-advance.sh <step>" >&2
    exit 2
fi

echo "  ${MARK_DONE} Pipeline gate: all steps complete" >&2
exit 0
