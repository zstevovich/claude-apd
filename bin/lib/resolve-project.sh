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

# --- Plugin root ---
# ${CLAUDE_PLUGIN_ROOT} is set by Claude Code when executing plugin hooks
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    APD_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
else
    # Fallback: resolve from script location (bin/lib/ → repo root)
    APD_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

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
MEMORY_DIR="$CLAUDE_DIR/memory"
PIPELINE_DIR="$PROJECT_DIR/.apd/pipeline"
SCRIPT_DIR="$APD_PLUGIN_ROOT/bin/core"

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
