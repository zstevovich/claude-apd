#!/bin/bash
# APD GitHub Sync — sinhronizuje pipeline korak sa GitHub Projects
#
# Korišćenje:
#   gh-sync.sh spec "Naziv taska"       → kreira issue, dodaje na board, pomera u Spec
#   gh-sync.sh builder [ISSUE_NUM]      → pomera issue u In Progress
#   gh-sync.sh reviewer [ISSUE_NUM]     → pomera issue u Review
#   gh-sync.sh verifier [ISSUE_NUM]     → pomera issue u Testing
#   gh-sync.sh done ISSUE_NUM COMMIT    → zatvara issue, linkuje commit
#   gh-sync.sh skip ISSUE_NUM "Razlog"  → zatvara sa apd-skip labelom
#
# Zahteva: gh CLI autentifikovan, GitHub Projects v2 konfigurisan
# Opciono: Ova skripta se NE poziva automatski — orkestrator je koristi po potrebi

STEP="$1"
ARG2="$2"
ARG3="$3"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/.pipeline"
GH_ISSUE_FILE="$PIPELINE_DIR/.gh-issue"

if ! command -v gh &>/dev/null; then
    echo "GREŠKA: gh CLI nije instaliran ili nije autentifikovan." >&2
    exit 1
fi

# Pročitaj issue number iz fajla ako nije prosleđen
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
            echo "GREŠKA: Naziv taska je obavezan." >&2
            exit 1
        fi

        # Kreiraj issue
        ISSUE_URL=$(gh issue create \
            --title "[APD] $ARG2" \
            --body "## Spec kartica

**Task:** $ARG2
**Kreiran:** $(date +%Y-%m-%d\ %H:%M:%S)

---
_APD Pipeline Task_" \
            --label "apd-pipeline" 2>&1)

        if [ $? -eq 0 ]; then
            ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')
            echo "$ISSUE_NUM" > "$GH_ISSUE_FILE"
            echo "GitHub issue #$ISSUE_NUM kreiran: $ISSUE_URL"

            # Pomeri u Spec kolonu ako je Projects konfigurisan
            # (gh project item-edit zahteva project number — orkestrator podešava)
        else
            echo "UPOZORENJE: Nije moguće kreirati GitHub issue. Nastavljam bez." >&2
            echo "$ISSUE_URL" >&2
        fi

        # Pokreni pipeline spec
        bash "$SCRIPT_DIR/pipeline-advance.sh" spec "$ARG2"
        ;;

    builder|reviewer|verifier)
        ISSUE=$(get_issue)
        COLUMN_MAP_builder="In Progress"
        COLUMN_MAP_reviewer="Review"
        COLUMN_MAP_verifier="Testing"

        eval "COLUMN=\$COLUMN_MAP_$STEP"

        if [ -n "$ISSUE" ]; then
            gh issue comment "$ISSUE" --body "Pipeline: **$STEP** završen ($(date +%Y-%m-%d\ %H:%M:%S))" 2>/dev/null
            echo "GitHub issue #$ISSUE: komentar dodat ($STEP)"
        fi

        # Pokreni pipeline korak
        bash "$SCRIPT_DIR/pipeline-advance.sh" "$STEP"
        ;;

    done)
        ISSUE="$ARG2"
        COMMIT_HASH="$ARG3"

        if [ -z "$ISSUE" ]; then
            ISSUE=$(get_issue)
        fi

        if [ -n "$ISSUE" ]; then
            CLOSE_MSG="Završen kroz APD pipeline."
            [ -n "$COMMIT_HASH" ] && CLOSE_MSG="$CLOSE_MSG Commit: $COMMIT_HASH"

            gh issue close "$ISSUE" --comment "$CLOSE_MSG" 2>/dev/null
            echo "GitHub issue #$ISSUE zatvoren."
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
            gh issue close "$ISSUE" --comment "Pipeline preskočen (hotfix): ${REASON:-bez razloga}" 2>/dev/null
            gh issue edit "$ISSUE" --add-label "apd-skip" 2>/dev/null
            echo "GitHub issue #$ISSUE zatvoren sa apd-skip labelom."
            rm -f "$GH_ISSUE_FILE"
        fi
        ;;

    status)
        ISSUE=$(get_issue)
        if [ -n "$ISSUE" ]; then
            echo "Aktivan GitHub issue: #$ISSUE"
            gh issue view "$ISSUE" --json title,state,labels --jq '"  \(.title) [\(.state)] labels: \([.labels[].name] | join(", "))"' 2>/dev/null
        else
            echo "Nema aktivnog GitHub issue-a za trenutni pipeline."
        fi
        ;;

    *)
        echo "APD GitHub Sync" >&2
        echo "" >&2
        echo "Korišćenje:" >&2
        echo "  gh-sync.sh spec \"Naziv taska\"" >&2
        echo "  gh-sync.sh builder|reviewer|verifier [ISSUE_NUM]" >&2
        echo "  gh-sync.sh done ISSUE_NUM [COMMIT_HASH]" >&2
        echo "  gh-sync.sh skip ISSUE_NUM \"Razlog\"" >&2
        echo "  gh-sync.sh status" >&2
        exit 1
        ;;
esac
