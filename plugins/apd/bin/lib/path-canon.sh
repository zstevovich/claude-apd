#!/bin/bash
# APD shared path canonicaliser (v7.1) — one physical-path normaliser for BOTH
# scope guards. guard-scope (Write/Edit) carried this inline since v6.37.1 /
# v7.0.4; guard-bash-scope compared raw command tokens against relative scope
# roots by string prefix, so an ABSOLUTE path inside the agent's own scope, a
# path relative to a `cd`, and a symlinked project root all read as
# "outside". The bash guard now resolves every write target through the same
# function the file guard uses, so the two channels agree on what "in scope"
# means (measured 2026-09: 166 of 170 September bash-guard blocks on one
# project hit subagents, most of them on paths that WERE in scope).
#
# Sourced by: bin/core/guard-scope, bin/core/guard-bash-scope.
# Pure bash 3.2 + realpath/pwd — no python, no GNU-only flags.

# _canon_abs <path> [<base-dir>]
#   Prints the PHYSICAL absolute form of <path>. A relative <path> is taken
#   against <base-dir> (default: $PWD). Works for paths that do not exist yet:
#   the deepest EXISTING ancestor is resolved with realpath / pwd -P and the
#   missing tail is re-attached verbatim (v7.0.4 — the first file in a new
#   directory is exactly this case). A `..` that survives (it sits in the
#   non-existent tail) is left in place for the caller's traversal check.
#   Prints nothing only when <path> is empty.
_canon_abs() {
  local p="$1" base="${2:-$PWD}" abs="" anc="" tail=""
  [ -n "$p" ] || return 0
  case "$p" in
    /*) ;;
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
    *) p="$base/$p" ;;
  esac
  if command -v realpath >/dev/null 2>&1; then
    abs=$(realpath "$p" 2>/dev/null || true)
  fi
  if [ -z "$abs" ]; then
    if [ -d "$p" ]; then
      abs="$(cd "$p" 2>/dev/null && pwd -P)"
    else
      anc=$(dirname "$p"); tail=$(basename "$p")
      while [ ! -d "$anc" ] && [ "$anc" != "/" ] && [ "$anc" != "." ]; do
        tail="$(basename "$anc")/$tail"
        anc=$(dirname "$anc")
      done
      if [ -d "$anc" ]; then
        abs="$(cd "$anc" 2>/dev/null && pwd -P)/$tail"
      fi
    fi
  fi
  [ -z "$abs" ] && abs="$p"
  printf '%s\n' "$abs"
}

# _proj_canon
#   Prints the physical form of $PROJECT_DIR (macOS /tmp → /private/tmp,
#   user-symlinked roots). Prefix-stripping a physical target against a
#   logical root false-blocked in-project files as "outside the project"
#   (v6.37.1); every scope comparison must use this form on both sides.
_proj_canon() {
  local c=""
  if command -v realpath >/dev/null 2>&1; then
    c=$(realpath "$PROJECT_DIR" 2>/dev/null || true)
  fi
  [ -z "$c" ] && c="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)"
  [ -z "$c" ] && c="$PROJECT_DIR"
  printf '%s\n' "$c"
}

# _has_traversal <path> — 0 when a `..` segment survived canonicalisation.
_has_traversal() {
  case "/$1/" in
    */../*|*/..|../*) return 0 ;;
  esac
  return 1
}
