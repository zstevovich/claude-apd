#!/bin/bash
# APD — Project & Plugin path resolution
# Source this at the top of every APD script:
#   source "$(dirname "$0")/lib/resolve-project.sh"
#
# Provides:
#   PROJECT_DIR   — user's project root (where CLAUDE.md lives)
#   APD_PLUGIN_ROOT — plugin install directory (where bin/ lives)
#   CLAUDE_DIR    — $PROJECT_DIR/.claude
#   MEMORY_DIR    — $CLAUDE_DIR/memory
#   PIPELINE_DIR  — $PROJECT_DIR/.apd/pipeline
#   SCRIPT_DIR    — $APD_PLUGIN_ROOT/scripts

# --- APD version (runtime-neutral read) ---
# Primary source: VERSION at plugin root. Fallback: CC plugin manifest.
# Kept here so any sourced script can echo $APD_VERSION without duplicating
# the grep/sed dance.
_read_apd_version() {
    local root="$1"
    if [ -f "$root/VERSION" ]; then
        local v
        v="$(tr -d '[:space:]' < "$root/VERSION")"
        if [ -n "$v" ]; then
            printf '%s' "$v"
            return 0
        fi
    fi
    if [ -f "$root/.claude-plugin/plugin.json" ]; then
        grep '"version"' "$root/.claude-plugin/plugin.json" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
    fi
}

# --- Plugin root ---
# ${CLAUDE_PLUGIN_ROOT} is set by Claude Code when executing plugin hooks
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    APD_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
    # Fallback: resolve from script location (bin/lib/ → repo root)
    APD_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# --- APD version ---
APD_VERSION="$(_read_apd_version "$APD_PLUGIN_ROOT")"
APD_VERSION="${APD_VERSION:-unknown}"

# --- Project root ---
# Claude Code hook commands execute with cwd = project directory
# Priority: explicit env var → git toplevel → pwd detection → upward walk
if [ -n "${APD_PROJECT_DIR:-}" ]; then
    PROJECT_DIR="$APD_PROJECT_DIR"
elif _git_root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -d "$_git_root/.claude" ]; then
    # Git toplevel is authoritative — works from any subdirectory or worktree
    PROJECT_DIR="$_git_root"
elif [ -f "$(pwd)/CLAUDE.md" ] || [ -d "$(pwd)/.claude" ]; then
    PROJECT_DIR="$(pwd)"
else
    # Walk upward looking for project markers (fallback for non-git dirs)
    _apd_dir="$(pwd)"
    PROJECT_DIR=""
    while [ "$_apd_dir" != "/" ]; do
        if [ -f "$_apd_dir/CLAUDE.md" ] || [ -d "$_apd_dir/.claude" ]; then
            PROJECT_DIR="$_apd_dir"
            break
        fi
        _apd_dir="$(dirname "$_apd_dir")"
    done
    # Last resort: use pwd
    PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
    unset _apd_dir
fi

# --- Derived paths ---
CLAUDE_DIR="$PROJECT_DIR/.claude"
PIPELINE_DIR="$PROJECT_DIR/.apd/pipeline"
SCRIPT_DIR="$APD_PLUGIN_ROOT/bin/core"

# --- Runtime-neutral APD directories (v5.0) ---
# CC-native projects keep content under .claude/<sub> (CC expects it there for
# its Task tool and @-imports). Pure-Codex projects place content under
# .apd/<sub>. Resolver picks the CC-native path whenever .claude/ exists so
# hybrid projects keep working; otherwise it falls back to .apd/<sub>.
_pick_apd_dir() {
    local sub="$1" cc_sub="$2"
    if [ -d "$CLAUDE_DIR/$cc_sub" ]; then
        printf '%s' "$CLAUDE_DIR/$cc_sub"
    elif [ -d "$PROJECT_DIR/.apd/$sub" ]; then
        printf '%s' "$PROJECT_DIR/.apd/$sub"
    elif [ -d "$CLAUDE_DIR" ]; then
        # CC project but sub-dir not created yet — stay CC-native for writes
        printf '%s' "$CLAUDE_DIR/$cc_sub"
    else
        # No CC project — default to runtime-neutral
        printf '%s' "$PROJECT_DIR/.apd/$sub"
    fi
}

APD_AGENTS_DIR="$(_pick_apd_dir agents agents)"
APD_MEMORY_DIR="$(_pick_apd_dir memory memory)"
APD_RULES_DIR="$(_pick_apd_dir rules rules)"

# Backward-compat alias — some older code still references MEMORY_DIR
MEMORY_DIR="$APD_MEMORY_DIR"

# Project-level version tag (informational copy of APD version)
if [ -f "$PROJECT_DIR/.apd/.apd-version" ]; then
    APD_VERSION_FILE_PROJECT="$PROJECT_DIR/.apd/.apd-version"
else
    APD_VERSION_FILE_PROJECT="$CLAUDE_DIR/.apd-version"
fi

# --- Activation marker ---
# APD activates on presence of a config file. Two valid locations:
#   1. $PROJECT_DIR/.apd/config       — runtime-neutral (Codex & hybrid projects)
#   2. $CLAUDE_DIR/.apd-config        — legacy CC-native path
# Pure-Codex projects never need to create .claude/; the neutral path is
# checked first so new installs can stay out of the Claude namespace.
if [ -f "$PROJECT_DIR/.apd/config" ]; then
    APD_CONFIG_FILE="$PROJECT_DIR/.apd/config"
    APD_ACTIVE=true
elif [ -f "$CLAUDE_DIR/.apd-config" ]; then
    APD_CONFIG_FILE="$CLAUDE_DIR/.apd-config"
    APD_ACTIVE=true
else
    APD_CONFIG_FILE=""
    APD_ACTIVE=false
fi

# --- Shortcut path for user-facing messages ---
# Prefer the Codex-namespaced shortcut when the project has .codex/, so
# Codex users see `.codex/bin/apd ...` in help and error messages. Fall
# back to the CC shortcut, then the absolute plugin entry point.
if [ -f "$PROJECT_DIR/.codex/bin/apd" ]; then
    APD_SHORTCUT="$PROJECT_DIR/.codex/bin/apd"
elif [ -f "$CLAUDE_DIR/bin/apd" ]; then
    APD_SHORTCUT="$CLAUDE_DIR/bin/apd"
else
    APD_SHORTCUT="$APD_PLUGIN_ROOT/bin/apd"
fi

# Display-friendly path: relative-from-project when shortcut lives inside
# the project, absolute otherwise. Used in help/error text.
case "$APD_SHORTCUT" in
    "$PROJECT_DIR/"*)
        APD_SHORTCUT_DISPLAY="${APD_SHORTCUT#"$PROJECT_DIR"/}"
        ;;
    *)
        APD_SHORTCUT_DISPLAY="$APD_SHORTCUT"
        ;;
esac
