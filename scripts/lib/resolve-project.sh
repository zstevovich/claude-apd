#!/bin/bash
# APD — Project & Plugin path resolution
# Source this at the top of every APD script:
#   source "$(dirname "$0")/lib/resolve-project.sh"
#
# Provides:
#   PROJECT_DIR   — user's project root (where CLAUDE.md lives)
#   APD_PLUGIN_ROOT — plugin install directory (where scripts/ lives)
#   CLAUDE_DIR    — $PROJECT_DIR/.claude
#   MEMORY_DIR    — $CLAUDE_DIR/memory
#   PIPELINE_DIR  — $CLAUDE_DIR/.pipeline
#   SCRIPT_DIR    — $APD_PLUGIN_ROOT/scripts

# --- Plugin root ---
# ${CLAUDE_PLUGIN_ROOT} is set by Claude Code when executing plugin hooks
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    APD_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
    # Fallback: resolve from script location (scripts/lib/ → repo root)
    APD_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

# --- Project root ---
# Claude Code hook commands execute with cwd = project directory
# Priority: explicit env var → pwd detection → upward walk
if [ -n "${APD_PROJECT_DIR:-}" ]; then
    PROJECT_DIR="$APD_PROJECT_DIR"
elif [ -f "$(pwd)/CLAUDE.md" ] || [ -d "$(pwd)/.claude" ]; then
    PROJECT_DIR="$(pwd)"
else
    # Walk upward looking for project markers
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
MEMORY_DIR="$CLAUDE_DIR/memory"
PIPELINE_DIR="$CLAUDE_DIR/.pipeline"
SCRIPT_DIR="$APD_PLUGIN_ROOT/scripts"
