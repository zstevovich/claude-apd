#!/bin/bash
# APD Pipeline Gate — blokira commit ako pipeline koraci nisu završeni

source "$(dirname "$0")/lib/resolve-project.sh"

mkdir -p "$PIPELINE_DIR"

MISSING=()

for step in spec builder reviewer verifier; do
    if [ ! -f "$PIPELINE_DIR/$step.done" ]; then
        MISSING+=("$step")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "BLOKIRANO: Pipeline koraci nisu završeni!" >&2
    echo "" >&2
    echo "  Pipeline: Spec → Builder → Reviewer → Verifier → Commit" >&2
    echo "" >&2

    for step in spec builder reviewer verifier; do
        if [ -f "$PIPELINE_DIR/$step.done" ]; then
            echo "  [DONE] $step" >&2
        else
            echo "  [----] $step ← NEDOSTAJE" >&2
        fi
    done

    echo "" >&2
    echo "Koristi pipeline-advance.sh za napredovanje:" >&2
    echo "  bash .claude/scripts/pipeline-advance.sh spec \"Naziv taska\"" >&2
    echo "  bash .claude/scripts/pipeline-advance.sh builder" >&2
    echo "  bash .claude/scripts/pipeline-advance.sh reviewer" >&2
    echo "  bash .claude/scripts/pipeline-advance.sh verifier" >&2
    echo "" >&2
    echo "Ili: pipeline-advance.sh skip \"Razlog\" za hitne hotfix-ove." >&2
    exit 2
fi

echo "Pipeline gate: SVA 4 KORAKA ZAVRŠENA — commit dozvoljen." >&2
exit 0
