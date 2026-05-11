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
# ${CLAUDE_PLUGIN_ROOT} is set by Claude Code when executing plugin hooks.
# In v6.0+ everything APD-runtime moved into <repo>/plugins/apd/, so the
# CC plugin root (= repo root in cache) is one level above APD_PLUGIN_ROOT.
# Resolution order:
#   1. CLAUDE_PLUGIN_ROOT/plugins/apd    — v6.0+ CC hook context
#   2. CLAUDE_PLUGIN_ROOT                 — pre-v6.0 cache (still has bin/ at root)
#   3. Walk up from this script           — direct invocation / Codex / tests
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    if [ -d "$CLAUDE_PLUGIN_ROOT/plugins/apd/bin" ]; then
        APD_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT/plugins/apd"
    else
        APD_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
    fi
else
    # Fallback: resolve from script location (bin/lib/ → plugin root)
    APD_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# --- APD version ---
APD_VERSION="$(_read_apd_version "$APD_PLUGIN_ROOT")"
APD_VERSION="${APD_VERSION:-unknown}"

# --- Project root ---
# Claude Code / Codex hook commands execute with cwd = project directory
# Priority: explicit env var → git toplevel → pwd detection → upward walk
#
# Project markers (any one counts): .claude/, .codex/, CLAUDE.md, AGENTS.md.
# .codex/ and AGENTS.md are recognised so pure-Codex projects resolve without
# CC-native files. $HOME is explicitly excluded during upward walk because the
# user's global Codex config lives at ~/.codex/ and must not be mistaken for a
# project root.
_apd_has_marker() {
    [ -f "$1/CLAUDE.md" ] || [ -d "$1/.claude" ] || [ -d "$1/.codex" ] || [ -f "$1/AGENTS.md" ]
}

if [ -n "${APD_PROJECT_DIR:-}" ]; then
    PROJECT_DIR="$APD_PROJECT_DIR"
elif _git_root=$(git rev-parse --show-toplevel 2>/dev/null) && _apd_has_marker "$_git_root"; then
    # Git toplevel is authoritative — works from any subdirectory or worktree
    PROJECT_DIR="$_git_root"
elif _apd_has_marker "$(pwd)" && [ "$(pwd)" != "$HOME" ]; then
    PROJECT_DIR="$(pwd)"
else
    # Walk upward looking for project markers (fallback for non-git dirs)
    _apd_dir="$(pwd)"
    PROJECT_DIR=""
    while [ "$_apd_dir" != "/" ] && [ "$_apd_dir" != "$HOME" ]; do
        if _apd_has_marker "$_apd_dir"; then
            PROJECT_DIR="$_apd_dir"
            break
        fi
        _apd_dir="$(dirname "$_apd_dir")"
    done
    # Last resort: use pwd (but never $HOME)
    if [ -z "$PROJECT_DIR" ]; then
        if [ "$(pwd)" != "$HOME" ]; then
            PROJECT_DIR="$(pwd)"
        else
            PROJECT_DIR="$HOME"  # fall back to home only as last-resort, APD_ACTIVE guard will disable
        fi
    fi
    unset _apd_dir
fi
unset -f _apd_has_marker 2>/dev/null || true

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

# --- Framework self-detection (v6.5) ---
# When the resolved PROJECT_DIR is the APD framework source repo itself, we
# auto-disable enforcement so guards / auto-init don't try to scaffold APD
# onto its own source. Skills and MCP tools still load — the user gets the
# `/apd-tdd`, `/apd-brainstorm`, etc. slash commands and MCP surface in
# Codex without any pipeline / hook side effects. Power users who want to
# dogfood APD on the framework itself set APD_FRAMEWORK_DEV_MODE=force-enable.
APD_FRAMEWORK_SELF=false
if [ -f "$PROJECT_DIR/plugins/apd/VERSION" ] \
   && [ -f "$PROJECT_DIR/.claude-plugin/plugin.json" ] \
   && grep -q '"name"[[:space:]]*:[[:space:]]*"claude-apd"' "$PROJECT_DIR/.claude-plugin/plugin.json" 2>/dev/null; then
    APD_FRAMEWORK_SELF=true
fi

# --- Activation marker ---
# APD activates on presence of a config file. Two valid locations:
#   1. $PROJECT_DIR/.apd/config       — runtime-neutral (Codex & hybrid projects)
#   2. $CLAUDE_DIR/.apd-config        — legacy CC-native path
# Pure-Codex projects never need to create .claude/; the neutral path is
# checked first so new installs can stay out of the Claude namespace.
# Framework-self always wins: APD_ACTIVE=false even if a config file exists,
# unless the user explicitly opts in via APD_FRAMEWORK_DEV_MODE=force-enable.
if [ "$APD_FRAMEWORK_SELF" = "true" ] && [ "${APD_FRAMEWORK_DEV_MODE:-}" != "force-enable" ]; then
    APD_CONFIG_FILE=""
    APD_ACTIVE=false
elif [ -f "$PROJECT_DIR/.apd/config" ]; then
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
# Pick the shortcut that matches the active runtime, so user-facing messages
# (pipeline errors, doctor hints, etc.) render the path the user actually
# types in their shell. Priority:
#   1. If APD_RUNTIME=codex and .codex/bin/apd exists → Codex shortcut
#   2. Else if .claude/bin/apd exists → CC shortcut (CC's default context)
#   3. Else if .codex/bin/apd exists → Codex shortcut (pure-Codex project)
#   4. Else → absolute plugin entry (no project shortcut anywhere)
if [ "${APD_RUNTIME:-}" = "codex" ] && [ -f "$PROJECT_DIR/.codex/bin/apd" ]; then
    APD_SHORTCUT="$PROJECT_DIR/.codex/bin/apd"
elif [ -f "$CLAUDE_DIR/bin/apd" ]; then
    APD_SHORTCUT="$CLAUDE_DIR/bin/apd"
elif [ -f "$PROJECT_DIR/.codex/bin/apd" ]; then
    APD_SHORTCUT="$PROJECT_DIR/.codex/bin/apd"
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
