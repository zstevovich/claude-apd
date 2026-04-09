#!/bin/bash
# APD GitHub Sync — synchronizes pipeline step with GitHub Projects
#
# Usage:
#   gh-sync.sh spec "Task name"         -> creates issue, adds to board, moves to Spec
#   gh-sync.sh builder [ISSUE_NUM]      -> moves issue to In Progress
#   gh-sync.sh reviewer [ISSUE_NUM]     -> moves issue to Review
#   gh-sync.sh verifier [ISSUE_NUM]     -> moves issue to Testing
#   gh-sync.sh done ISSUE_NUM COMMIT    -> closes issue, links commit
#   gh-sync.sh skip ISSUE_NUM "Reason"  -> closes with apd-skip label
#
# Requires: gh CLI authenticated, GitHub Projects v2 configured
# Called automatically by pipeline-advance.sh at each step (best-effort, non-blocking)

source "$(dirname "$0")/lib/resolve-project.sh"

STEP="$1"
ARG2="$2"
ARG3="$3"
GH_ISSUE_FILE="$PIPELINE_DIR/.gh-issue"

if ! command -v gh &>/dev/null; then
    echo "ERROR: gh CLI is not installed or not authenticated." >&2
    exit 1
fi

# Read issue number from file if not provided
get_issue() {
    if [ -n "$ARG2" ] && echo "$ARG2" | grep -qE '^[0-9]+$'; then
        echo "$ARG2"
    elif [ -f "$GH_ISSUE_FILE" ]; then
        cat "$GH_ISSUE_FILE"
    else
        echo ""
    fi
}

case "$STEP" in
    spec)
        if [ -z "$ARG2" ]; then
            echo "ERROR: Task name is required." >&2
            exit 1
        fi

        # Find existing issue or create new one
        EXISTING_ISSUE=$(gh issue list --label "apd-pipeline" --state open --json number,title 2>/dev/null | \
            jq -r ".[] | select(.title | test(\"$ARG2\")) | .number" 2>/dev/null | head -1)

        if [ -n "$EXISTING_ISSUE" ]; then
            echo "$EXISTING_ISSUE" > "$GH_ISSUE_FILE"
            echo "GitHub issue #$EXISTING_ISSUE found (existing). Reusing."
        else
            ISSUE_URL=$(gh issue create \
                --title "[APD] $ARG2" \
                --body "## Spec Card

**Task:** $ARG2
**Created:** $(date +%Y-%m-%d\ %H:%M:%S)

---
_APD Pipeline Task_" \
                --label "apd-pipeline" 2>&1)
            GH_EXIT=$?

            if [ $GH_EXIT -eq 0 ]; then
                ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')
                echo "$ISSUE_NUM" > "$GH_ISSUE_FILE"
                echo "GitHub issue #$ISSUE_NUM created: $ISSUE_URL"
            else
                echo "WARNING: Could not create GitHub issue. Continuing without it." >&2
                echo "$ISSUE_URL" >&2
            fi
        fi
        ;;

    builder|reviewer|verifier)
        ISSUE=$(get_issue)
        case "$STEP" in
            builder)  COLUMN="In Progress" ;;
            reviewer) COLUMN="Review" ;;
            verifier) COLUMN="Testing" ;;
        esac

        if [ -n "$ISSUE" ]; then
            gh issue comment "$ISSUE" --body "Pipeline: **$STEP** completed ($(date +%Y-%m-%d\ %H:%M:%S))" 2>/dev/null
            echo "GitHub issue #$ISSUE: comment added ($STEP)"
        fi

        # Run pipeline step
        bash "$SCRIPT_DIR/pipeline-advance.sh" "$STEP"
        ;;

    done)
        ISSUE="$ARG2"
        COMMIT_HASH="$ARG3"

        if [ -z "$ISSUE" ]; then
            ISSUE=$(get_issue)
        fi

        if [ -n "$ISSUE" ]; then
            CLOSE_MSG="Completed through APD pipeline."
            [ -n "$COMMIT_HASH" ] && CLOSE_MSG="$CLOSE_MSG Commit: $COMMIT_HASH"

            gh issue close "$ISSUE" --comment "$CLOSE_MSG" 2>/dev/null
            echo "GitHub issue #$ISSUE closed."
            rm -f "$GH_ISSUE_FILE"
        fi
        ;;

    skip)
        ISSUE="$ARG2"
        REASON="$ARG3"

        if [ -z "$ISSUE" ]; then
            ISSUE=$(get_issue)
        fi

        if [ -n "$ISSUE" ]; then
            gh issue close "$ISSUE" --comment "Pipeline skipped (hotfix): ${REASON:-no reason provided}" 2>/dev/null
            gh issue edit "$ISSUE" --add-label "apd-skip" 2>/dev/null
            echo "GitHub issue #$ISSUE closed with apd-skip label."
            rm -f "$GH_ISSUE_FILE"
        fi
        ;;

    status)
        ISSUE=$(get_issue)
        if [ -n "$ISSUE" ]; then
            echo "Active GitHub issue: #$ISSUE"
            gh issue view "$ISSUE" --json title,state,labels --jq '"  \(.title) [\(.state)] labels: \([.labels[].name] | join(", "))"' 2>/dev/null
        else
            echo "No active GitHub issue for the current pipeline."
        fi
        ;;

    *)
        echo "APD GitHub Sync" >&2
        echo "" >&2
        echo "Usage:" >&2
        echo "  gh-sync.sh spec \"Task name\"" >&2
        echo "  gh-sync.sh builder|reviewer|verifier [ISSUE_NUM]" >&2
        echo "  gh-sync.sh done ISSUE_NUM [COMMIT_HASH]" >&2
        echo "  gh-sync.sh skip ISSUE_NUM \"Reason\"" >&2
        echo "  gh-sync.sh status" >&2
        exit 1
        ;;
esac
