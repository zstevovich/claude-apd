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
_canon_abs() {  # <path> [<base-dir>] [nofollow]
  local p="$1" base="${2:-$PWD}" nofollow="${3:-}" abs="" anc="" tail="" t=""
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
  # v7.1.4 (audit I1/I2): a DANGLING symlink. BSD realpath fails on it and the
  # fallback below returned the link's own path, so a link in the scratchpad
  # pointing at an out-of-scope project file read as "scratchpad" on macOS
  # while GNU realpath resolved it on Linux — canonicalisation differed by
  # platform. Resolve one level by hand, unless the caller wants the link itself.
  if [ -z "$abs" ] && [ -z "$nofollow" ] && [ -L "$p" ]; then
    local hops=0
    while [ -L "$p" ] && [ "$hops" -lt 40 ]; do   # (audit N3) a CHAIN of links, capped like the kernel
      t=$(readlink "$p" 2>/dev/null || true); [ -n "$t" ] || break
      case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
      hops=$((hops + 1))
    done
    if command -v realpath >/dev/null 2>&1; then abs=$(realpath "$p" 2>/dev/null || true); fi
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
        abs="$(cd "$anc" 2>/dev/null && pwd -P)"
        # `/` as the deepest existing ancestor gave `//private/tmp/…` (the
        # macOS-physical scratchpad form on Linux CI, where /private does not
        # exist) and the scratchpad pattern never matched — 8 red checks on the
        # first Linux run of v7.1.0.
        abs="${abs%/}/$tail"
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

# _is_session_scratchpad <canonical-path> — 0 when the path is the session
#   scratchpad Claude Code hands each session (v7.0.5, bash guard; v7.1.4,
#   shared by guard-bash-scope, guard-scope and guard-orchestrator). The match
#   is deliberately narrow — under a `claude-<uid>` temp root AND naming a
#   `scratchpad` segment — so `/tmp/out.txt` and `/tmp/scratchpad/evil.txt`
#   stay outside it. Both the logical (/tmp) and the macOS physical
#   (/private/tmp) forms match, because callers pass the CANONICAL path.
#   v7.1.4 (audit C5/M1): a path that still carries `..` is never the
#   scratchpad (a non-existent segment keeps `..` in the tail, and
#   `…/scratchpad/../../..<project>/x.cs` matched the old glob); and the layout
#   is exact — `claude-<digits>/<project-slug>/<session>/scratchpad` — so
#   `claude-5evil` and a deeper or shallower nesting do not match.
_APD_SCRATCHPAD_RE='^(/private)?/tmp/claude-[0-9]+/[^/]+/[^/]+/scratchpad(/.*)?$'
_is_session_scratchpad() {
  _has_traversal "$1" && return 1
  [[ "$1" =~ $_APD_SCRATCHPAD_RE ]] && return 0
  return 1
}

# _is_plugin_cache <canonical-path> — 0 when the path is inside a Claude Code
#   plugin cache (`…/plugins/cache/…`): plugin files are read-only for every
#   caller. v7.1.4 — judged on the resolved target; the raw-string scan it
#   replaces refused read-only commands whenever `2>/dev/null`, a quoted `>`
#   or a quoted `rm ` appeared anywhere before a plugin path.
_is_plugin_cache() {
  case "$1" in
    */plugins/cache/*|*/plugins/cache) return 0 ;;
  esac
  return 1
}

# _has_traversal <path> — 0 when a `..` segment survived canonicalisation.
_has_traversal() {
  case "/$1/" in
    */../*|*/..|../*) return 0 ;;
  esac
  return 1
}
