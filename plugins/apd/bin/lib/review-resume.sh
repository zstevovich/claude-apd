#!/bin/bash
# APD review resume (opt-in) — a delta re-review by the SAME code reviewer.
#
# WHY THIS EXISTS
# Measured on a real project (2026-11-11, ten runs): a pipeline is 95% agent
# time, every re-review after a fix is a FRESH reviewer that re-reads the whole
# diff (22–29 min, 430–490k tokens of context rebuilt), and a run has two or
# three of them. A reviewer continued with SendMessage keeps what it read; it
# needs only what changed since it looked. Two things were missing: the exact
# "what changed since the review" (the tree is not committed mid-run), and a
# SendMessage that the guard lets through for exactly that agent.
#
# WHAT IS HERE
#   _rr_mode              off | shadow | on  (APD_REVIEW_RESUME; anything else,
#                         unset, or the Codex runtime → off = nothing changes)
#   _rr_snapshot_pending  copy the task's changed files for every reviewer-class
#                         agent that has stopped and has no snapshot of that
#                         stop yet. Called from the pre-spawn guard (PreToolUse
#                         Agent, 30 s) — the SubagentStop hook has 3 s. The
#                         copy is taken LATER than the stop, so it is only
#                         taken when it can still be what the reviewer saw:
#                         no code-writing agent has an event since the
#                         reviewer last started, or is running
#                         (_rr_tree_quiet), and a file modified at or after
#                         the stop is not copied but named (the delta
#                         then says NOT COMPARED for it, never "unchanged").
#   _rr_delta <id>        unified diff: snapshot → working tree
#   _rr_resume_check <id> the reason a resume is refused, or nothing
#   _rr_resume_record     one line per allowed resume → `.review-resumes`
#
# Only the REVIEWER class may be resumed. The adversarial reviewer and the
# supervisor are valuable because they are fresh; they are never continued.
#
# shadow: the resume is allowed and measured, but a resumed reviewer is not
# evidence for the reviewer gate — a fresh one is still required. on: it is.
#
# Needs: PIPELINE_DIR, PROJECT_DIR (resolve-project.sh), bin/lib/agent-scope.sh
# and bin/lib/dispatch-budget.sh (_dispatch_class, _dispatch_budget, _dispatch_count).

RR_MAX_RESUMES_PER_AGENT=2
RR_MAX_FILE_BYTES=1048576
RR_SNAPSHOT_MAX_SEC=10      # copying stops here; the files left are named as not copied

command -v _file_mtime >/dev/null 2>&1 || source "${BASH_SOURCE[0]%/*}/portable.sh"

_rr_mode() {
  [ "${APD_RUNTIME:-}" = "codex" ] && { printf 'off'; return 0; }
  case "${APD_REVIEW_RESUME:-}" in
    on)     printf 'on' ;;
    shadow) printf 'shadow' ;;
    *)      printf 'off' ;;
  esac
}

_rr_dir()     { printf '%s' "$PIPELINE_DIR/.review-snapshot"; }
_rr_resumes() { printf '%s' "$PIPELINE_DIR/.review-resumes"; }

# An agent id as CC writes it; anything else never reaches a path.
_rr_id_ok() { case "$1" in ''|*[!A-Za-z0-9]*) return 1 ;; esac; return 0; }

# _rr_task_files [base] — the files this task changed, one per line, relative
# to the project. The same rule as `_write_reviewed_files` in pipeline-advance
# (dirty against HEAD + untracked, framework files out, a file dirty before the
# spec and untouched since out); the exclusion pattern below is compared with
# that one by a test. Two differences, both needed for a diff that must not
# miss a file: names are read NUL-separated (git quotes a name with a non-ASCII
# byte, a quote or a tab, and a quoted name is not a path) and relative to the
# project directory (a project in a subdirectory of its repository). A name
# with a newline in it cannot be carried on a line (its pieces name no file):
# _rr_odd_names lists it, and the delta names it as not compared.
# _rr_git_ok — a work tree with a commit. `rev-parse --is-inside-work-tree`
# prints "false" with exit 0 inside a bare repository, and `git diff HEAD` lists
# nothing before the first commit: both would give an empty list, and an empty
# list reads as "nothing changed".
_rr_git_ok() {
  command -v git >/dev/null 2>&1 || return 1
  [ "$(git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ] || return 1
  git -C "$PROJECT_DIR" rev-parse --verify -q "HEAD^{commit}" >/dev/null 2>&1
}
_rr_names0() {
  git -C "$PROJECT_DIR" diff --name-only -z --relative "${1:-HEAD}" 2>/dev/null
  git -C "$PROJECT_DIR" ls-files --others --exclude-standard -z 2>/dev/null
}
_rr_odd_names() {
  local _f
  _rr_names0 "${1:-HEAD}" | while IFS= read -r -d '' _f; do
    case "$_f" in *$'\n'*) printf '%s\n' "$(printf '%s' "$_f" | tr '\n' '?')" ;; esac
  done | sort -u
}
_rr_task_files() {
  _rr_git_ok || return 0
  local _f _h _base_h _base="${1:-HEAD}"
  _rr_names0 "$_base" \
  | while IFS= read -r -d '' _f; do
      printf '%s\n' "$_f"
    done | sort -u | sed '/^$/d' \
  | while IFS= read -r _f; do
      case "$_f" in
          .apd/pipeline/*|.apd/memory/*|.apd/lessons.md|.apd/.pending-reload|.claude/memory/*|.claude/bin/*|.claude/rules/workflow.md|.claude/agents/*.bak.*|.claude/settings.local.json|.agents/*) continue ;;
      esac
      # (past the snapshot's time limit the check is skipped: the file is listed, and then named as not copied)
      if [ -f "$PIPELINE_DIR/.task-baseline" ] && { [ -z "${_rr_deadline:-}" ] || [ "$SECONDS" -lt "$_rr_deadline" ]; }; then
          _base_h=$(awk -F'\t' -v p="$_f" '$2==p {print $1; exit}' "$PIPELINE_DIR/.task-baseline")
          if [ -n "$_base_h" ]; then
              _h=$(git -C "$PROJECT_DIR" hash-object -- "$_f" 2>/dev/null || echo cur)
              [ "$_h" = "$_base_h" ] && continue
          fi
      fi
      printf '%s\n' "$_f"
  done
}

# _rr_last_stop <id> → timestamp of the id's last event when that event is a stop
_rr_last_stop() {
  awk -F'|' -v id="$1" 'NF >= 4 && $4 == id { ev = $2; ts = $1 } END { if (ev == "stop") print ts }' "$PIPELINE_DIR/.agents" 2>/dev/null
}

# _rr_agent_type <id> → the type the id STARTED as (a `start` line), or nothing
_rr_agent_type() {
  awk -F'|' -v id="$1" 'NF >= 4 && $2 == "start" && $4 == id { print $3; exit }' "$PIPELINE_DIR/.agents" 2>/dev/null
}

# _rr_tree_quiet <id> — may a copy taken NOW still stand for what <id> saw?
# No when an agent that can write code has any event since <id> last STARTED
# (or was continued) — during the review a file may have been read before it
# changed, after it the copy is of something else — or is running. Review
# roles (reviewer, adversarial, supervisor) do not count: they are bounded off
# code. What the ledger cannot see — the
# orchestrator changing a file itself — is caught per file by modification time
# in _rr_snapshot_take.
_rr_tree_quiet() {
  local typ
  awk -F'|' -v id="$1" 'NF >= 3 { n++; ty[n] = $3; if ($4 == id && ($2 == "start" || $2 == "resume")) at = n
                                   if ($4 != "") { last[$4] = $2; if ($2 == "start") st[$4] = $3 } }
       END { for (i = at + 1; i <= n; i++) print ty[i]
             for (k in last) if (last[k] != "stop") print ((k in st) ? st[k] : "?") }' "$PIPELINE_DIR/.agents" 2>/dev/null | sort -u \
  | { while IFS= read -r typ; do
        case "$(_dispatch_class "$typ")" in reviewer|adversarial|supervisor) ;; *) exit 1 ;; esac
      done; exit 0; }
}

# _rr_snapshot_take <id> <stamp> — copy the task files as they stand. Built in a
# temporary directory beside the target and renamed, so a killed copy leaves no
# half snapshot under the real name. The temporary directory is also the lock:
# one copy per reviewer at a time (parallel dispatches each run this hook), and
# what a killed copy left is removed when the process it names is gone. Not copied, and named in `skipped`: a symlink, a file over the size
# limit, a file modified after the stop, and whatever is left when the time
# limit is reached.
_rr_snapshot_take() {
  local id="$1" stamp="$2" base tmp f size stop_ep old deadline="${_rr_deadline:-$((SECONDS + RR_SNAPSHOT_MAX_SEC))}"
  _rr_id_ok "$id" || return 0
  [ -n "$stamp" ] || return 0      # GNU `date -d ""` is midnight, not an error
  stop_ep=$(_human_to_epoch "$stamp")
  [ -n "$stop_ep" ] || return 0
  base=$(_rr_dir)
  mkdir -p "$base" 2>/dev/null || return 0
  tmp="$base/.tmp.$id"
  if ! mkdir "$tmp" 2>/dev/null; then
    old=$(cat "$tmp/pid" 2>/dev/null)
    case "$old" in ''|*[!0-9]*) return 0 ;; esac
    kill -0 "$old" 2>/dev/null && return 0
    rm -rf "$tmp" 2>/dev/null; mkdir "$tmp" 2>/dev/null || return 0
  fi
  printf '%s\n' "$$" > "$tmp/pid"
  mkdir -p "$tmp/files" 2>/dev/null || { rm -rf "$tmp" 2>/dev/null; return 0; }
  : > "$tmp/list"; : > "$tmp/skipped"
  _rr_task_files | while IFS= read -r f; do
    printf '%s\n' "$f" >> "$tmp/list"
    if [ "$SECONDS" -ge "$deadline" ]; then printf '%s\n' "$f" >> "$tmp/skipped"; continue; fi
    if [ -L "$PROJECT_DIR/$f" ] || [ ! -f "$PROJECT_DIR/$f" ]; then
      [ -e "$PROJECT_DIR/$f" ] || [ -L "$PROJECT_DIR/$f" ] && printf '%s\n' "$f" >> "$tmp/skipped"
      continue
    fi
    if [ "$(_file_mtime "$PROJECT_DIR/$f")" -ge "$stop_ep" ]; then printf '%s\n' "$f" >> "$tmp/skipped"; continue; fi
    size=$(wc -c < "$PROJECT_DIR/$f" 2>/dev/null | tr -d '[:space:]')
    case "$size" in ''|*[!0-9]*) size=0 ;; esac
    if [ "$size" -gt "$RR_MAX_FILE_BYTES" ]; then printf '%s\n' "$f" >> "$tmp/skipped"; continue; fi
    mkdir -p "$tmp/files/$(dirname "$f")" 2>/dev/null && cp -p "$PROJECT_DIR/$f" "$tmp/files/$f" 2>/dev/null \
      || printf '%s\n' "$f" >> "$tmp/skipped"
  done
  git -C "$PROJECT_DIR" rev-parse HEAD > "$tmp/head" 2>/dev/null
  printf '%s\n' "$stamp" > "$tmp/stamp"
  rm -f "$tmp/pid" 2>/dev/null
  rm -rf "$base/$id" 2>/dev/null
  mv "$tmp" "$base/$id" 2>/dev/null || rm -rf "$tmp" 2>/dev/null
  return 0
}

# _rr_snapshot_pending — for every reviewer-class id whose last event is a stop,
# whose snapshot is not of that stop, and whose stop nothing code-writing has
# followed. One time limit for the whole pass. Never fails the caller.
_rr_snapshot_pending() {
  [ "$(_rr_mode)" = "off" ] && return 0
  [ -f "$PIPELINE_DIR/spec.done" ] && [ -f "$PIPELINE_DIR/.agents" ] || return 0
  # Without git the task's files cannot be told from the rest: no snapshot, so
  # no resume (an empty snapshot would read as "nothing changed").
  _rr_git_ok || return 0
  local id typ stamp have
  _rr_deadline=$((SECONDS + RR_SNAPSHOT_MAX_SEC))
  awk -F'|' 'NF >= 4 && $2 == "start" && $4 != "" { print $4 "|" $3 }' "$PIPELINE_DIR/.agents" 2>/dev/null | sort -u \
  | while IFS='|' read -r id typ; do
      [ "$(_dispatch_class "$typ")" = "reviewer" ] || continue
      stamp=$(_rr_last_stop "$id")      # empty while the agent runs: _rr_snapshot_take refuses a stop it cannot date
      have=$(cat "$(_rr_dir)/$id/stamp" 2>/dev/null)
      [ "$have" = "$stamp" ] && continue
      _rr_tree_quiet "$id" || continue
      _rr_snapshot_take "$id" "$stamp"
    done
  return 0
}

# _rr_resume_count [id] → allowed resumes on record (for one id, or all)
_rr_resume_count() {
  local f; f=$(_rr_resumes)
  [ -f "$f" ] || { printf '0'; return 0; }
  if [ -n "${1:-}" ]; then awk -F'|' -v id="$1" '$2 == id { n++ } END { print n + 0 }' "$f" 2>/dev/null
  else awk 'NF { n++ } END { print n + 0 }' "$f" 2>/dev/null; fi
}

# _rr_resume_check <id> → prints WHY the resume is refused; prints nothing (rc 0)
# when it may go ahead. Every branch is a refusal on its own.
_rr_resume_check() {
  local id="$1" typ stamp have budget count
  _rr_id_ok "$id" || { printf 'the recipient is not an agent id'; return 1; }
  [ -f "$PIPELINE_DIR/.agents" ] || { printf 'no agent ledger for this task'; return 1; }
  typ=$(_rr_agent_type "$id")
  [ -n "$typ" ] || { printf 'agent %s was not dispatched in this task' "$id"; return 1; }
  [ "$(_dispatch_class "$typ")" = "reviewer" ] || { printf '%s is not a code reviewer — the adversarial reviewer, the supervisor and builders are always dispatched fresh' "$typ"; return 1; }
  stamp=$(_rr_last_stop "$id")
  [ -n "$stamp" ] || { printf 'agent %s is still running (its last event is not a stop)' "$id"; return 1; }
  have=$(cat "$(_rr_dir)/$id/stamp" 2>/dev/null)
  [ -n "$have" ] && [ "$have" = "$stamp" ] || { printf 'no snapshot of what %s reviewed — either nothing was dispatched since its stop (no fix to re-review), or code was already being changed before a copy could be taken; dispatch a fresh reviewer' "$id"; return 1; }
  [ "$(_rr_resume_count "$id")" -lt "$RR_MAX_RESUMES_PER_AGENT" ] || { printf 'agent %s was already continued %s times — dispatch a fresh reviewer' "$id" "$RR_MAX_RESUMES_PER_AGENT"; return 1; }
  budget=$(_dispatch_budget reviewer)
  if [ "$budget" != "unlimited" ]; then
    count=$(_dispatch_count reviewer)
    [ "$count" -lt "$budget" ] 2>/dev/null || { printf 'the reviewer dispatch budget is spent (%s/%s) — a resume takes one slot' "$count" "$budget"; return 1; }
  fi
  return 0
}

# _rr_resume_record <id> — one line per allowed resume, with the mode the HOOK
# ran under. The reviewer gate reads the mode from here, not from the
# environment of whoever types the advance.
_rr_resume_record() {
  printf '%s|%s|%s|%s\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$1" "$(_rr_agent_type "$1")" "$(_rr_mode)" >> "$(_rr_resumes)" 2>/dev/null
}

# _rr_resume_shadow <id> — was <id> ever continued in shadow?
_rr_resume_shadow() {
  awk -F'|' -v id="$1" '$2 == id && $4 == "shadow" { f = 1 } END { exit f ? 0 : 1 }' "$(_rr_resumes)" 2>/dev/null
}

# _rr_latest_id → the reviewer id with the newest snapshot stamp
_rr_latest_id() {
  local d best="" bs="" s
  for d in "$(_rr_dir)"/*/; do
    [ -f "${d}stamp" ] || continue
    s=$(cat "${d}stamp" 2>/dev/null)
    if [ -z "$bs" ] || [ "$s" \> "$bs" ]; then bs="$s"; best="${d%/}"; best="${best##*/}"; fi
  done
  printf '%s' "$best"
}

# _rr_delta <id> — unified diff from what the reviewer saw to the working tree,
# over the files in the snapshot and the files the task has changed since. A
# file the task had not touched at review time is not in the snapshot: what the
# reviewer saw of it is HEAD (nothing is committed mid-task), so HEAD is its
# base — the HEAD the snapshot recorded, so a commit made since does not hide
# it. A file that was not copied (too large, not a regular file, modified after
# the stop, out of time) or cannot be read now is named, never shown as
# unchanged. Reads only; its scratch files live outside the pipeline directory.
# Not seen, stated: a file git ignores.
_rr_delta() {
  local id="$1" snap f a b any=0 tmp base rc
  _rr_id_ok "$id" || { echo "review-delta: not an agent id: $id" >&2; return 1; }
  snap="$(_rr_dir)/$id"
  [ -f "$snap/stamp" ] || { echo "review-delta: no snapshot for agent $id" >&2; return 1; }
  tmp=$(mktemp -d -t apd-rr.XXXXXX 2>/dev/null) || { echo "review-delta: no temporary directory" >&2; return 1; }
  echo "# review delta for agent $id — changes since its stop at $(cat "$snap/stamp")"
  base=$(cat "$snap/head" 2>/dev/null)
  if [ -n "$base" ] && ! git -C "$PROJECT_DIR" cat-file -e "$base^{commit}" 2>/dev/null; then
    echo "# NOT COMPARED (the commit the review was based on no longer exists — a file first touched after the review may be missing below; dispatch a fresh reviewer)"; any=1
    base=""
  fi
  [ -n "$base" ] || base=HEAD
  { cat "$snap/list" 2>/dev/null; _rr_task_files "$base"; } | sort -u | sed '/^$/d' > "$tmp/list"
  while IFS= read -r f; do
    if grep -qxF -- "$f" "$snap/skipped" 2>/dev/null; then
      echo "# NOT COMPARED (not copied at review time — review it in full): $f"; any=1; continue
    fi
    b="$PROJECT_DIR/$f"
    if [ -L "$b" ] || { [ -e "$b" ] && [ ! -f "$b" ]; }; then
      echo "# NOT COMPARED (not a regular file — review it in full): $f"; any=1; continue
    fi
    [ -f "$b" ] || b=/dev/null
    if grep -qxF -- "$f" "$snap/list" 2>/dev/null; then
      a="$snap/files/$f"; [ -f "$a" ] || a=/dev/null
    elif git -C "$PROJECT_DIR" cat-file -e "$base:./$f" 2>/dev/null; then
      a="$tmp/head"; git -C "$PROJECT_DIR" show "$base:./$f" > "$a" 2>/dev/null || { echo "# NOT COMPARED (HEAD version unreadable — review it in full): $f"; any=1; continue; }
    else
      a=/dev/null
    fi
    [ "$a" = /dev/null ] && [ "$b" = /dev/null ] && continue
    # GNU diff -q answers "differ" from the sizes alone and never opens the
    # files, so an unreadable one must be asked about first.
    rc=0
    { [ "$a" != /dev/null ] && [ ! -r "$a" ]; } && rc=2
    { [ "$b" != /dev/null ] && [ ! -r "$b" ]; } && rc=2
    [ "$rc" = 2 ] || { diff -q "$a" "$b" >/dev/null 2>&1; rc=$?; }
    if [ "$rc" -ge 2 ]; then
      echo "# NOT COMPARED (could not be read — review it in full): $f"; any=1; continue
    fi
    if [ "$rc" = 1 ]; then
      any=1
      [ "$a" = /dev/null ] && echo "# NEW since the review: $f"
      [ "$b" = /dev/null ] && echo "# REMOVED since the review: $f"
      diff -u -L "a/$f" -L "b/$f" "$a" "$b" 2>/dev/null
    fi
    if [ "$a" = "$snap/files/$f" ] && [ "$b" != /dev/null ]; then
      if { [ -x "$a" ] && [ ! -x "$b" ]; } || { [ ! -x "$a" ] && [ -x "$b" ]; }; then
        echo "# MODE CHANGED since the review (executable bit): $f"; any=1
      fi
    fi
  done < "$tmp/list"
  _rr_odd_names "$base" > "$tmp/odd"
  while IFS= read -r f; do
    echo "# NOT COMPARED (a newline in the file name — review it in full): $f"; any=1
  done < "$tmp/odd"
  rm -rf "$tmp" 2>/dev/null
  [ "$any" = 1 ] || echo "# no changes since the review"
  return 0
}
