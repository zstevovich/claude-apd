#!/bin/bash
# APD Pipeline Advance — advances pipeline step with timestamps
#
# Usage:
#   pipeline-advance.sh spec "Task name"
#   pipeline-advance.sh builder|reviewer|verifier
#   pipeline-advance.sh reset|status|stats|metrics|rollback
#   pipeline-advance.sh init "Description"  (first setup only)

source "$(dirname "$0")/lib/resolve-project.sh"

mkdir -p "$PIPELINE_DIR"

# File lock — prevent concurrent pipeline operations
LOCK_FILE="$PIPELINE_DIR/.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "BLOCKED: Pipeline is locked by another session." >&2
    echo "  Wait for the other session to finish or remove .pipeline/.lock" >&2
    exit 1
fi

STEP="$1"
ARG="$2"
NOW=$(date +%s)
NOW_HUMAN=$(date +"%Y-%m-%d %H:%M:%S")

# --- Visual helpers ---
source "$(dirname "$0")/lib/style.sh"

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

        # Validate spec-card.md exists and has R* criteria (hard block)
        if [ ! -f "$PIPELINE_DIR/spec-card.md" ]; then
            echo "BLOCKED: spec-card.md not found." >&2
            echo "" >&2
            echo "  Write the spec card to .claude/.pipeline/spec-card.md before advancing." >&2
            echo "  Acceptance criteria must use R1:, R2:, ... format." >&2
            exit 1
        fi
        if ! grep -qE '^[[:space:]]*-[[:space:]]+R[0-9]+[[:space:]]*:' "$PIPELINE_DIR/spec-card.md"; then
            echo "BLOCKED: spec-card.md has no R* acceptance criteria." >&2
            echo "" >&2
            echo "  Expected format in spec-card.md:" >&2
            echo "    - R1: First requirement" >&2
            echo "    - R2: Second requirement" >&2
            exit 1
        fi
        # Check criteria count — too many means feature should be decomposed
        MAX_CRITERIA=7
        CRITERIA_COUNT=$(grep -cE '^[[:space:]]*-[[:space:]]+R[0-9]+[[:space:]]*:' "$PIPELINE_DIR/spec-card.md" 2>/dev/null || echo 0)
        if [ "$CRITERIA_COUNT" -gt "$MAX_CRITERIA" ]; then
            echo "BLOCKED: spec-card.md has $CRITERIA_COUNT criteria (max $MAX_CRITERIA)." >&2
            echo "" >&2
            echo "  Decompose into smaller tasks — each task should be one pipeline cycle." >&2
            echo "  Large features = large rollbacks. Small tasks = safe commits." >&2
            exit 1
        fi

        # Archive agent log before clearing (permanent audit trail)
        if [ -f "$PIPELINE_DIR/.agents" ]; then
            cat "$PIPELINE_DIR/.agents" >> "$MEMORY_DIR/agent-history.log"
        fi
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents" "$PIPELINE_DIR/.trace-summary" "$PIPELINE_DIR/.adversarial-summary" "$PIPELINE_DIR/implementation-plan.md" "$PIPELINE_DIR/.spec-hash"
        echo "${NOW}|${NOW_HUMAN}|${ARG}" > "$PIPELINE_DIR/spec.done"
        # Freeze spec-card.md — hash for tamper detection
        shasum -a 256 "$PIPELINE_DIR/spec-card.md" | cut -d' ' -f1 > "$PIPELINE_DIR/.spec-hash"
        apd_spec_header "$ARG"
        show_pipeline "builder"
        # GitHub sync (best-effort — never blocks pipeline)
        bash "$SCRIPT_DIR/gh-sync.sh" spec "$ARG" 2>/dev/null || true
        # Pre-flight checklist
        echo "" >&2
        echo "    ${D}Next steps:${R}" >&2
        echo "    ${D}1. Write .pipeline/implementation-plan.md (files + changes)${R}" >&2
        echo "    ${D}2. Dispatch project builders: Agent({ subagent_type: \"<agent-name>\", ... })${R}" >&2
        echo "    ${D}3. Dispatch project reviewer: Agent({ subagent_type: \"code-reviewer\", ... })${R}" >&2
        echo "    ${D}   NEVER use superpowers: or feature-dev: agents — pipeline will BLOCK${R}" >&2
        ;;

    builder)
        if [ ! -f "$PIPELINE_DIR/spec.done" ]; then
            echo "ERROR: Spec must be completed before builder!" >&2
            exit 1
        fi

        # Verify implementation plan exists (hard block)
        if [ ! -f "$PIPELINE_DIR/implementation-plan.md" ]; then
            echo "BLOCKED: implementation-plan.md not found." >&2
            echo "" >&2
            echo "  Write the implementation plan to .claude/.pipeline/implementation-plan.md" >&2
            echo "  List files to change with 1-2 sentences per file describing the change." >&2
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
        apd_header "Builder Complete" "+$ELAPSED"
        show_pipeline "reviewer"
        # GitHub sync (best-effort)
        bash "$SCRIPT_DIR/gh-sync.sh" builder 2>/dev/null || true
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
                echo "  Rejected: ${BLOCKED_AGENTS%, }" >&2
                echo "  These are plugin agents, NOT project agents." >&2
                echo "" >&2
            fi
            echo "  Dispatch the project code-reviewer using the Agent tool:" >&2
            echo "    Agent({ subagent_type: \"code-reviewer\", prompt: \"Review...\" })" >&2
            echo "" >&2
            echo "  NEVER use superpowers:code-reviewer or feature-dev:code-reviewer." >&2
            echo "  If reviewer step fails, do NOT rollback code — fix the dispatch and retry." >&2
            exit 1
        fi

        BUILDER_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/builder.done")
        ELAPSED=$(format_duration $((NOW - BUILDER_TS)))
        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/reviewer.done"
        apd_header "Reviewer Complete" "+$ELAPSED"
        show_pipeline "verifier"
        # GitHub sync (best-effort)
        bash "$SCRIPT_DIR/gh-sync.sh" reviewer 2>/dev/null || true
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
        # Verify spec-card.md was not modified after spec step (frozen)
        if [ -f "$PIPELINE_DIR/.spec-hash" ] && [ -f "$PIPELINE_DIR/spec-card.md" ]; then
            ORIGINAL_HASH=$(cat "$PIPELINE_DIR/.spec-hash")
            CURRENT_HASH=$(shasum -a 256 "$PIPELINE_DIR/spec-card.md" | cut -d' ' -f1)
            if [ "$ORIGINAL_HASH" != "$CURRENT_HASH" ]; then
                echo "BLOCKED: spec-card.md was modified after spec step." >&2
                echo "" >&2
                echo "  Spec is frozen after approval. Do not add criteria mid-pipeline." >&2
                echo "  To change scope: pipeline-advance.sh rollback → update spec → restart." >&2
                exit 1
            fi
        fi
        # Run spec traceability check (if spec-card.md exists)
        if [ -f "$PIPELINE_DIR/spec-card.md" ]; then
            TRACE_OUT=$(bash "$SCRIPT_DIR/verify-trace.sh" 2>&1 1>"$PIPELINE_DIR/.trace-summary")
            TRACE_EXIT=$?
            # Show the report (was on stderr, captured above)
            [ -n "$TRACE_OUT" ] && echo "$TRACE_OUT" >&2
            if [ "$TRACE_EXIT" -ne 0 ]; then
                echo "" >&2
                echo "  Fix: Add @trace R* markers in test files for uncovered criteria." >&2
                echo "  Then re-run: pipeline-advance.sh verifier" >&2
                exit 1
            fi
        fi

        # Warn if adversarial reviewer is configured but wasn't used
        if [ -f "$CLAUDE_DIR/agents/adversarial-reviewer.md" ] && [ ! -f "$PIPELINE_DIR/.adversarial-summary" ]; then
            warn "Adversarial reviewer is configured but was not used this task." >&2
            echo "    Write ADVERSARIAL:total:accepted:dismissed to .pipeline/.adversarial-summary" >&2
        fi

        echo "${NOW}|${NOW_HUMAN}" > "$PIPELINE_DIR/verifier.done"
        # Cache timestamp — verify-all.sh skips rebuild if fresh (<120s)
        echo "$NOW" > "$PIPELINE_DIR/verified.timestamp"
        apd_header "COMMIT ALLOWED" "total: $TOTAL"
        show_pipeline ""
        echo "    Ready: APD_ORCHESTRATOR_COMMIT=1 git commit ..."
        # GitHub sync (best-effort)
        bash "$SCRIPT_DIR/gh-sync.sh" verifier 2>/dev/null || true
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
            # Read adversarial stats for metrics
            ADV_T=0; ADV_A=0; ADV_D=0
            if [ -f "$PIPELINE_DIR/.adversarial-summary" ]; then
                IFS=: read -r _prefix ADV_T ADV_A ADV_D < "$PIPELINE_DIR/.adversarial-summary" 2>/dev/null || true
                ADV_T=${ADV_T:-0}; ADV_A=${ADV_A:-0}; ADV_D=${ADV_D:-0}
            fi
            echo "${NOW}|${TASK_NAME}|${SPEC_TS_V}|${BUILDER_TS_V}|${REVIEWER_TS_V}|${VERIFIER_TS_V}|${STATUS}|${ADV_T}|${ADV_A}|${ADV_D}" >> "$METRICS_LOG"

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

                # 6. Agents dispatched during this task
                AGENTS_SUMMARY="none"
                AGENTS_LOG="$PIPELINE_DIR/.agents"
                if [ -f "$AGENTS_LOG" ]; then
                    AGENT_LIST=$(grep '|stop|' "$AGENTS_LOG" | cut -d'|' -f3 | sort -u | tr '\n' ', ' | sed 's/,$//' | sed 's/,/, /g')
                    [ -n "$AGENT_LIST" ] && AGENTS_SUMMARY="$AGENT_LIST"
                fi

                # 7. Spec trace coverage
                TRACE_COVERAGE=""
                if [ -f "$PIPELINE_DIR/.trace-summary" ]; then
                    TRACE_LINE=$(cat "$PIPELINE_DIR/.trace-summary")
                    TRACE_COVERED=$(echo "$TRACE_LINE" | cut -d: -f2 | cut -d/ -f1)
                    TRACE_TOTAL=$(echo "$TRACE_LINE" | cut -d: -f2 | cut -d/ -f2)
                    TRACE_MISSING=$(echo "$TRACE_LINE" | cut -d: -f3)
                    if [ -n "$TRACE_TOTAL" ] && [ "$TRACE_TOTAL" != "0" ]; then
                        if [ -z "$TRACE_MISSING" ]; then
                            TRACE_COVERAGE="${TRACE_COVERED}/${TRACE_TOTAL} (all covered)"
                        else
                            TRACE_COVERAGE="${TRACE_COVERED}/${TRACE_TOTAL} (missing: ${TRACE_MISSING})"
                        fi
                    fi
                fi

                # 8. Adversarial review hit rate
                ADV_REVIEW=""
                if [ -f "$PIPELINE_DIR/.adversarial-summary" ]; then
                    ADV_LINE=$(cat "$PIPELINE_DIR/.adversarial-summary")
                    # Format: ADVERSARIAL:total:accepted:dismissed
                    ADV_TOTAL=$(echo "$ADV_LINE" | cut -d: -f2)
                    ADV_ACCEPTED=$(echo "$ADV_LINE" | cut -d: -f3)
                    ADV_DISMISSED=$(echo "$ADV_LINE" | cut -d: -f4)
                    if [ -n "$ADV_TOTAL" ] && [ "$ADV_TOTAL" != "0" ]; then
                        ADV_REVIEW="${ADV_TOTAL} findings (${ADV_ACCEPTED} accepted, ${ADV_DISMISSED} dismissed)"
                    fi
                fi

                # --- Generate entry ---
                cat >> "$SESSION_LOG" << EOF

## [$(date +%Y-%m-%d)] $TASK_NAME
**Status:** $PIPELINE_STATUS
**Spec coverage:** ${TRACE_COVERAGE:-N/A}
**Adversarial review:** ${ADV_REVIEW:-N/A}
**What was done:** $CHANGED_SUMMARY
**Agents:** $AGENTS_SUMMARY
**Problems:** $PROBLEMS
**Guardrail that helped:** $GUARD_SUMMARY
**New rule:** $NEW_RULE
**Pipeline duration:**$TOTAL
EOF
                echo "Session log updated (auto-summary): $TASK_NAME" >&2
            fi
        fi
        # Archive agent log before clearing
        if [ -f "$PIPELINE_DIR/.agents" ]; then
            cat "$PIPELINE_DIR/.agents" >> "$MEMORY_DIR/agent-history.log"
        fi
        # GitHub sync — mark done (best-effort, before cleanup removes .gh-issue)
        bash "$SCRIPT_DIR/gh-sync.sh" done 2>/dev/null || true
        rm -f "$PIPELINE_DIR"/*.done "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.agents" "$PIPELINE_DIR/.trace-summary" "$PIPELINE_DIR/.adversarial-summary" "$PIPELINE_DIR/spec-card.md" "$PIPELINE_DIR/implementation-plan.md" "$PIPELINE_DIR/.spec-hash"
        echo "Pipeline reset. Ready for new task."
        ;;

    rollback)
        # Find the last completed step and remove it
        ROLLED_BACK=false
        for step in verifier reviewer builder spec; do
            if [ -f "$PIPELINE_DIR/$step.done" ]; then
                rm -f "$PIPELINE_DIR/$step.done"
                # If verifier rolled back, also remove cache timestamp and trace summary
                [ "$step" = "verifier" ] && rm -f "$PIPELINE_DIR/verified.timestamp" "$PIPELINE_DIR/.trace-summary" "$PIPELINE_DIR/.adversarial-summary"
                [ "$step" = "builder" ] && rm -f "$PIPELINE_DIR/implementation-plan.md"
                apd_header "Rollback: $step"
                show_pipeline "$step"
                ROLLED_BACK=true
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

        if [ -n "$SPEC_TIME" ]; then
            TOTAL_ELAPSED=$(format_duration $(($(date +%s) - SPEC_TS)))
            apd_header "$TASK" "$TOTAL_ELAPSED"
        else
            apd_header "Pipeline Status"
        fi
        show_pipeline "$NEXT_STEP"

        # Detailed timing below the box
        PREV_TS="${SPEC_TS:-}"
        for step in spec builder reviewer verifier; do
            if [ -f "$PIPELINE_DIR/$step.done" ]; then
                STEP_TS=$(cut -d'|' -f1 "$PIPELINE_DIR/$step.done")
                if [ "$step" != "spec" ] && [ -n "$PREV_TS" ]; then
                    DELTA=$(format_duration $((STEP_TS - PREV_TS)))
                    sc=$(_step_color "$step")
                    printf "    %s■%s %-12s +%s\n" "$sc" "$R" "$step" "$DELTA"
                fi
                PREV_TS="$STEP_TS"
            else
                if [ -n "$PREV_TS" ]; then
                    WAITING=$(format_duration $(($(date +%s) - PREV_TS)))
                    sc=$(_step_color "$step")
                    printf "    %s□%s %-12s waiting %s\n" "$sc" "$R" "$step" "$WAITING"
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
        COMPLETED=$(grep -c '|completed' "$METRICS_LOG" 2>/dev/null || echo 0)
        PARTIAL=$(grep -c '|partial' "$METRICS_LOG" 2>/dev/null || echo 0)
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

        while IFS='|' read -r _ts task_name spec_ts builder_ts reviewer_ts verifier_ts status _adv_t _adv_a _adv_d; do
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

        apd_header "Pipeline Metrics"

        section "Overview"
        printf "    %-22s %s\n" "Total tasks:" "$TOTAL_TASKS ($COMPLETED completed, $PARTIAL partial)"
        printf "    %-22s %s\n" "Average duration:" "$AVG_DURATION"
        printf "    %-22s %s\n" "Fastest:" "$FASTEST_FMT"
        printf "    %-22s %s\n" "Slowest:" "$SLOWEST_FMT"
        printf "    %-22s %s\n" "Skip rate:" "$SKIP_RATE"

        section "Average per step"
        printf "    %-22s %s\n" "spec → builder:" "$AVG_S2B"
        printf "    %-22s %s\n" "builder → reviewer:" "$AVG_B2R"
        printf "    %-22s %s\n" "reviewer → verifier:" "$AVG_R2V"

        # Adversarial hit rate (cumulative)
        ADV_TOTAL_SUM=0
        ADV_ACCEPTED_SUM=0
        ADV_TASKS=0
        while IFS='|' read -r _ts _task _s _b _r _v _status adv_t adv_a adv_d; do
            adv_t=$(echo "${adv_t:-0}" | tr -d '[:space:]')
            adv_a=$(echo "${adv_a:-0}" | tr -d '[:space:]')
            [ "$adv_t" -gt 0 ] 2>/dev/null && {
                ADV_TOTAL_SUM=$((ADV_TOTAL_SUM + adv_t))
                ADV_ACCEPTED_SUM=$((ADV_ACCEPTED_SUM + adv_a))
                ADV_TASKS=$((ADV_TASKS + 1))
            }
        done < "$METRICS_LOG"

        if [ "$ADV_TASKS" -gt 0 ]; then
            ADV_RATE=$((ADV_ACCEPTED_SUM * 100 / ADV_TOTAL_SUM))
            section "Adversarial review"
            printf "    %-22s %s\n" "Hit rate:" "${ADV_RATE}% (${ADV_ACCEPTED_SUM}/${ADV_TOTAL_SUM} accepted across ${ADV_TASKS} tasks)"
        fi

        section "Last 5"
        tail -5 "$METRICS_LOG" | while IFS='|' read -r _ts task_name spec_ts _b _r verifier_ts status _adv_t _adv_a _adv_d; do
            verifier_ts=$(echo "$verifier_ts" | tr -d '[:space:]')
            spec_ts=$(echo "$spec_ts" | tr -d '[:space:]')
            status=$(echo "$status" | tr -d '[:space:]')
            DUR="N/A"
            if [ "$verifier_ts" -gt 0 ] 2>/dev/null && [ "$spec_ts" -gt 0 ] 2>/dev/null; then
                DUR=$(format_duration $((verifier_ts - spec_ts)))
            fi
            ICON="${MARK_PASS}"
            [ "$status" = "partial" ] && ICON="${D}…${R}"
            printf "    %s %-24s %s\n" "$ICON" "$task_name" "$DUR"
        done
        echo ""
        ;;

    init)
        if [ -z "$ARG" ]; then
            echo "ERROR: Description for init is required." >&2
            exit 1
        fi

        # Init only allowed if no previous commits with APD (first setup)
        APD_COMMIT_COUNT=$(git -C "$PROJECT_DIR" log --oneline --all -- .claude/ 2>/dev/null | wc -l | tr -d ' ')
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

        apd_header "Initial Setup"
        echo "    $ARG"
        echo "    All steps marked complete. Ready to commit."
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
