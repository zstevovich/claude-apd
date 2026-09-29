#!/bin/bash
# APD dispatch budget (v7.1) — the count the cycle cap never counted.
#
# `max_cycles` counts `pipeline-advance` calls (workflow.md §0b says so). Runs
# measured in September 2026 dispatched 4–5 builder-class agents per advance
# and 20 same-type agents per task with three cap-raises; the fix rounds that
# cost hours live AFTER builder.done, across phase boundaries. This budget is
# per TASK (the `spec.done` window), by ROLE CLASS, counted from the `.agents`
# ledger that already exists, is wiped on spec re-advance + reset and survives
# rollback — exactly the cap semantics workflow.md documents. No new state.
#
# Sourced by: bin/core/guard-agent-reload (pre-spawn enforcement, CC-only) and
# bin/core/pipeline-advance (raise-cap dispatch, status line, wall-clock nudge).
# Needs: PIPELINE_DIR, PROJECT_DIR, APD_AGENTS_DIR (resolve-project.sh) and
# bin/lib/agent-scope.sh (_agent_def_file, _agent_is_writable).

DISPATCH_BUDGET_BUILDER_DEFAULT=12
DISPATCH_BUDGET_REVIEWER_DEFAULT=6
DISPATCH_BUDGET_ADVERSARIAL_DEFAULT=2
WALL_NUDGE_SEC_DEFAULT=5400

# _agent_file_by_name <agent_type> — the definition whose FRONTMATTER `name:`
#   is <agent_type>. CC dispatches by that name, not by the file name; a file
#   `builder-v2.md` carrying `name: backend-builder` is dispatched as
#   `backend-builder`, which `_agent_def_file` cannot find (audit 2026-09-29
#   M4b). Budget-only fallback, same identifier rule as the resolver.
_agent_file_by_name() {
  local t="$1" d f
  case "$t" in ''|.|..|*[!A-Za-z0-9_.-]*) return 1 ;; esac
  for d in "$APD_AGENTS_DIR" "$PROJECT_DIR/.claude/agents" "$PROJECT_DIR/.apd/agents"; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    for f in "$d"/*.md; do
      [ -f "$f" ] || continue
      if awk -v n="$t" 'NR == 1 && $0 ~ /^---[ \t]*$/ { fm = 1; next } fm && $0 ~ /^---[ \t]*$/ { exit } fm && $0 ~ /^name:[ \t]*/ { v = $0; sub(/^name:[ \t]*/, "", v); sub(/[ \t]+$/, "", v); if (v == n) found = 1 } END { exit found ? 0 : 1 }' "$f" 2>/dev/null; then
        printf '%s' "$f"; return 0
      fi
    done
  done
  return 1
}

# _agent_has_bash <file> — frontmatter `tools:` names Bash (or no tools line at all)
_agent_has_bash() {
  awk '
    NR == 1 && $0 ~ /^---[ \t]*$/ { fm = 1; next }
    fm && $0 ~ /^---[ \t]*$/ { exit }
    !fm { next }
    tolower($0) ~ /^tools:/ { seen = 1; if (tolower($0) ~ /bash|all tools|\*/) b = 1 }
    END { exit (seen && !b) ? 1 : 0 }
  ' "$1" 2>/dev/null
}

# _dispatch_class_live <agent_type> — classification from the agent file AS IT
#   IS NOW. Used only to build the snapshot below and for an agent that did not
#   exist when the spec was signed.
_dispatch_class_live() {
  local t="$1" f=""
  f=$(_agent_def_file "$t" 2>/dev/null) || f=""
  [ -n "$f" ] || f=$(_agent_file_by_name "$t" 2>/dev/null) || f=""
  [ -n "$f" ] || { printf 'none'; return 0; }
  case "$t" in
    *adversarial*) printf 'adversarial'; return 0 ;;
    supervisor)    printf 'supervisor'; return 0 ;;
    *review*)      printf 'reviewer'; return 0 ;;
  esac
  if _agent_is_writable "$f" || _agent_has_bash "$f"; then printf 'builder'; else printf 'none'; fi
}

# _dispatch_class_snapshot_write — `type|class` for every project agent, taken
#   at the SPEC advance into `.apd/pipeline/.dispatch-classes` (pipeline state:
#   no bash write, not on the Write/Edit allowlist). The orchestrator may edit
#   `.claude/agents/*.md` at any time and CC keeps the definition it cached at
#   session start, so a mid-task rewrite to `tools: Read, Grep` turned a
#   builder into `none` for the count while the running agent kept writing
#   (gates delta audit N1, reproduced: 13th dispatch rc=2 → edit → rc=0 → 33rd
#   rc=0, restore, no trace). The snapshot is what the budget counts against.
_dispatch_class_snapshot_write() {
  local d f t n out="$PIPELINE_DIR/.dispatch-classes"
  : > "$out"
  for d in "$APD_AGENTS_DIR" "$PROJECT_DIR/.claude/agents" "$PROJECT_DIR/.apd/agents"; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    for f in "$d"/*.md; do
      [ -f "$f" ] || continue
      t="${f##*/}"; t="${t%.md}"
      case "$t" in *[!A-Za-z0-9_.-]*) continue ;; esac
      grep -q "^$t|" "$out" 2>/dev/null || printf '%s|%s\n' "$t" "$(_dispatch_class_live "$t")" >> "$out"
      n=$(awk 'NR == 1 && $0 ~ /^---[ \t]*$/ { fm = 1; next } fm && $0 ~ /^---[ \t]*$/ { exit } fm && $0 ~ /^name:[ \t]*/ { v = $0; sub(/^name:[ \t]*/, "", v); sub(/[ \t]+$/, "", v); print v; exit }' "$f" 2>/dev/null)
      if [ -n "$n" ] && [ "$n" != "$t" ]; then
        case "$n" in *[!A-Za-z0-9_.-]*) ;; *) grep -q "^$n|" "$out" 2>/dev/null || printf '%s|%s\n' "$n" "$(_dispatch_class_live "$n")" >> "$out" ;; esac
      fi
    done
  done
}

# _dispatch_class <agent_type> → builder | reviewer | adversarial | supervisor | none
#   From the spec-time snapshot when the type is in it; live only for an agent
#   created after the spec was signed. Only PROJECT-defined agents are
#   classified; anything APD does not own (Explore, general-purpose, fork,
#   plugin agents) is `none` — it cannot advance a phase, so it does not spend
#   the budget. A project agent that can modify files through Write/Edit OR
#   through Bash is a builder (audit M4a).
_dispatch_class() {
  local t="$1" f="" snap live
  if [ -s "$PIPELINE_DIR/.dispatch-classes" ]; then
    snap=$(grep -F -- "$t|" "$PIPELINE_DIR/.dispatch-classes" 2>/dev/null | awk -F'|' -v k="$t" '$1 == k { print $2; exit }')
    if [ -n "$snap" ]; then printf '%s' "$snap"; return 0; fi
    # unknown at spec time (created or renamed after it): classify live ONCE
    # and freeze — otherwise a later downgrade re-reads it (delta2 audit R2)
    live=$(_dispatch_class_live "$t")
    case "$t" in *[!A-Za-z0-9_.-]*) ;; *) printf '%s|%s\n' "$t" "$live" >> "$PIPELINE_DIR/.dispatch-classes" 2>/dev/null ;; esac
    printf '%s' "$live"; return 0
  fi
  if [ -f "$PIPELINE_DIR/spec.done" ]; then
    # spec signed but no snapshot (deleted, truncated, or a spec signed before
    # v7.1): fail CLOSED for the count — every project-defined agent that is
    # not a review role is a builder (delta2 audit R1: with the file gone the
    # live-read trick worked again)
    DISPATCH_SNAPSHOT_MISSING=1
    f=$(_agent_def_file "$t" 2>/dev/null) || f=""
    [ -n "$f" ] || f=$(_agent_file_by_name "$t" 2>/dev/null) || f=""
    [ -n "$f" ] || { printf 'none'; return 0; }
    case "$t" in *adversarial*) printf 'adversarial' ;; supervisor) printf 'supervisor' ;; *review*) printf 'reviewer' ;; *) printf 'builder' ;; esac
    return 0
  fi
  f=$(_agent_def_file "$t" 2>/dev/null) || f=""
  [ -n "$f" ] || f=$(_agent_file_by_name "$t" 2>/dev/null) || f=""
  [ -n "$f" ] || { printf 'none'; return 0; }
  case "$t" in
    *adversarial*) printf 'adversarial'; return 0 ;;
    supervisor)    printf 'supervisor'; return 0 ;;
    *review*)      printf 'reviewer'; return 0 ;;
  esac
  if _agent_is_writable "$f" || _agent_has_bash "$f"; then printf 'builder'; else printf 'none'; fi
}

# _spec_card_is_signed → 0 when spec-card.md still hashes to `.spec-hash`
#   (the frozen, signed spec). The orchestrator may WRITE spec-card.md at any
#   time (it is on the pipeline-state allowlist) and the verifier only checks
#   the hash at the end — so a `dispatch_budget:` line appended mid-run would
#   have lifted the budget with no trace (audit 2026-09-29 C1, reproduced:
#   13th dispatch rc=2 → append `builder=unlimited` → rc=0 → restore → hash
#   matches again). A spec-card value counts only while the card is the one
#   that was signed.
_spec_card_is_signed() {
  local cur sig
  [ -f "$PIPELINE_DIR/spec-card.md" ] && [ -f "$PIPELINE_DIR/.spec-hash" ] || return 1
  cur=$(shasum -a 256 "$PIPELINE_DIR/spec-card.md" 2>/dev/null | cut -d' ' -f1)
  sig=$(tr -d '[:space:]' < "$PIPELINE_DIR/.spec-hash" 2>/dev/null)
  [ -n "$cur" ] && [ "$cur" = "$sig" ]
}

# _dispatch_budget <class> → N | unlimited
#   Default per class → spec-card `dispatch_budget: builder=N reviewer=M
#   adversarial=K` (spec-time, may set any value; honoured only while the card
#   is still the SIGNED one) → `.dispatch-cap-override` (`raise-cap dispatch`,
#   raises only, last line per class wins).
_dispatch_budget() {
  local c="$1" v line ov
  case "$c" in
    builder)     v="$DISPATCH_BUDGET_BUILDER_DEFAULT" ;;
    reviewer)    v="$DISPATCH_BUDGET_REVIEWER_DEFAULT" ;;
    adversarial) v="$DISPATCH_BUDGET_ADVERSARIAL_DEFAULT" ;;
    *) printf 'unlimited'; return 0 ;;
  esac
  if [ -f "$PIPELINE_DIR/spec-card.md" ] && grep -qiE '^[-*_[:blank:]]*dispatch_budget[-*_[:blank:]]*:' "$PIPELINE_DIR/spec-card.md" 2>/dev/null; then
    if _spec_card_is_signed; then
      line=$(grep -iE '^[-*_[:blank:]]*dispatch_budget[-*_[:blank:]]*:' "$PIPELINE_DIR/spec-card.md" 2>/dev/null | head -1)
    else
      line=""   # edited after signing: ignored (the guard logs it)
    fi
    if [ -n "$line" ]; then
      ov=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]' | grep -oE "$c=([0-9]+|unlimited)" | head -1 | cut -d= -f2)
      [ -n "$ov" ] && v="$ov"
    fi
  fi
  if [ -f "$PIPELINE_DIR/.dispatch-cap-override" ]; then
    ov=$(grep -E "^$c=" "$PIPELINE_DIR/.dispatch-cap-override" 2>/dev/null | tail -1 | cut -d= -f2 | tr -d '[:space:]')
    if [ "$ov" = "unlimited" ]; then v="unlimited"
    elif [ "$v" != "unlimited" ] && printf '%s' "$ov" | grep -qE '^[0-9]+$' && [ "$ov" -gt "$v" ] 2>/dev/null; then v="$ov"; fi
  fi
  printf '%s' "$v"
}

# _dispatch_count <class> → number of `start` events of that class since spec.done
#   The `.agents` timestamp and spec.done column 2 share one human format, so
#   the lexical compare is chronological (v6.6.1 idiom, same as the builder gate).
_dispatch_count() {
  local c="$1" spec_h="" n=0 ts ev typ id cls
  [ -f "$PIPELINE_DIR/spec.done" ] || { printf '0'; return 0; }
  [ -f "$PIPELINE_DIR/.agents" ] || { printf '0'; return 0; }
  spec_h=$(head -1 "$PIPELINE_DIR/spec.done" | cut -d'|' -f2)
  local seen_t=() seen_c=() i found
  while IFS='|' read -r ts ev typ id; do
    [ "$ev" = "start" ] || continue
    [ -n "$spec_h" ] && [ "$ts" \< "$spec_h" ] && continue
    found=""
    for ((i = 0; i < ${#seen_t[@]}; i++)); do
      [ "${seen_t[$i]}" = "$typ" ] && { found="${seen_c[$i]}"; break; }
    done
    if [ -z "$found" ]; then found=$(_dispatch_class "$typ"); seen_t+=("$typ"); seen_c+=("$found"); fi
    [ "$found" = "$c" ] && n=$((n + 1))
  done < "$PIPELINE_DIR/.agents"
  printf '%s' "$n"
}

# _dispatch_summary → "builder 7/12 · reviewer 3/6 · adversarial 1/2"
_dispatch_summary() {
  local c out=""
  for c in builder reviewer adversarial; do
    out="${out:+$out · }$c $(_dispatch_count "$c")/$(_dispatch_budget "$c")"
  done
  printf '%s' "$out"
}

# _wall_nudge_sec → threshold in seconds (APD_WALL_NUDGE_SEC overrides; a
# non-number or 0 falls back to the default — the value is the operator's)
_wall_nudge_sec() {
  local t="${APD_WALL_NUDGE_SEC:-$WALL_NUDGE_SEC_DEFAULT}"
  case "$t" in ''|*[!0-9]*|0) t="$WALL_NUDGE_SEC_DEFAULT" ;; esac
  printf '%s' "$t"
}

# _human_to_epoch "<YYYY-mm-dd HH:MM:SS>" → epoch (macOS or GNU date); empty on failure
_human_to_epoch() {
  local e=""
  e=$(date -j -f "%Y-%m-%d %H:%M:%S" "$1" +%s 2>/dev/null) || e=""
  [ -n "$e" ] || e=$(date -d "$1" +%s 2>/dev/null) || e=""
  case "$e" in *[!0-9]*) e="" ;; esac
  printf '%s' "$e"
}

# _wall_elapsed → seconds since spec.done (0 when no active pipeline)
_wall_elapsed() {
  local s
  [ -f "$PIPELINE_DIR/spec.done" ] || { printf '0'; return 0; }
  s=$(head -1 "$PIPELINE_DIR/spec.done" | cut -d'|' -f1)
  case "$s" in ''|*[!0-9]*) printf '0'; return 0 ;; esac
  printf '%s' "$(( $(date +%s) - s ))"
}

# _wall_nudge_text → the advisory line(s) when over the threshold, nothing otherwise
_wall_nudge_text() {
  local el thr h m
  el=$(_wall_elapsed); thr=$(_wall_nudge_sec)
  [ "$el" -gt "$thr" ] 2>/dev/null || return 1
  h=$((el / 3600)); m=$(((el % 3600) / 60))
  printf '  NOTE: this task has been open for %dh %02dm (dispatches: %s).\n' "$h" "$m" "$(_dispatch_summary)"
  printf '        Long runs are where scope grows in flight. If a finding is out of scope,\n'
  printf '        spin it off (apd pipeline spinoff-finding) or decompose; do not keep fixing forward.\n'
  return 0
}
