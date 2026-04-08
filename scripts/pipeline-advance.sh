#!/bin/bash
# APD Pipeline Advance — advances pipeline step with timestamps
#
# Usage:
#   pipeline-advance.sh spec "Task name"
#   pipeline-advance.sh builder|reviewer|verifier
#   pipeline-advance.sh reset|status|stats|metrics|rollback
#   pipeline-advance.sh skip "Reason"

source "$(dirname "$0")/lib/resolve-project.sh"

mkdir -p "$PIPELINE_DIR"

STEP="$1"
ARG="$2"
NOW=$(date +%s)
NOW_HUMAN=$(date +"%Y-%m-%d %H:%M:%S")

# --- Visual helpers ---
show_pipeline() {
    # Usage: show_pipeline [active_step]
    # Renders a visual pipeline progress bar
    local active="$1"
    local steps=("spec" "builder" "reviewer" "verifier")
    local line=""
    local detail=""

    for i in "${!steps[@]}"; do
        local s="${steps[$i]}"
        local icon="--"
        local label="$s"

        if [ -f "$PIPELINE_DIR/$s.done" ]; then
            icon="done"
        fi

        if [ "$s" = "$active" ]; then
            icon="next"
        fi

        if [ "$i" -gt 0 ]; then
            line="${line}---"
        fi

        if [ "$icon" = "done" ] || [ "$icon" = "next" ]; then
            line="${line}[${label}]"
        else
            line="${line} ${label} "
        fi
    done

    echo ""
    echo "  $line --> commit"
    echo ""

    # Detail lines
    for s in "${steps[@]}"; do
        if [ -f "$PIPELINE_DIR/$s.done" ]; then
            local ts=$(cut -d'|' -f2 "$PIPELINE_DIR/$s.done")
            printf "    %-12s %s\n" "$s" "$ts"
        elif [ "$s" = "$active" ]; then
            printf "    %-12s %s\n" "$s" "<-- current"
        else
            printf "    %-12s %s\n" "$s" "..."
        fi
    done
}

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
            echo "ERROR: Task name is required." >&2
            exit 1
        fi

        # Check if the previous session-log entry has unfilled [fill in] placeholders
        SESSION_LOG="$MEMORY_DIR/session-log.md"
        if [ -f "$SESSION_LOG" ]; then
            # Find the last entry — from the last ## [date] to end of file
            LAST_ENTRY_LINE=$(grep -n '^## \[' "$SESSION_LOG" | tail -1 | cut -d: -f1)
            if [ -n "$LAST_ENTRY_LINE" ]; then
                LAST_ENTRY=$(tail -n +"$LAST_ENTRY_LINE" "$SESSION_LOG")
            else
                LAST_ENTRY=""
            fi
            if echo "$LAST_ENTRY" | grep -q '\[fill in' 2>/dev/null; then
                LAST_TITLE=$(echo "$LAST_ENTRY" | head -1)
                echo "BLOCKED: Previous session-log entry is not filled in!" >&2
                echo "" >&2
                echo "  Entry: $LAST_TITLE" >&2
                echo "  Contains [fill in] placeholders." >&2
                echo "" >&2
                echo "  Fill in session-log.md before starting a new task:" >&2
                echo "  - What was done" >&2
                echo "  - Problems (or \"No problems\")" >&2
                echo "  - Guardrail that helped (or \"N/A\")" >&2
                echo "  - New rule (or \"None\")" >&2
                exit 1
            fi
        fi

        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents"
        echo "${NOW}|${NOW_HUMAN}|${ARG}" > "$PIPELINE_DIR/spec.done"
        echo "Pipeline started: $ARG"
        show_pipeline "builder"
        ;;

    builder)
        if [ ! -f "$PIPELINE_DIR/spec.done" ]; then
            echo "ERROR: Spec must be completed before builder!" >&2
            exit 1
        fi

        # Verify that a PROJECT-DEFINED builder agent ran
        # Superpowers agents that conflict with APD pipeline are rejected.
        # Other plugin agents (figma, context7, etc.) are allowed alongside project agents.
        AGENTS_LOG="$PIPELINE_DIR/.agents"
        SPEC_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/spec.done")
        BUILDER_RAN=""
        BLOCKED_AGENTS=""
        # Superpowers skills that conflict with APD roles
        REJECTED_PREFIXES="superpowers:"
        if [ -f "$AGENTS_LOG" ]; then
            while IFS='|' read -r _ts _evt agent_type _id; do
                [ "$_evt" = "stop" ] || continue
                # Reject specific conflicting agents
                if echo "$agent_type" | grep -qE "^(${REJECTED_PREFIXES})"; then
                    BLOCKED_AGENTS="${BLOCKED_AGENTS}${agent_type}, "
                    continue
                fi
                # Accept project-defined agents
                if [ -f "$CLAUDE_DIR/agents/${agent_type}.md" ]; then
                    BUILDER_RAN="$agent_type"
                fi
            done < "$AGENTS_LOG"
        fi
        if [ -z "${BUILDER_RAN:-}" ]; then
            echo "BLOCKED: No project Builder agent was dispatched!" >&2
            echo "" >&2
            if [ -n "$BLOCKED_AGENTS" ]; then
                echo "  Rejected conflicting agents: ${BLOCKED_AGENTS%, }" >&2
                echo "  These conflict with APD pipeline roles." >&2
                echo "  Dispatch agents defined in .claude/agents/ instead:" >&2
            else
                echo "  The orchestrator must dispatch a Builder agent to implement code." >&2
            fi
            echo "" >&2
            echo "  Project agents:" >&2
            if [ -d "$CLAUDE_DIR/agents" ]; then
                for f in "$CLAUDE_DIR/agents"/*.md; do
                    [ -f "$f" ] || continue
                    echo "    - $(basename "$f" .md)" >&2
                done
            fi
            exit 1
        fi

        ELAPSED=$(format_duration $((NOW - SPEC_TS)))
        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/builder.done"
        echo "Builder completed (+$ELAPSED)"
        show_pipeline "reviewer"
        ;;

    reviewer)
        if [ ! -f "$PIPELINE_DIR/builder.done" ]; then
            echo "ERROR: Builder must be completed before reviewer!" >&2
            exit 1
        fi

        # Verify that a PROJECT-DEFINED reviewer agent ran
        AGENTS_LOG="$PIPELINE_DIR/.agents"
        REVIEWER_RAN=""
        BLOCKED_AGENTS=""
        REJECTED_PREFIXES="superpowers:"
        if [ -f "$AGENTS_LOG" ]; then
            while IFS='|' read -r _ts _evt agent_type _id; do
                [ "$_evt" = "stop" ] || continue
                # Reject specific conflicting agents
                if echo "$agent_type" | grep -qE "^(${REJECTED_PREFIXES})"; then
                    BLOCKED_AGENTS="${BLOCKED_AGENTS}${agent_type}, "
                    continue
                fi
                # Accept reviewer if defined in project
                if [ -f "$CLAUDE_DIR/agents/${agent_type}.md" ] && echo "$agent_type" | grep -qiE 'review'; then
                    REVIEWER_RAN="$agent_type"
                fi
            done < "$AGENTS_LOG"
        fi
        if [ -z "${REVIEWER_RAN:-}" ]; then
            echo "BLOCKED: No project Reviewer agent was dispatched!" >&2
            echo "" >&2
            if [ -n "$BLOCKED_AGENTS" ]; then
                echo "  Rejected conflicting agents: ${BLOCKED_AGENTS%, }" >&2
                echo "  Use the project's code-reviewer agent (opus/max, read-only)." >&2
            else
                echo "  Code review is MANDATORY. Dispatch the code-reviewer agent." >&2
            fi
            echo "  The reviewer finds bugs, risks, and security issues." >&2
            exit 1
        fi

        BUILDER_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/builder.done")
        ELAPSED=$(format_duration $((NOW - BUILDER_TS)))
        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/reviewer.done"
        echo "Reviewer completed (+$ELAPSED)"
        show_pipeline "verifier"
        ;;

    verifier)
        if [ ! -f "$PIPELINE_DIR/reviewer.done" ]; then
            echo "ERROR: Reviewer must be completed before verifier!" >&2
            exit 1
        fi
        REVIEWER_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/reviewer.done")
        SPEC_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/spec.done")
        ELAPSED=$(format_duration $((NOW - REVIEWER_TS)))
        TOTAL=$(format_duration $((NOW - SPEC_TS)))
        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/verifier.done"
        # Cache timestamp — verify-all.sh skips rebuild if fresh (<120s)
        echo "$NOW" > "$PIPELINE_DIR/verified.timestamp"
        echo ""
        echo "  ========================================="
        echo "    COMMIT ALLOWED  (total: $TOTAL)"
        echo "  ========================================="
        show_pipeline ""
        echo "  Ready: APD_ORCHESTRATOR_COMMIT=1 git commit ..."
        ;;

    reset)
        # Auto-append to session-log before clearing flags
        if [ -f "$PIPELINE_DIR/spec.done" ]; then
            TASK_NAME=$(cut -d'|' -f3 "$PIPELINE_DIR/spec.done" 2>/dev/null)
            SPEC_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/spec.done" 2>/dev/null)
            TOTAL=""
            if [ -f "$PIPELINE_DIR/verifier.done" ] && [ -n "$SPEC_TS" ]; then
                VERIFIER_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/verifier.done" 2>/dev/null)
                TOTAL=" ($(format_duration $((VERIFIER_TS - SPEC_TS))))"
            fi
            # Append to metrics log
            METRICS_LOG="$MEMORY_DIR/pipeline-metrics.log"
            SPEC_TS_V=${SPEC_TS:-0}
            BUILDER_TS_V=$(cut -d'|' -f1 "$PIPELINE_DIR/builder.done" 2>/dev/null || echo 0)
            REVIEWER_TS_V=$(cut -d'|' -f1 "$PIPELINE_DIR/reviewer.done" 2>/dev/null || echo 0)
            VERIFIER_TS_V=$(cut -d'|' -f1 "$PIPELINE_DIR/verifier.done" 2>/dev/null || echo 0)
            STATUS="completed"
            if [ ! -f "$PIPELINE_DIR/verifier.done" ]; then STATUS="partial"; fi
            echo "${NOW}|${TASK_NAME}|${SPEC_TS_V}|${BUILDER_TS_V}|${REVIEWER_TS_V}|${VERIFIER_TS_V}|${STATUS}" >> "$METRICS_LOG"

            SESSION_LOG="$MEMORY_DIR/session-log.md"
            if [ -f "$SESSION_LOG" ] && [ -n "$TASK_NAME" ]; then

                # --- Collect context ---

                # 1. Changed files — check last commit first, fall back to working tree
                CHANGED_SUMMARY=""
                if command -v git &>/dev/null && git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
                    # Try last commit (most common — reset happens after commit)
                    CHANGED_FILES=$(git -C "$PROJECT_DIR" diff --name-only HEAD~1 HEAD 2>/dev/null)
                    # Fall back to staged/unstaged changes
                    [ -z "$CHANGED_FILES" ] && CHANGED_FILES=$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null)
                    [ -z "$CHANGED_FILES" ] && CHANGED_FILES=$(git -C "$PROJECT_DIR" diff --name-only HEAD 2>/dev/null)
                    if [ -n "$CHANGED_FILES" ]; then
                        FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
                        # Extract top-level directories
                        TOP_DIRS=$(echo "$CHANGED_FILES" | sed 's|/.*||' | sort -u | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g')
                        CHANGED_SUMMARY="${FILE_COUNT} files changed (${TOP_DIRS})"
                    else
                        CHANGED_SUMMARY="No changes detected in git"
                    fi
                else
                    CHANGED_SUMMARY="Git not available"
                fi

                # 2. Guard blocks during this task (filter by spec timestamp, not date)
                GUARD_SUMMARY="N/A"
                AUDIT_LOG="$MEMORY_DIR/guard-audit.log"
                if [ -f "$AUDIT_LOG" ] && [ -n "$SPEC_TS" ]; then
                    SPEC_TIME=$(date -r "$SPEC_TS" +"%Y-%m-%d %H:%M" 2>/dev/null || date -d "@$SPEC_TS" +"%Y-%m-%d %H:%M" 2>/dev/null || echo "")
                    if [ -n "$SPEC_TIME" ]; then
                        # Only count blocks after this task's spec was created
                        BLOCKS=0
                        BLOCK_REASONS=""
                        while IFS='|' read -r log_ts log_type log_agent log_reason log_cmd; do
                            LOG_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$log_ts" +%s 2>/dev/null || date -d "$log_ts" +%s 2>/dev/null || echo 0)
                            if [ "$LOG_EPOCH" -ge "$SPEC_TS" ] 2>/dev/null; then
                                BLOCKS=$((BLOCKS + 1))
                                BLOCK_REASONS="${BLOCK_REASONS}${log_reason}\n"
                            fi
                        done < "$AUDIT_LOG"
                        if [ "$BLOCKS" -gt 0 ]; then
                            REASON_SUMMARY=$(printf '%b' "$BLOCK_REASONS" | sort | uniq -c | sort -rn | head -3 | awk '{print $2 " (" $1 "x)"}' | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g')
                            GUARD_SUMMARY="${BLOCKS} blocks: ${REASON_SUMMARY}"
                        fi
                    fi
                fi

                # 3. Rollback detection — check if verifier.done is newer than reviewer.done
                # (indicates rollback was used and passed again)
                PROBLEMS="No problems"
                if [ -f "$PIPELINE_DIR/verifier.done" ] && [ -f "$PIPELINE_DIR/reviewer.done" ]; then
                    V_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/verifier.done" 2>/dev/null || echo 0)
                    R_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/reviewer.done" 2>/dev/null || echo 0)
                    B_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/builder.done" 2>/dev/null || echo 0)
                    # If builder->reviewer took >60% of total time, possible problem
                    if [ "$V_TS" -gt 0 ] && [ "$SPEC_TS" -gt 0 ] && [ "$B_TS" -gt 0 ] && [ "$R_TS" -gt 0 ]; then
                        TOTAL_DUR=$((V_TS - SPEC_TS))
                        BUILD_DUR=$((R_TS - B_TS))
                        if [ "$TOTAL_DUR" -gt 0 ] && [ "$BUILD_DUR" -gt 0 ]; then
                            BUILD_PCT=$((BUILD_DUR * 100 / TOTAL_DUR))
                            if [ "$BUILD_PCT" -gt 60 ]; then
                                PROBLEMS="Builder->Reviewer took ${BUILD_PCT}% of total time (possible iterations)"
                            fi
                        fi
                    fi
                fi

                # If there are guard blocks, that's a problem
                if [ "$GUARD_SUMMARY" != "N/A" ]; then
                    if [ "$PROBLEMS" = "No problems" ]; then
                        PROBLEMS="Guard blocks detected (see Guardrail)"
                    fi
                fi

                # 4. Pipeline status
                PIPELINE_STATUS="Completed"
                if [ ! -f "$PIPELINE_DIR/verifier.done" ]; then
                    PIPELINE_STATUS="Partial (verifier not completed)"
                fi

                # 5. New rule — auto-fill "None" for skip/init tasks, leave [fill in] for real tasks
                NEW_RULE='[fill in or "None"]'
                if echo "$TASK_NAME" | grep -qE '^(HOTFIX|INIT):'; then
                    NEW_RULE="None"
                fi

                # --- Generate entry ---
                cat >> "$SESSION_LOG" << EOF

## [$(date +%Y-%m-%d)] $TASK_NAME
**Status:** $PIPELINE_STATUS
**What was done:** $CHANGED_SUMMARY
**Problems:** $PROBLEMS
**Guardrail that helped:** $GUARD_SUMMARY
**New rule:** $NEW_RULE
**Pipeline duration:**$TOTAL
EOF
                echo "Session log updated (auto-summary): $TASK_NAME" >&2
            fi
        fi
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents"
        echo "Pipeline reset. Ready for new task."
        ;;

    rollback)
        # Find the last completed step and remove it
        ROLLED_BACK=false
        for step in verifier reviewer builder spec; do
            if [ -f "$PIPELINE_DIR/$step.done" ]; then
                rm -f "$PIPELINE_DIR/$step.done"
                # If verifier rolled back, also remove cache timestamp
                [ "$step" = "verifier" ] && rm -f "$PIPELINE_DIR/verified.timestamp"
                echo "Rollback: $step removed."
                ROLLED_BACK=true
                show_pipeline "$step"
                break
            fi
        done

        if [ "$ROLLED_BACK" = false ]; then
            echo "No steps to roll back — pipeline is empty."
        fi
        ;;

    status)
        TASK="[no active task]"
        SPEC_TIME=""
        NEXT_STEP=""
        if [ -f "$PIPELINE_DIR/spec.done" ]; then
            TASK=$(cut -d'|' -f3 "$PIPELINE_DIR/spec.done")
            SPEC_TIME=$(cut -d'|' -f2 "$PIPELINE_DIR/spec.done")
            SPEC_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/spec.done")
        fi

        # Find next step
        for s in spec builder reviewer verifier; do
            if [ ! -f "$PIPELINE_DIR/$s.done" ]; then
                NEXT_STEP="$s"
                break
            fi
        done

        echo "Task: $TASK"
        if [ -n "$SPEC_TIME" ]; then
            TOTAL_ELAPSED=$(format_duration $(($(date +%s) - SPEC_TS)))
            echo "Started: $SPEC_TIME ($TOTAL_ELAPSED ago)"
        fi

        show_pipeline "$NEXT_STEP"

        # Detailed timing
        PREV_TS="${SPEC_TS:-}"
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
                    echo "  [----] $step   (waiting $WAITING)"
                else
                    echo "  [----] $step"
                fi
                PREV_TS=""
            fi
        done
        ;;

    stats)
        SKIP_LOG="$MEMORY_DIR/pipeline-skip-log.md"
        if [ ! -f "$SKIP_LOG" ]; then
            echo "No skip log found."
            exit 0
        fi
        TOTAL_SKIPS=$(grep -c '^|[[:space:]]*[0-9]' "$SKIP_LOG" 2>/dev/null || echo 0)
        echo "Pipeline statistics:"
        echo "  Total skips: $TOTAL_SKIPS"
        if [ "$TOTAL_SKIPS" -gt 0 ]; then
            echo ""
            echo "Last 5:"
            grep '^|[[:space:]]*[0-9]' "$SKIP_LOG" | tail -5
        fi
        ;;

    metrics)
        METRICS_LOG="$MEMORY_DIR/pipeline-metrics.log"
        if [ ! -f "$METRICS_LOG" ] || [ ! -s "$METRICS_LOG" ]; then
            echo "No metrics — no tasks completed yet."
            exit 0
        fi

        TOTAL_TASKS=$(wc -l < "$METRICS_LOG" | tr -d ' ')
        COMPLETED=$(grep -c '|completed$' "$METRICS_LOG" 2>/dev/null || echo 0)
        PARTIAL=$(grep -c '|partial$' "$METRICS_LOG" 2>/dev/null || echo 0)
        SKIP_LOG="$MEMORY_DIR/pipeline-skip-log.md"
        TOTAL_SKIPS=0
        if [ -f "$SKIP_LOG" ]; then
            TOTAL_SKIPS=$(grep -c '^|[[:space:]]*[0-9]' "$SKIP_LOG" 2>/dev/null) || TOTAL_SKIPS=0
        fi

        # Calculate average durations
        TOTAL_DURATION=0
        FASTEST=999999
        SLOWEST=0
        SPEC_TO_BUILDER=0
        BUILDER_TO_REVIEWER=0
        REVIEWER_TO_VERIFIER=0
        VALID_COUNT=0

        while IFS='|' read -r _ts task_name spec_ts builder_ts reviewer_ts verifier_ts status; do
            # Clean trailing whitespace
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
                VALID_COUNT=$((VALID_COUNT + 1))

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
        echo "║        APD Pipeline Metrics              ║"
        echo "╠══════════════════════════════════════════╣"
        printf "║  %-22s %-17s ║\n" "Total tasks:" "$TOTAL_TASKS ($COMPLETED completed, $PARTIAL partial)"
        printf "║  %-22s %-17s ║\n" "Average duration:" "$AVG_DURATION"
        printf "║  %-22s %-17s ║\n" "Fastest:" "$FASTEST_FMT"
        printf "║  %-22s %-17s ║\n" "Slowest:" "$SLOWEST_FMT"
        printf "║  %-22s %-17s ║\n" "Skip rate:" "$SKIP_RATE"
        echo "╠──────────────────────────────────────────╣"
        echo "║  Average per step:                       ║"
        printf "║    %-20s %-17s ║\n" "spec->builder:" "$AVG_S2B"
        printf "║    %-20s %-17s ║\n" "builder->reviewer:" "$AVG_B2R"
        printf "║    %-20s %-17s ║\n" "reviewer->verifier:" "$AVG_R2V"
        echo "╠──────────────────────────────────────────╣"
        echo "║  Last 5:                                 ║"
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

    init)
        if [ -z "$ARG" ]; then
            echo "ERROR: Description for init is required." >&2
            exit 1
        fi

        # Init only allowed if no previous commits with APD (first setup)
        APD_COMMIT_COUNT=$(git -C "$PROJECT_DIR" log --oneline 2>/dev/null | wc -l | tr -d ' ')
        if [ "$APD_COMMIT_COUNT" -gt 2 ] && [ "${APD_FORCE_INIT:-}" != "1" ]; then
            echo "BLOCKED: Init is only for first project setup." >&2
            echo "" >&2
            echo "  This project already has $APD_COMMIT_COUNT commits." >&2
            echo "  Use the full pipeline: spec → builder → reviewer → verifier → commit" >&2
            echo "" >&2
            echo "  If this is truly a re-initialization, run:" >&2
            echo "    APD_FORCE_INIT=1 bash \${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh init \"$ARG\"" >&2
            exit 1
        fi

        echo "${NOW}|${NOW_HUMAN}|INIT: ${ARG}" > "$PIPELINE_DIR/spec.done"
        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/builder.done"
        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/reviewer.done"
        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/verifier.done"

        echo ""
        echo "  --------- INIT: $ARG ---------"
        echo "  Initial setup — no pipeline review required."
        echo "  All steps marked complete. Ready to commit."
        echo ""
        ;;

    *)
        echo "Usage:" >&2
        echo "  pipeline-advance.sh spec \"Task name\"" >&2
        echo "  pipeline-advance.sh builder|reviewer|verifier" >&2
        echo "  pipeline-advance.sh reset|status|stats|metrics" >&2
        echo "  pipeline-advance.sh rollback" >&2
        echo "  pipeline-advance.sh init \"Description\"     # First setup only" >&2
        echo "" >&2
        echo "  There is no skip command. Every feature goes through the full pipeline." >&2
        echo "  For hotfixes, use a separate terminal: git commit without APD prefix." >&2
        exit 1
        ;;
esac
