#!/bin/bash
# APD agent-scope resolution (CC side)
#
# WHY THIS EXISTS
# CC agents declare their writable scope inside their frontmatter PreToolUse
# hook command (`… guard-scope src/ tests/`). That block was assumed to be both
# the DECLARATION and the ENFORCEMENT site. It is only the declaration:
# per-agent frontmatter hooks DO NOT FIRE (measured on CC 2.1.220 — a logging
# hook wired there never ran, in either schema form, while the identical hook in
# settings.json fired and blocked). So `guard-scope` and `guard-secrets`, wired
# nowhere else, never ran on CC at all.
#
# The fix is to enforce session-level from hooks/hooks.json and identify the
# caller from the hook payload, which carries `agent_type` (the agent's name)
# for every tool call made inside a subagent and omits it for the orchestrator's
# own calls. This file turns that name into the scope the agent declared.
#
# It is a bash mirror of the Codex MCP resolver (`_scope_from_hook_command` +
# `apd_guard_write`): same registry, same YAML-then-hook-command order, same
# fail-closed rule. Scope comes from the REGISTRY, never from caller arguments —
# an agent must not be able to widen its own scope.

# _agent_def_file <agent_type>
# Prints the path to the agent definition, or nothing when there is none.
_agent_def_file() {
  local t="$1"
  # A bare identifier only — no separators, no parent refs. Without this a
  # crafted agent_type could point the resolver at an attacker-placed file.
  case "$t" in
    ''|.|..) return 1 ;;
    *[!A-Za-z0-9_.-]*) return 1 ;;
  esac
  local d
  for d in "$APD_AGENTS_DIR" "$PROJECT_DIR/.claude/agents" "$PROJECT_DIR/.apd/agents"; do
    [ -n "$d" ] || continue
    [ -f "$d/$t.md" ] && { printf '%s' "$d/$t.md"; return 0; }
  done
  return 1
}

# _agent_is_readonly <file> — frontmatter `readonly: true`
_agent_is_readonly() {
  grep -qE '^readonly:[[:space:]]*true[[:space:]]*$' "$1" 2>/dev/null
}

# _agent_scope_paths <file>
# Prints the declared scope, one path per line.
# YAML `scope:` first (Codex-native form), then the CC hook command. Unfilled
# `{{PLACEHOLDER}}` tokens and flags are dropped — a template that was never
# customised declares NOTHING, which the caller must treat as "no scope", not
# as "scope is the literal string {{SCOPE_PATHS}}".
#
# `|| true` on every grep is load-bearing, not defensive noise: these callers
# are shims running under `set -e`, and a grep that simply finds nothing exits
# 1. Without it the function aborts at the FIRST probe — a CC agent has no YAML
# `scope:`, so the hook-command branch below was never reached, the scope came
# back empty, and the fail-closed rule blocked EVERY write by EVERY agent.
# Measured, not theorised: the resolver returned `src/` when tested by hand
# (no `set -e`) and nothing at all through the shim.
_agent_scope_paths() {
  local f="$1" line toks tok

  # YAML inline list: `scope: [src/, tests/]` or plain `scope: src/ tests/`
  line=$(grep -m1 -E '^scope:' "$f" 2>/dev/null || true)
  if [ -n "$line" ]; then
    toks="${line#scope:}"
    toks="${toks//[/ }"; toks="${toks//]/ }"; toks="${toks//,/ }"
    toks="${toks//\"/ }"; toks="${toks//\'/ }"
    for tok in $toks; do
      case "$tok" in -*|*'{{'*) continue ;; esac
      printf '%s\n' "$tok"
    done
    return 0
  fi

  # CC form: the paths trailing the `guard-scope` token in the hook command.
  # `guard-bash-scope` is a different token and must not match this anchor,
  # hence the leading `/` boundary from the adapter path.
  line=$(grep -m1 -oE '/guard-scope([[:space:]]+[^[:space:]"'"'"']+)+' "$f" 2>/dev/null || true)
  [ -n "$line" ] || return 0
  line="${line#/guard-scope}"
  for tok in $line; do
    case "$tok" in -*|*'{{'*) continue ;; esac
    printf '%s\n' "$tok"
  done
}
