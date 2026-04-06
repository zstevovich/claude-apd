#!/bin/bash
# APD Session Start — učitava kontekst projekta na početku sesije

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 0

MEMORY_DIR=".claude/memory"
PIPELINE_DIR=".claude/.pipeline"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ===== VERSION CHECK =====
APD_MIN_VERSION="2.1.89"
APD_FUNCTIONAL_VERSION="2.1.32"

if command -v claude &>/dev/null; then
    CC_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -n "$CC_VERSION" ]; then
        # Uporedi verzije: pretvori u numeričku vrednost (major*10000 + minor*100 + patch)
        ver_to_num() {
            echo "$1" | awk -F. '{ printf "%d%02d%02d", $1, $2, $3 }'
        }
        CC_NUM=$(ver_to_num "$CC_VERSION")
        MIN_NUM=$(ver_to_num "$APD_MIN_VERSION")
        FUNC_NUM=$(ver_to_num "$APD_FUNCTIONAL_VERSION")

        if [ "$CC_NUM" -lt "$FUNC_NUM" ] 2>/dev/null; then
            echo "╔═══════════════════════════════════════════════════════╗"
            echo "║  ⛔ APD: Claude Code $CC_VERSION je PRESTARA                ║"
            echo "║  Minimum za APD: v$APD_FUNCTIONAL_VERSION (agenti + pipeline)       ║"
            echo "║  Ažuriraj: npm install -g @anthropic-ai/claude-code  ║"
            echo "╚═══════════════════════════════════════════════════════╝"
            echo ""
        elif [ "$CC_NUM" -lt "$MIN_NUM" ] 2>/dev/null; then
            echo "╔═══════════════════════════════════════════════════════╗"
            echo "║  ⚠ APD: Claude Code $CC_VERSION — nedostaju feature-i      ║"
            echo "║  Preporučeno: v$APD_MIN_VERSION+ za pun APD feature set     ║"
            echo "║  Nedostaje: conditional hooks, PostCompact,         ║"
            echo "║    PermissionDenied, effort frontmatter             ║"
            echo "║  Ažuriraj: npm install -g @anthropic-ai/claude-code ║"
            echo "╚═══════════════════════════════════════════════════════╝"
            echo ""
        fi
    fi
fi
# =========================

# ===== SELF-HEALING — detektuj i popravi probleme =====
HEALED=0
BLOCKED=0

heal()  { echo "  ✓ HEALED: $1"; ((HEALED++)); }
block() { echo "  ✗ BLOCKED: $1"; ((BLOCKED++)); }

# 1. jq — bez njega guard-ovi ne rade (ne može se auto-popraviti)
if ! command -v jq &>/dev/null; then
    block "jq NIJE instaliran — guard skripte neće raditi!"
    echo "    → Instaliraj: brew install jq (macOS) / apt install jq (Linux)"
fi

# 2. Skripte — ako postoje ali nisu executable, popravi automatski
for script in guard-git.sh guard-scope.sh guard-bash-scope.sh guard-secrets.sh guard-lockfile.sh pipeline-advance.sh pipeline-gate.sh verify-all.sh session-start.sh rotate-session-log.sh verify-apd.sh verify-contracts.sh; do
    SCRIPT_PATH="$SCRIPT_DIR/$script"
    if [ -f "$SCRIPT_PATH" ] && [ ! -x "$SCRIPT_PATH" ]; then
        chmod +x "$SCRIPT_PATH" 2>/dev/null
        if [ -x "$SCRIPT_PATH" ]; then
            heal "$script nije bio executable — popravljeno (chmod +x)"
        else
            block "$script nije executable i ne može se popraviti (dozvole?)"
        fi
    elif [ ! -f "$SCRIPT_PATH" ]; then
        # Samo kritične skripte su blocker
        case "$script" in
            guard-git.sh|pipeline-advance.sh|pipeline-gate.sh)
                block "$script NEDOSTAJE — pipeline neće raditi"
                ;;
        esac
    fi
done

# 3. settings.json — detektuj merge conflict markere
SETTINGS_FILE="$PROJECT_DIR/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
    if grep -qE '^(<<<<<<<|=======|>>>>>>>)' "$SETTINGS_FILE" 2>/dev/null; then
        CONFLICT_LINE=$(grep -nE '^(<<<<<<<|=======|>>>>>>>)' "$SETTINGS_FILE" | head -1 | cut -d: -f1)
        block "settings.json ima merge conflict (linija $CONFLICT_LINE) — reši ručno"
    elif ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
        block "settings.json NIJE validan JSON — proveri sintaksu"
    fi
fi

# 4. Stale pipeline — flags stariji od 24h
if [ -d "$PIPELINE_DIR" ] && ls "$PIPELINE_DIR"/*.done &>/dev/null 2>&1; then
    OLDEST_FLAG=$(ls -t "$PIPELINE_DIR"/*.done 2>/dev/null | tail -1)
    if [ -n "$OLDEST_FLAG" ]; then
        MTIME=$(stat -f %m "$OLDEST_FLAG" 2>/dev/null || stat -c %Y "$OLDEST_FLAG" 2>/dev/null || echo "")
        if [ -n "$MTIME" ] && [ "$MTIME" -gt 0 ] 2>/dev/null; then
            FLAG_AGE=$(( $(date +%s) - MTIME ))
        else
            FLAG_AGE=0
        fi
        if [ "$FLAG_AGE" -gt 86400 ]; then
            # Prikupi kontekst pre reset-a
            STALE_TASK="[nepoznat]"
            STALE_STEP="spec"
            if [ -f "$PIPELINE_DIR/spec.done" ]; then
                STALE_TASK=$(cut -d'|' -f3 "$PIPELINE_DIR/spec.done" 2>/dev/null)
            fi
            for step in verifier reviewer builder spec; do
                if [ -f "$PIPELINE_DIR/$step.done" ]; then
                    STALE_STEP="$step"
                    break
                fi
            done

            STALE_HOURS=$((FLAG_AGE / 3600))
            heal "Stale pipeline detektovan (${STALE_HOURS}h star)"
            echo "    → Task: $STALE_TASK (poslednji korak: $STALE_STEP)"
            echo "    → Automatski resetujem..."
            bash "$SCRIPT_DIR/pipeline-advance.sh" reset >/dev/null 2>&1
            echo "    → Pipeline resetovan. Spreman za novi task."
        fi
    fi
fi

# 5. Nedovršen pipeline — prikaži gde je stao i šta je sledeće
if [ -d "$PIPELINE_DIR" ] && ls "$PIPELINE_DIR"/*.done &>/dev/null 2>&1; then
    # Pipeline postoji ali nije stale — prikaži kontekst
    INCOMPLETE=false
    NEXT_STEP=""
    for step in spec builder reviewer verifier; do
        if [ ! -f "$PIPELINE_DIR/$step.done" ]; then
            INCOMPLETE=true
            NEXT_STEP="$step"
            break
        fi
    done

    if [ "$INCOMPLETE" = true ] && [ -n "$NEXT_STEP" ]; then
        CURRENT_TASK="[nepoznat]"
        if [ -f "$PIPELINE_DIR/spec.done" ]; then
            CURRENT_TASK=$(cut -d'|' -f3 "$PIPELINE_DIR/spec.done" 2>/dev/null)
        fi
        echo "  → Pipeline u toku: $CURRENT_TASK — sledeći korak: $NEXT_STEP"
    fi
fi

# Prikaži summary
if [ "$HEALED" -gt 0 ] || [ "$BLOCKED" -gt 0 ]; then
    echo ""
    if [ "$BLOCKED" -gt 0 ]; then
        echo "╔═══════════════════════════════════════════════════╗"
        printf "║  ⚠ APD: %d popravljeno, %d zahteva pažnju           ║\n" "$HEALED" "$BLOCKED"
        echo "║  Pokreni: bash .claude/scripts/verify-apd.sh      ║"
        echo "╚═══════════════════════════════════════════════════╝"
    else
        echo "╔═══════════════════════════════════════════════════╗"
        printf "║  ✓ APD: %d problem(a) automatski popravljeno        ║\n" "$HEALED"
        echo "╚═══════════════════════════════════════════════════╝"
    fi
    echo ""
fi
# ========================================

# Rotiraj session log (čuva poslednjih 10 entry-ja)
if [ -x "$SCRIPT_DIR/rotate-session-log.sh" ]; then
    bash "$SCRIPT_DIR/rotate-session-log.sh" 10 2>/dev/null
fi

# ===== PRILAGODI IME PROJEKTA =====
echo "=== {{PROJECT_NAME}} ==="
# ==================================
echo ""

# Status
if [ -f "$MEMORY_DIR/status.md" ]; then
  echo "--- Trenutni status ---"
  head -30 "$MEMORY_DIR/status.md"
  echo ""
fi

# Pipeline
echo "--- Pipeline ---"
if [ -d "$PIPELINE_DIR" ] && ls "$PIPELINE_DIR"/*.done &>/dev/null; then
    TASK="[idle]"
    if [ -f "$PIPELINE_DIR/spec.done" ]; then
        TASK=$(cut -d'|' -f3 "$PIPELINE_DIR/spec.done" 2>/dev/null)
    fi
    echo "Task: $TASK"
    for step in spec builder reviewer verifier; do
        if [ -f "$PIPELINE_DIR/$step.done" ]; then
            echo "  [DONE] $step"
        else
            echo "  [----] $step"
        fi
    done
else
    echo "  [idle] Nema aktivnog pipeline-a"
fi
echo ""

# Poslednja sesija
if [ -f "$MEMORY_DIR/session-log.md" ]; then
  echo "--- Poslednja sesija ---"
  tail -20 "$MEMORY_DIR/session-log.md"
fi
