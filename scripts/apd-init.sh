#!/bin/bash
# APD Init — initializes or updates APD environment in a project
#
# Two modes:
#   NEW PROJECT:      No .apd-config → creates everything from scratch
#   EXISTING PROJECT: .apd-config exists → gap analysis, fixes what's missing
#
# Uses userConfig env vars when available:
#   CLAUDE_PLUGIN_OPTION_PROJECT_NAME, CLAUDE_PLUGIN_OPTION_STACK, CLAUDE_PLUGIN_OPTION_AUTHOR_NAME

source "$(dirname "$0")/lib/resolve-project.sh"

# --version flag: show APD version and exit
if [ "${1:-}" = "--version" ] || [ "${1:-}" = "-v" ]; then
    VER=$(grep '"version"' "$APD_PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo "APD v${VER:-unknown} (plugin: $APD_PLUGIN_ROOT)"
    exit 0
fi

# --quick flag: skip verification (used by session-start.sh)
QUICK=false
[ "${1:-}" = "--quick" ] && QUICK=true

# --- Visual helpers ---
source "$(dirname "$0")/lib/style.sh"

FIXES=0
SKIPS=0

apd_header "Init"
echo ""

# ===========================================================
# DETECT MODE
# ===========================================================
if [ -f "$CLAUDE_DIR/.apd-config" ]; then
    MODE="update"
    echo "  Mode: ${B}Update${R} (existing APD project)"
    PROJECT_NAME=$(grep '^PROJECT_NAME=' "$CLAUDE_DIR/.apd-config" 2>/dev/null | cut -d= -f2-)
    STACK=$(grep '^STACK=' "$CLAUDE_DIR/.apd-config" 2>/dev/null | cut -d= -f2-)
else
    MODE="new"
    echo "  Mode: ${B}New project${R}"
    # Read from userConfig or fallback
    PROJECT_NAME="${CLAUDE_PLUGIN_OPTION_PROJECT_NAME:-}"
    STACK="${CLAUDE_PLUGIN_OPTION_STACK:-}"
    AUTHOR="${CLAUDE_PLUGIN_OPTION_AUTHOR_NAME:-}"
fi
echo ""

# ===========================================================
# NEW PROJECT — create everything from scratch
# ===========================================================
if [ "$MODE" = "new" ]; then
    if [ -z "$PROJECT_NAME" ]; then
        err "PROJECT_NAME not set. Configure userConfig in plugin settings or set CLAUDE_PLUGIN_OPTION_PROJECT_NAME."
        exit 1
    fi
    if [ -z "$STACK" ]; then
        err "STACK not set. Configure userConfig in plugin settings or set CLAUDE_PLUGIN_OPTION_STACK."
        exit 1
    fi

    echo "  Project: $PROJECT_NAME"
    echo "  Stack:   $STACK"
    echo "  Author:  ${AUTHOR:-$(git config user.name 2>/dev/null || echo 'unknown')}"
    echo ""

    AUTHOR="${AUTHOR:-$(git config user.name 2>/dev/null || echo 'Developer')}"

    # Create directories
    mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/rules" "$CLAUDE_DIR/scripts" "$CLAUDE_DIR/memory" "$CLAUDE_DIR/.pipeline"

    # .apd-config
    cat > "$CLAUDE_DIR/.apd-config" << EOF
PROJECT_NAME=$PROJECT_NAME
APD_VERSION=3.3.1
STACK=$STACK
EOF
    fix "Created .apd-config"

    # .apd-version
    echo "3.3.1" > "$CLAUDE_DIR/.apd-version"
    fix "Created .apd-version"

    # Copy workflow.md
    if [ -f "$APD_PLUGIN_ROOT/rules/workflow.md" ]; then
        cp "$APD_PLUGIN_ROOT/rules/workflow.md" "$CLAUDE_DIR/rules/workflow.md"
        fix "Copied workflow.md"
    fi

    # Generate principles.md
    if [ -f "$APD_PLUGIN_ROOT/templates/principles/en.md" ]; then
        cp "$APD_PLUGIN_ROOT/templates/principles/en.md" "$CLAUDE_DIR/rules/principles.md"
        fix "Created principles.md"
    fi

    # Generate verify-all.sh from stack template
    VERIFY_TEMPLATE="$APD_PLUGIN_ROOT/templates/verify-all/${STACK}.sh"
    if [ -f "$VERIFY_TEMPLATE" ]; then
        cat > "$CLAUDE_DIR/scripts/verify-all.sh" << 'HEADER'
#!/bin/bash
# APD Verify All — runs verification for all changed components
# This script lives IN THE PROJECT (.claude/scripts/verify-all.sh), not in the plugin.

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 0

# Cache — skip if Verifier step already passed recently
VERIFIED_TS_FILE="$PROJECT_DIR/.claude/.pipeline/verified.timestamp"
if [ -f "$VERIFIED_TS_FILE" ]; then
    VERIFIED_AT=$(cat "$VERIFIED_TS_FILE" 2>/dev/null | tr -d '[:space:]')
    NOW=$(date +%s)
    if [ -n "$VERIFIED_AT" ] && [ "$VERIFIED_AT" -gt 0 ] 2>/dev/null; then
        AGE=$((NOW - VERIFIED_AT))
        if [ "$AGE" -lt 120 ]; then
            echo "Verification skipped — Verifier passed ${AGE}s ago (cache <120s)" >&2
            exit 0
        fi
    fi
fi

ERRORS=()
CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null)
[ -z "$CHANGED_FILES" ] && CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null)

HEADER
        cat "$VERIFY_TEMPLATE" >> "$CLAUDE_DIR/scripts/verify-all.sh"
        cat >> "$CLAUDE_DIR/scripts/verify-all.sh" << 'FOOTER'

# Result
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "VERIFICATION FAILED:"
    for e in "${ERRORS[@]}"; do echo "  - $e"; done
    exit 1
fi
echo "Verification passed"
exit 0
FOOTER
        chmod +x "$CLAUDE_DIR/scripts/verify-all.sh"
        fix "Created verify-all.sh ($STACK)"
    else
        err "No verify-all template for stack: $STACK"
    fi

    # Memory files
    for file in MEMORY.md status.md session-log.md pipeline-skip-log.md; do
        if [ ! -f "$CLAUDE_DIR/memory/$file" ]; then
            if [ -f "$APD_PLUGIN_ROOT/templates/memory/$file" ]; then
                cp "$APD_PLUGIN_ROOT/templates/memory/$file" "$CLAUDE_DIR/memory/$file"
            else
                touch "$CLAUDE_DIR/memory/$file"
            fi
            fix "Created memory/$file"
        fi
    done

    # Settings.json
    cat > "$CLAUDE_DIR/settings.json" << EOF
{
  "env": {
    "APD_PROJECT_NAME": "$PROJECT_NAME"
  },
  "permissions": {
    "allow": [
      "Edit(.claude/memory/**)",
      "Write(.claude/memory/**)"
    ]
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": false
  },
  "attribution": {
    "commit": "",
    "pr": ""
  },
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo '[$PROJECT_NAME] Claude needs attention'"
          }
        ]
      }
    ]
  }
}
EOF
    fix "Created settings.json (superpowers disabled, attribution empty)"

    # Gitignore entries
    if [ -f "$APD_PLUGIN_ROOT/templates/gitignore-entries.txt" ]; then
        if [ ! -f "$PROJECT_DIR/.gitignore" ]; then
            cat "$APD_PLUGIN_ROOT/templates/gitignore-entries.txt" > "$PROJECT_DIR/.gitignore"
            fix "Created .gitignore"
        else
            while IFS= read -r entry; do
                [ -z "$entry" ] && continue
                [[ "$entry" == \#* ]] && continue
                if ! grep -qF "$entry" "$PROJECT_DIR/.gitignore" 2>/dev/null; then
                    echo "$entry" >> "$PROJECT_DIR/.gitignore"
                fi
            done < "$APD_PLUGIN_ROOT/templates/gitignore-entries.txt"
            fix "Updated .gitignore"
        fi
    fi

    # Git init if needed
    if ! git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        git -C "$PROJECT_DIR" init -q
        fix "Initialized git repo"
    fi

    echo ""
    echo "  ${B}NOTE:${R} CLAUDE.md and agents must be generated by the orchestrator"
    echo "  using the /apd-setup skill — they require project analysis."
    echo ""

    FIXES=$((FIXES + 1))
fi

# ===========================================================
# UPDATE MODE — gap analysis, fix what's missing
# ===========================================================
if [ "$MODE" = "update" ]; then
    echo "  Project: $PROJECT_NAME"
    echo "  Stack:   $STACK"
    echo ""

    # --- code-reviewer agent ---
    if [ -f "$CLAUDE_DIR/agents/code-reviewer.md" ]; then
        # Check model
        if grep -q 'model: opus' "$CLAUDE_DIR/agents/code-reviewer.md" 2>/dev/null; then
            ok "code-reviewer (opus/max)"
        else
            sed -i.bak 's/model:.*/model: opus/' "$CLAUDE_DIR/agents/code-reviewer.md" 2>/dev/null && rm -f "$CLAUDE_DIR/agents/code-reviewer.md.bak"
            fix "code-reviewer: fixed model to opus"
            FIXES=$((FIXES + 1))
        fi
    else
        if [ -f "$APD_PLUGIN_ROOT/templates/reviewer-template.md" ]; then
            sed "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$APD_PLUGIN_ROOT/templates/reviewer-template.md" > "$CLAUDE_DIR/agents/code-reviewer.md"
            fix "Created code-reviewer.md (opus/max, read-only)"
            FIXES=$((FIXES + 1))
        fi
    fi

    # --- maxTurns in builder agents ---
    for agent_file in "$CLAUDE_DIR/agents"/*.md; do
        [ -f "$agent_file" ] || continue
        AGENT_NAME=$(basename "$agent_file" .md)
        [ "$AGENT_NAME" = "code-reviewer" ] && continue
        if grep -q 'maxTurns' "$agent_file" 2>/dev/null; then
            ok "$AGENT_NAME: maxTurns set"
        else
            sed -i.bak '/^effort:/a\
maxTurns: 20' "$agent_file" 2>/dev/null && rm -f "$agent_file.bak"
            fix "$AGENT_NAME: added maxTurns: 20"
            FIXES=$((FIXES + 1))
        fi
    done

    # --- workflow.md ---
    if [ -f "$CLAUDE_DIR/rules/workflow.md" ]; then
        # Check for outdated ${CLAUDE_PLUGIN_ROOT} references
        if grep -q 'CLAUDE_PLUGIN_ROOT' "$CLAUDE_DIR/rules/workflow.md" 2>/dev/null; then
            cp "$APD_PLUGIN_ROOT/rules/workflow.md" "$CLAUDE_DIR/rules/workflow.md"
            fix "workflow.md: updated (removed stale CLAUDE_PLUGIN_ROOT references)"
            FIXES=$((FIXES + 1))
        else
            ok "workflow.md"
        fi
    else
        if [ -f "$APD_PLUGIN_ROOT/rules/workflow.md" ]; then
            mkdir -p "$CLAUDE_DIR/rules"
            cp "$APD_PLUGIN_ROOT/rules/workflow.md" "$CLAUDE_DIR/rules/workflow.md"
            fix "Copied workflow.md"
            FIXES=$((FIXES + 1))
        fi
    fi

    # --- settings.json: superpowers disabled ---
    if [ -f "$CLAUDE_DIR/settings.json" ]; then
        if grep -q '"superpowers@claude-plugins-official"' "$CLAUDE_DIR/settings.json" 2>/dev/null; then
            ok "superpowers disabled in settings"
        else
            # Add superpowers disable to enabledPlugins
            if grep -q '"enabledPlugins"' "$CLAUDE_DIR/settings.json" 2>/dev/null; then
                sed -i.bak '/"enabledPlugins".*{/a\
    "superpowers@claude-plugins-official": false,' "$CLAUDE_DIR/settings.json" 2>/dev/null && rm -f "$CLAUDE_DIR/settings.json.bak"
            else
                # Add enabledPlugins section before closing brace
                tmp=$(mktemp)
                awk '
                /^}$/ {
                    print "  ,\"enabledPlugins\": {"
                    print "    \"superpowers@claude-plugins-official\": false"
                    print "  }"
                    print "}"
                    next
                }
                { print }
                ' "$CLAUDE_DIR/settings.json" > "$tmp" && mv "$tmp" "$CLAUDE_DIR/settings.json"
            fi
            fix "Disabled superpowers in settings.json"
            FIXES=$((FIXES + 1))
        fi

        # Attribution
        if grep -q '"attribution"' "$CLAUDE_DIR/settings.json" 2>/dev/null; then
            ok "attribution configured"
        else
            tmp=$(mktemp)
            awk '
            /^}$/ {
                print "  ,\"attribution\": {"
                print "    \"commit\": \"\","
                print "    \"pr\": \"\""
                print "  }"
                print "}"
                next
            }
            { print }
            ' "$CLAUDE_DIR/settings.json" > "$tmp" && mv "$tmp" "$CLAUDE_DIR/settings.json"
            fix "Added attribution (empty, no AI signatures)"
            FIXES=$((FIXES + 1))
        fi

        # Permissions — auto-allow memory writes
        if grep -q '"permissions"' "$CLAUDE_DIR/settings.json" 2>/dev/null; then
            ok "permissions configured"
        else
            tmp=$(mktemp)
            awk '
            /^}$/ {
                print "  ,\"permissions\": {"
                print "    \"allow\": ["
                print "      \"Edit(.claude/memory/**)\","
                print "      \"Write(.claude/memory/**)\""
                print "    ]"
                print "  }"
                print "}"
                next
            }
            { print }
            ' "$CLAUDE_DIR/settings.json" > "$tmp" && mv "$tmp" "$CLAUDE_DIR/settings.json"
            fix "Added permissions (auto-allow memory writes)"
            FIXES=$((FIXES + 1))
        fi
    fi

    # --- Memory files ---
    for file in MEMORY.md status.md session-log.md pipeline-skip-log.md; do
        if [ -f "$CLAUDE_DIR/memory/$file" ]; then
            ok "memory/$file"
        else
            mkdir -p "$CLAUDE_DIR/memory"
            touch "$CLAUDE_DIR/memory/$file"
            fix "Created memory/$file"
            FIXES=$((FIXES + 1))
        fi
    done

    # --- .apd-version ---
    CURRENT_VER=$(cat "$CLAUDE_DIR/.apd-version" 2>/dev/null | tr -d '[:space:]')
    PLUGIN_VER="3.3.1"
    if [ "$CURRENT_VER" = "$PLUGIN_VER" ]; then
        ok ".apd-version ($CURRENT_VER)"
    else
        echo "$PLUGIN_VER" > "$CLAUDE_DIR/.apd-version"
        fix "Updated .apd-version: $CURRENT_VER → $PLUGIN_VER"
        FIXES=$((FIXES + 1))
    fi
fi

# ===========================================================
# SUMMARY
# ===========================================================
echo ""
if [ "$FIXES" -gt 0 ]; then
    echo "  ${G}${FIXES} fix(es) applied.${R}"
else
    echo "  ${B}Everything up to date.${R}"
fi
echo ""

# Run verify-apd.sh (skip in quick mode)
if [ "$QUICK" = true ]; then
    exit 0
fi
echo "  Running verification..."
echo ""
bash "$SCRIPT_DIR/verify-apd.sh"
