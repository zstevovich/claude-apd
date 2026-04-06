#!/bin/bash
# APD Pipeline Advance — napreduje pipeline korak sa timestampovima
#
# Korišćenje:
#   pipeline-advance.sh spec "Naziv taska"
#   pipeline-advance.sh builder|reviewer|verifier
#   pipeline-advance.sh reset|status|stats|metrics|rollback
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

        # Proveri da li prethodni session-log entry ima nepopunjene [popuni] placeholder-e
        SESSION_LOG="$(cd "$SCRIPT_DIR/.." && pwd)/memory/session-log.md"
        if [ -f "$SESSION_LOG" ]; then
            # Nađi poslednji entry — od poslednjeg ## [datum] do kraja fajla
            LAST_ENTRY_LINE=$(grep -n '^## \[' "$SESSION_LOG" | tail -1 | cut -d: -f1)
            if [ -n "$LAST_ENTRY_LINE" ]; then
                LAST_ENTRY=$(tail -n +"$LAST_ENTRY_LINE" "$SESSION_LOG")
            else
                LAST_ENTRY=""
            fi
            if echo "$LAST_ENTRY" | grep -q '\[popuni\]' 2>/dev/null; then
                LAST_TITLE=$(echo "$LAST_ENTRY" | head -1)
                echo "BLOKIRANO: Prethodni session-log entry nije popunjen!" >&2
                echo "" >&2
                echo "  Entry: $LAST_TITLE" >&2
                echo "  Sadrži [popuni] placeholder-e." >&2
                echo "" >&2
                echo "  Popuni session-log.md pre pokretanja novog taska:" >&2
                echo "  - Šta je urađeno" >&2
                echo "  - Problemi (ili \"Bez problema\")" >&2
                echo "  - Guardrail koji je pomogao (ili \"N/A\")" >&2
                echo "  - Novo pravilo (ili \"Nema\")" >&2
                exit 1
            fi
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
            # Append u metrics log
            METRICS_LOG="$(cd "$SCRIPT_DIR/.." && pwd)/memory/pipeline-metrics.log"
            SPEC_TS_V=${SPEC_TS:-0}
            BUILDER_TS_V=$(cut -d'|' -f1 "$PIPELINE_DIR/builder.done" 2>/dev/null || echo 0)
            REVIEWER_TS_V=$(cut -d'|' -f1 "$PIPELINE_DIR/reviewer.done" 2>/dev/null || echo 0)
            VERIFIER_TS_V=$(cut -d'|' -f1 "$PIPELINE_DIR/verifier.done" 2>/dev/null || echo 0)
            STATUS="completed"
            if [ ! -f "$PIPELINE_DIR/verifier.done" ]; then STATUS="partial"; fi
            echo "${NOW}|${TASK_NAME}|${SPEC_TS_V}|${BUILDER_TS_V}|${REVIEWER_TS_V}|${VERIFIER_TS_V}|${STATUS}" >> "$METRICS_LOG"

            SESSION_LOG="$(cd "$SCRIPT_DIR/.." && pwd)/memory/session-log.md"
            if [ -f "$SESSION_LOG" ] && [ -n "$TASK_NAME" ]; then
                MEMORY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/memory"
                PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

                # --- Prikupi kontekst ---

                # 1. Promenjeni fajlovi (git diff --stat)
                CHANGED_SUMMARY=""
                if command -v git &>/dev/null && git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
                    CHANGED_FILES=$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null)
                    [ -z "$CHANGED_FILES" ] && CHANGED_FILES=$(git -C "$PROJECT_DIR" diff --name-only HEAD 2>/dev/null)
                    if [ -n "$CHANGED_FILES" ]; then
                        FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
                        # Izvuci top-level direktorijume
                        TOP_DIRS=$(echo "$CHANGED_FILES" | sed 's|/.*||' | sort -u | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g')
                        CHANGED_SUMMARY="${FILE_COUNT} fajlova promenjeno (${TOP_DIRS})"
                    else
                        CHANGED_SUMMARY="Nema detektovanih promena u git-u"
                    fi
                else
                    CHANGED_SUMMARY="Git nije dostupan"
                fi

                # 2. Guard blokade tokom taska
                GUARD_SUMMARY="N/A"
                AUDIT_LOG="$MEMORY_DIR/guard-audit.log"
                if [ -f "$AUDIT_LOG" ] && [ -n "$SPEC_TS" ]; then
                    SPEC_DATE=$(date -r "$SPEC_TS" +%Y-%m-%d 2>/dev/null || date -d "@$SPEC_TS" +%Y-%m-%d 2>/dev/null || echo "")
                    if [ -n "$SPEC_DATE" ]; then
                        BLOCKS=$(grep "^${SPEC_DATE}" "$AUDIT_LOG" 2>/dev/null | wc -l | tr -d ' ')
                        if [ "$BLOCKS" -gt 0 ]; then
                            BLOCK_REASONS=$(grep "^${SPEC_DATE}" "$AUDIT_LOG" 2>/dev/null | cut -d'|' -f4 | sort | uniq -c | sort -rn | head -3 | awk '{print $2 " (" $1 "x)"}' | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g')
                            GUARD_SUMMARY="${BLOCKS} blokada: ${BLOCK_REASONS}"
                        fi
                    fi
                fi

                # 3. Rollback detekcija — proveri da li je verifier.done noviji od reviewer.done
                # (indikator da je rollback bio korišćen i ponovo prošao)
                PROBLEMS="Bez problema"
                if [ -f "$PIPELINE_DIR/verifier.done" ] && [ -f "$PIPELINE_DIR/reviewer.done" ]; then
                    V_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/verifier.done" 2>/dev/null || echo 0)
                    R_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/reviewer.done" 2>/dev/null || echo 0)
                    B_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/builder.done" 2>/dev/null || echo 0)
                    # Ako je builder→reviewer trajalo >60% ukupnog vremena, moguć problem
                    if [ "$V_TS" -gt 0 ] && [ "$SPEC_TS" -gt 0 ] && [ "$B_TS" -gt 0 ] && [ "$R_TS" -gt 0 ]; then
                        TOTAL_DUR=$((V_TS - SPEC_TS))
                        BUILD_DUR=$((R_TS - B_TS))
                        if [ "$TOTAL_DUR" -gt 0 ] && [ "$BUILD_DUR" -gt 0 ]; then
                            BUILD_PCT=$((BUILD_DUR * 100 / TOTAL_DUR))
                            if [ "$BUILD_PCT" -gt 60 ]; then
                                PROBLEMS="Builder→Reviewer trajao ${BUILD_PCT}% ukupnog vremena (moguće iteracije)"
                            fi
                        fi
                    fi
                fi

                # Ako ima guard blokada, to je problem
                if [ "$GUARD_SUMMARY" != "N/A" ]; then
                    if [ "$PROBLEMS" = "Bez problema" ]; then
                        PROBLEMS="Guard blokade detektovane (vidi Guardrail)"
                    fi
                fi

                # 4. Pipeline status
                PIPELINE_STATUS="Završen"
                if [ ! -f "$PIPELINE_DIR/verifier.done" ]; then
                    PIPELINE_STATUS="Delimičan (verifier nije završen)"
                fi

                # --- Generiši entry ---
                cat >> "$SESSION_LOG" << EOF

## [$(date +%Y-%m-%d)] $TASK_NAME
**Status:** $PIPELINE_STATUS
**Šta je urađeno:** $CHANGED_SUMMARY
**Problemi:** $PROBLEMS
**Guardrail koji je pomogao:** $GUARD_SUMMARY
**Novo pravilo:** [popuni ili "Nema"]
**Pipeline trajanje:**$TOTAL
EOF
                echo "Session log ažuriran (auto-summary): $TASK_NAME" >&2
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

    metrics)
        METRICS_LOG="$(cd "$SCRIPT_DIR/.." && pwd)/memory/pipeline-metrics.log"
        if [ ! -f "$METRICS_LOG" ] || [ ! -s "$METRICS_LOG" ]; then
            echo "Nema metrika — još nije završen nijedan task."
            exit 0
        fi

        TOTAL_TASKS=$(wc -l < "$METRICS_LOG" | tr -d ' ')
        COMPLETED=$(grep -c '|completed$' "$METRICS_LOG" 2>/dev/null || echo 0)
        PARTIAL=$(grep -c '|partial$' "$METRICS_LOG" 2>/dev/null || echo 0)
        SKIP_LOG="$(cd "$SCRIPT_DIR/.." && pwd)/memory/pipeline-skip-log.md"
        TOTAL_SKIPS=0
        if [ -f "$SKIP_LOG" ]; then
            TOTAL_SKIPS=$(grep -c '^|[[:space:]]*[0-9]' "$SKIP_LOG" 2>/dev/null) || TOTAL_SKIPS=0
        fi

        # Izračunaj proseke trajanja
        TOTAL_DURATION=0
        FASTEST=999999
        SLOWEST=0
        SPEC_TO_BUILDER=0
        BUILDER_TO_REVIEWER=0
        REVIEWER_TO_VERIFIER=0
        VALID_COUNT=0

        while IFS='|' read -r _ts task_name spec_ts builder_ts reviewer_ts verifier_ts status; do
            # Očisti trailing whitespace
            verifier_ts=$(echo "$verifier_ts" | tr -d '[:space:]')
            spec_ts=$(echo "$spec_ts" | tr -d '[:space:]')
            builder_ts=$(echo "$builder_ts" | tr -d '[:space:]')
            reviewer_ts=$(echo "$reviewer_ts" | tr -d '[:space:]')
            status=$(echo "$status" | tr -d '[:space:]')

            if [ "$verifier_ts" -gt 0 ] 2>/dev/null && [ "$spec_ts" -gt 0 ] 2>/dev/null; then
                DUR=$((verifier_ts - spec_ts))
                TOTAL_DURATION=$((TOTAL_DURATION + DUR))
                [ "$DUR" -lt "$FASTEST" ] && FASTEST=$DUR
                [ "$DUR" -gt "$SLOWEST" ] && SLOWEST=$DUR
                ((VALID_COUNT++))

                if [ "$builder_ts" -gt 0 ]; then
                    SPEC_TO_BUILDER=$((SPEC_TO_BUILDER + builder_ts - spec_ts))
                fi
                if [ "$reviewer_ts" -gt 0 ] && [ "$builder_ts" -gt 0 ]; then
                    BUILDER_TO_REVIEWER=$((BUILDER_TO_REVIEWER + reviewer_ts - builder_ts))
                fi
                if [ "$verifier_ts" -gt 0 ] && [ "$reviewer_ts" -gt 0 ]; then
                    REVIEWER_TO_VERIFIER=$((REVIEWER_TO_VERIFIER + verifier_ts - reviewer_ts))
                fi
            fi
        done < "$METRICS_LOG"

        if [ "$VALID_COUNT" -gt 0 ]; then
            AVG_DURATION=$(format_duration $((TOTAL_DURATION / VALID_COUNT)))
            FASTEST_FMT=$(format_duration $FASTEST)
            SLOWEST_FMT=$(format_duration $SLOWEST)
            AVG_S2B=$(format_duration $((SPEC_TO_BUILDER / VALID_COUNT)))
            AVG_B2R=$(format_duration $((BUILDER_TO_REVIEWER / VALID_COUNT)))
            AVG_R2V=$(format_duration $((REVIEWER_TO_VERIFIER / VALID_COUNT)))
        else
            AVG_DURATION="N/A"; FASTEST_FMT="N/A"; SLOWEST_FMT="N/A"
            AVG_S2B="N/A"; AVG_B2R="N/A"; AVG_R2V="N/A"
        fi

        SKIP_RATE="0%"
        if [ "$TOTAL_TASKS" -gt 0 ] && [ "$TOTAL_SKIPS" -gt 0 ]; then
            SKIP_RATE="$TOTAL_SKIPS/$((TOTAL_TASKS + TOTAL_SKIPS)) ($((TOTAL_SKIPS * 100 / (TOTAL_TASKS + TOTAL_SKIPS)))%)"
        fi

        echo "╔══════════════════════════════════════════╗"
        echo "║        APD Pipeline Metrike              ║"
        echo "╠══════════════════════════════════════════╣"
        printf "║  %-22s %-17s ║\n" "Ukupno taskova:" "$TOTAL_TASKS ($COMPLETED completed, $PARTIAL partial)"
        printf "║  %-22s %-17s ║\n" "Prosečno trajanje:" "$AVG_DURATION"
        printf "║  %-22s %-17s ║\n" "Najbrži:" "$FASTEST_FMT"
        printf "║  %-22s %-17s ║\n" "Najsporiji:" "$SLOWEST_FMT"
        printf "║  %-22s %-17s ║\n" "Skip rate:" "$SKIP_RATE"
        echo "╠──────────────────────────────────────────╣"
        echo "║  Prosek po koraku:                       ║"
        printf "║    %-20s %-17s ║\n" "spec→builder:" "$AVG_S2B"
        printf "║    %-20s %-17s ║\n" "builder→reviewer:" "$AVG_B2R"
        printf "║    %-20s %-17s ║\n" "reviewer→verifier:" "$AVG_R2V"
        echo "╠──────────────────────────────────────────╣"
        echo "║  Poslednjih 5:                           ║"
        tail -5 "$METRICS_LOG" | while IFS='|' read -r _ts task_name spec_ts _b _r verifier_ts status; do
            verifier_ts=$(echo "$verifier_ts" | tr -d '[:space:]')
            spec_ts=$(echo "$spec_ts" | tr -d '[:space:]')
            status=$(echo "$status" | tr -d '[:space:]')
            DUR="N/A"
            if [ "$verifier_ts" -gt 0 ] 2>/dev/null && [ "$spec_ts" -gt 0 ] 2>/dev/null; then
                DUR=$(format_duration $((verifier_ts - spec_ts)))
            fi
            ICON="✓"
            [ "$status" = "partial" ] && ICON="…"
            printf "║    %-24s %-8s %s    ║\n" "$task_name" "$DUR" "$ICON"
        done
        echo "╚══════════════════════════════════════════╝"
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
        echo "  pipeline-advance.sh reset|status|stats|metrics" >&2
        echo "  pipeline-advance.sh rollback" >&2
        echo "  pipeline-advance.sh skip \"Razlog\"" >&2
        exit 1
        ;;
esac
