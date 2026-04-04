#!/bin/bash
# APD Pipeline Advance — napreduje pipeline korak sa timestampovima
#
# Korišćenje:
#   pipeline-advance.sh spec "Naziv taska"
#   pipeline-advance.sh builder|reviewer|verifier
#   pipeline-advance.sh reset|status|stats|rollback
#   pipeline-advance.sh skip "Razlog"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/.pipeline"

mkdir -p "$PIPELINE_DIR"

STEP="$1"
ARG="$2"
NOW=$(date +%s)
NOW_HUMAN=$(date +"%Y-%m-%d %H:%M:%S")

format_duration() {
    local seconds=$1
    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
    fi
}

case "$STEP" in
    spec)
        if [ -z "$ARG" ]; then
            echo "GREŠKA: Naziv taska je obavezan." >&2
            exit 1
        fi
        rm -f "$PIPELINE_DIR"/*.done
        echo "${NOW}|${NOW_HUMAN}|${ARG}" > "$PIPELINE_DIR/spec.done"
        echo "Pipeline započet: $ARG [$NOW_HUMAN]"
        echo "  [DONE] spec   $NOW_HUMAN"
        echo "  [----] builder"
        echo "  [----] reviewer"
        echo "  [----] verifier"
        ;;

    builder)
        if [ ! -f "$PIPELINE_DIR/spec.done" ]; then
            echo "GREŠKA: Spec mora biti završen pre builder-a!" >&2
            exit 1
        fi
        SPEC_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/spec.done")
        ELAPSED=$(format_duration $((NOW - SPEC_TS)))
        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/builder.done"
        echo "Pipeline: builder završen. [$NOW_HUMAN] (spec→builder: $ELAPSED)"
        echo "  [DONE] spec"
        echo "  [DONE] builder   $NOW_HUMAN"
        echo "  [----] reviewer ← SLEDEĆI"
        echo "  [----] verifier"
        ;;

    reviewer)
        if [ ! -f "$PIPELINE_DIR/builder.done" ]; then
            echo "GREŠKA: Builder mora biti završen pre reviewer-a!" >&2
            exit 1
        fi
        BUILDER_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/builder.done")
        ELAPSED=$(format_duration $((NOW - BUILDER_TS)))
        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/reviewer.done"
        echo "Pipeline: reviewer završen. [$NOW_HUMAN] (builder→reviewer: $ELAPSED)"
        echo "  [DONE] spec"
        echo "  [DONE] builder"
        echo "  [DONE] reviewer  $NOW_HUMAN"
        echo "  [----] verifier ← SLEDEĆI"
        ;;

    verifier)
        if [ ! -f "$PIPELINE_DIR/reviewer.done" ]; then
            echo "GREŠKA: Reviewer mora biti završen pre verifier-a!" >&2
            exit 1
        fi
        REVIEWER_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/reviewer.done")
        SPEC_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/spec.done")
        ELAPSED=$(format_duration $((NOW - REVIEWER_TS)))
        TOTAL=$(format_duration $((NOW - SPEC_TS)))
        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/verifier.done"
        echo "Pipeline: verifier završen. COMMIT DOZVOLJEN. [$NOW_HUMAN]"
        echo "  (reviewer→verifier: $ELAPSED | ukupno: $TOTAL)"
        echo "  [DONE] spec"
        echo "  [DONE] builder"
        echo "  [DONE] reviewer"
        echo "  [DONE] verifier  $NOW_HUMAN"
        echo ""
        echo "Možeš commitovati sa: APD_ORCHESTRATOR_COMMIT=1 git commit ..."
        ;;

    reset)
        # Auto-append u session-log pre brisanja flag-ova
        if [ -f "$PIPELINE_DIR/spec.done" ]; then
            TASK_NAME=$(cut -d'|' -f3 "$PIPELINE_DIR/spec.done" 2>/dev/null)
            SPEC_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/spec.done" 2>/dev/null)
            TOTAL=""
            if [ -f "$PIPELINE_DIR/verifier.done" ] && [ -n "$SPEC_TS" ]; then
                VERIFIER_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/verifier.done" 2>/dev/null)
                TOTAL=" ($(format_duration $((VERIFIER_TS - SPEC_TS))))"
            fi
            SESSION_LOG="$(cd "$SCRIPT_DIR/.." && pwd)/memory/session-log.md"
            if [ -f "$SESSION_LOG" ] && [ -n "$TASK_NAME" ]; then
                cat >> "$SESSION_LOG" << EOF

## [$(date +%Y-%m-%d)] $TASK_NAME
**Status:** Završen
**Šta je urađeno:** [popuni]
**Problemi:** [popuni ili "Bez problema"]
**Guardrail koji je pomogao:** [popuni ili "N/A"]
**Novo pravilo:** [popuni ili "Nema"]
**Pipeline trajanje:**$TOTAL
EOF
                echo "Session log ažuriran: $TASK_NAME" >&2
            fi
        fi
        rm -f "$PIPELINE_DIR"/*.done
        echo "Pipeline resetovan. Spreman za novi task."
        ;;

    rollback)
        # Pronađi poslednji završen korak i obriši ga
        ROLLED_BACK=false
        for step in verifier reviewer builder spec; do
            if [ -f "$PIPELINE_DIR/$step.done" ]; then
                rm -f "$PIPELINE_DIR/$step.done"
                echo "Rollback: $step uklonjen."
                ROLLED_BACK=true

                # Prikaži novi status
                echo ""
                for s in spec builder reviewer verifier; do
                    if [ -f "$PIPELINE_DIR/$s.done" ]; then
                        echo "  [DONE] $s"
                    else
                        echo "  [----] $s ← SLEDEĆI"
                        break
                    fi
                done
                break
            fi
        done

        if [ "$ROLLED_BACK" = false ]; then
            echo "Nema koraka za rollback — pipeline je prazan."
        fi
        ;;

    status)
        TASK="[nema aktivnog taska]"
        SPEC_TIME=""
        if [ -f "$PIPELINE_DIR/spec.done" ]; then
            TASK=$(cut -d'|' -f3 "$PIPELINE_DIR/spec.done")
            SPEC_TIME=$(cut -d'|' -f2 "$PIPELINE_DIR/spec.done")
            SPEC_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/spec.done")
        fi
        echo "Pipeline status: $TASK"
        if [ -n "$SPEC_TIME" ]; then
            TOTAL_ELAPSED=$(format_duration $(($(date +%s) - SPEC_TS)))
            echo "  Započet: $SPEC_TIME (pre $TOTAL_ELAPSED)"
        fi
        echo ""

        PREV_TS="$SPEC_TS"
        for step in spec builder reviewer verifier; do
            if [ -f "$PIPELINE_DIR/$step.done" ]; then
                STEP_TIME=$(cut -d'|' -f2 "$PIPELINE_DIR/$step.done")
                STEP_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/$step.done")
                if [ "$step" != "spec" ] && [ -n "$PREV_TS" ]; then
                    DELTA=$(format_duration $((STEP_TS - PREV_TS)))
                    echo "  [DONE] $step   $STEP_TIME  (+$DELTA)"
                else
                    echo "  [DONE] $step   $STEP_TIME"
                fi
                PREV_TS="$STEP_TS"
            else
                if [ -n "$PREV_TS" ]; then
                    WAITING=$(format_duration $(($(date +%s) - PREV_TS)))
                    echo "  [----] $step   (čeka $WAITING)"
                else
                    echo "  [----] $step"
                fi
                PREV_TS=""
            fi
        done
        ;;

    stats)
        SKIP_LOG="$(cd "$SCRIPT_DIR/.." && pwd)/memory/pipeline-skip-log.md"
        if [ ! -f "$SKIP_LOG" ]; then
            echo "Nema skip log-a."
            exit 0
        fi
        TOTAL_SKIPS=$(grep -c '^|[[:space:]]*[0-9]' "$SKIP_LOG" 2>/dev/null || echo 0)
        echo "Pipeline statistika:"
        echo "  Ukupno skip-ova: $TOTAL_SKIPS"
        if [ "$TOTAL_SKIPS" -gt 0 ]; then
            echo ""
            echo "Poslednjih 5:"
            grep '^|[[:space:]]*[0-9]' "$SKIP_LOG" | tail -5
        fi
        ;;

    skip)
        if [ -z "$ARG" ]; then
            echo "GREŠKA: Razlog za skip je obavezan." >&2
            exit 1
        fi
        echo "${NOW}|${NOW_HUMAN}|HOTFIX: ${ARG}" > "$PIPELINE_DIR/spec.done"
        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/builder.done"
        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/reviewer.done"
        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/verifier.done"

        # Append u skip log
        SKIP_LOG="$(cd "$SCRIPT_DIR/.." && pwd)/memory/pipeline-skip-log.md"
        if [ -f "$SKIP_LOG" ]; then
            echo "| ${NOW_HUMAN} | ${ARG} | — |" >> "$SKIP_LOG"
        fi

        echo "Pipeline PRESKOČEN: $ARG [$NOW_HUMAN]"
        echo "  Ovo se loguje. Koristi samo za hitne produkcijske popravke."
        ;;

    *)
        echo "Korišćenje:" >&2
        echo "  pipeline-advance.sh spec \"Naziv taska\"" >&2
        echo "  pipeline-advance.sh builder|reviewer|verifier" >&2
        echo "  pipeline-advance.sh reset|status|stats" >&2
        echo "  pipeline-advance.sh rollback" >&2
        echo "  pipeline-advance.sh skip \"Razlog\"" >&2
        exit 1
        ;;
esac
