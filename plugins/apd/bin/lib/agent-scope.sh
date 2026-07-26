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

# _agent_is_writable <file> — can this agent modify files at all?
#
# `readonly: true` is NOT the discriminator, and assuming it was is what left a
# hole on the Bash channel. APD's own review roles (code-reviewer, adversarial,
# supervisor) do not carry that flag — they are bounded by OMITTING Write/Edit
# from `tools:`. So "not readonly" describes every agent APD ships, and using it
# to decide whether an empty scope should fail closed would have blocked
# reviewers from `… > /tmp/out` while still not bounding anything.
#
# The honest question is whether the agent can write, and CC answers it in
# `tools:`. An agent with NO `tools:` line inherits every tool, so absence means
# writable — the fail-safe reading, since the consequence of guessing wrong is
# an unbounded shell.
_agent_is_writable() {
  awk '
    NR == 1 && $0 ~ /^---[ \t]*$/ { fm = 1; next }
    fm && $0 ~ /^---[ \t]*$/ { exit }
    !fm { next }
    tolower($0) ~ /^tools:/ {
      seen = 1
      if (tolower($0) ~ /write|edit|all tools|\*/) w = 1
    }
    END { exit (seen && !w) ? 1 : 0 }
  ' "$1" 2>/dev/null
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
#
# READS THE FRONTMATTER ONLY, and reads every form a project actually uses.
# An audit found both halves of that sentence were false:
#
#   * `^scope:` was grepped over the WHOLE file, so a prose line in the body
#     ("scope: src/ secrets/") silently widened an agent past what its hook
#     command declared — a fail-OPEN, and the body of an agent `.md` is a file
#     the orchestrator is explicitly allowed to write.
#   * Only two declaration forms were understood. Every unread form resolves to
#     nothing, and nothing means a total write ban for that agent (guard-scope
#     fails closed). So a QUOTED hook argument, a YAML block list, or a legacy
#     `scripts/guard-scope.sh` path did not loosen enforcement — it froze the
#     agent mid-pipeline on its first write, on projects that had been working.
#
# Forms handled: `scope: [a, b]`, `scope: a b`, a `scope:` block list, and the
# hook command with quoted OR unquoted arguments, with or without a `.sh` suffix.
# Quoted arguments are kept whole, so a path containing a space is expressible —
# stripping the quotes first split it into two wrong paths AND let an undeclared
# sibling through.
_agent_scope_paths() {
  local f="$1" tok
  awk '
    # --- frontmatter only ------------------------------------------------
    NR == 1 && $0 ~ /^---[ \t]*$/ { fm = 1; next }
    fm && $0 ~ /^---[ \t]*$/ { exit }
    !fm { next }

    # --- `scope:` block list ---------------------------------------------
    inlist {
      if ($0 ~ /^[ \t]*-[ \t]*/) {
        s = $0; sub(/^[ \t]*-[ \t]*/, "", s); print s; next
      }
      inlist = 0
    }
    $0 ~ /^scope:[ \t]*$/ { inlist = 1; found = 1; next }

    # --- `scope:` inline --------------------------------------------------
    $0 ~ /^scope:[ \t]*[^ \t]/ {
      s = $0; sub(/^scope:[ \t]*/, "", s)
      gsub(/[][,]/, " ", s)
      n = split(s, a, /[ \t]+/)
      for (i = 1; i <= n; i++) if (a[i] != "") print a[i]
      found = 1; next
    }

    # --- the hook command -------------------------------------------------
    # Only the file-scope guard: `guard-bash-scope` is a different token and
    # must not match. Everything after it is split respecting quotes, so a
    # quoted path keeps its spaces.
    !found && /guard-scope/ && !/guard-bash-scope/ {
      p = index($0, "guard-scope")
      s = substr($0, p + length("guard-scope"))
      sub(/^\.sh/, "", s)                       # legacy `guard-scope.sh`
      cur = ""; q = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q != "") { if (c == q) { q = "" } else { cur = cur c }; continue }
        if (c == "\"" || c == "\047") { q = c; continue }
        if (c == " " || c == "\t") { if (cur != "") { print cur; cur = "" }; continue }
        cur = cur c
      }
      if (cur != "") print cur
    }
  ' "$f" 2>/dev/null | while IFS= read -r tok; do
    # Drop flags, unfilled placeholders, and anything carrying shell syntax —
    # the hook command is a command line, and only its path arguments are a
    # declaration. A token we cannot read as a path is not a scope widening.
    case "$tok" in
      ''|-*|*'{{'*|*'$'*|*'&'*|*';'*|*'|'*|*'`'*) continue ;;
    esac
    printf '%s\n' "$tok"
  done
}
