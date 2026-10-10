#!/bin/bash
# APD pipeline telemetry (v7.4) — an append-only event log, observability only.
#
# `pipeline-metrics.log` holds ONE row per run, written at reset from whatever
# state survived until then. Three things never reached it: a rollback deletes
# the adversarial/supervision summaries and rationale (a run with thirty
# dispatches closed as 0:0:0), a re-advanced step overwrites its own timestamp
# (the time spent on the repeat is gone), and nothing recorded what the working
# tree looked like at any point. This file records those as EVENTS, at the
# moment they happen, in `<memory>/pipeline-events.log`:
#
#   <ts>|v1|<run>|<event>|<k=v k=v …>|<task>
#
#   run    the epoch of `spec.done` — the same value as column 3 of the metrics
#          row, so the two files join on (run, task). No new state.
#   event  advance | rollback | review-state | verify | run-end
#
# `review-state` is an OBSERVATION, not a pass: one line each time the
# adversarial/supervision files on disk differ from what was last recorded
# (a summary first, then the same summary with its rationale, are two lines of
# one pass). What separates passes is on the same line and in the neighbouring
# events: `disp=` (builder/reviewer/adversarial dispatches since the spec, from
# the `.agents` ledger) and a `rollback … wiped=1`.
#
# Rules this file keeps, each with a row in test-codex-adapter §154:
#   - It decides NOTHING. No caller reads an event back to choose a branch; every
#     function returns 0. The numbers are raw data: an unchanged tree
#     fingerprint is a fact about the tree, not a verdict about progress.
#   - A value that was not measured is ABSENT, never 0 (`adv=` is missing when
#     no adversarial summary exists; the diff fields are missing outside git).
#   - A failed write never changes an exit code, and is never silent: one WARN
#     on stderr per invocation, and `_ev_probe` (status, doctor) reports the
#     condition while it lasts. No marker file — the probe reads the live state.
#   - `APD-VERIFY-*` tasks and APD_AUDIT_SYNTHETIC=1 write nothing (the same
#     exclusion as the metrics row and the guard-audit SYNTHETIC tag).
#
# Sourced by: bin/core/pipeline-advance, bin/core/pipeline-doctor.
# Needs: PIPELINE_DIR, MEMORY_DIR, PROJECT_DIR (resolve-project.sh), _file_mtime
# (portable.sh).

_EV_WARNED=""

_ev_file()    { printf '%s' "${MEMORY_DIR:-}/pipeline-events.log"; }
_ev_rb_file() { printf '%s' "${MEMORY_DIR:-}/adversarial-rationale-rollbacks.md"; }

# _ev_run / _ev_task — the identity of the run on disk (empty when no spec.done)
_ev_run()  { head -1 "$PIPELINE_DIR/spec.done" 2>/dev/null | cut -d'|' -f1; }
_ev_task() { head -1 "$PIPELINE_DIR/spec.done" 2>/dev/null | cut -d'|' -f3; }

# _ev_unwritable [file] → prints WHY the file (default: the event log) cannot be
# appended to, nothing when it can. Every writer in this file asks it BEFORE it
# opens or reads the file, so the step's WARN, `status` and the doctor cannot
# disagree — and a FIFO, a device or a directory in the file's place is never
# opened (a FIFO with no reader blocks the open forever: audit-740 F10 for the
# event log, N1 for a `grep` on the rollbacks file).
_ev_unwritable() {
    local f="${1:-$(_ev_file)}"
    if [ -z "${MEMORY_DIR:-}" ] || [ ! -d "${MEMORY_DIR:-}" ]; then
        echo "memory directory missing: ${MEMORY_DIR:-<unset>}"
    elif [ ! -x "$MEMORY_DIR" ]; then
        echo "$MEMORY_DIR cannot be entered"
    elif [ -L "$f" ] && [ ! -e "$f" ]; then
        echo "$f is a dangling symlink"
    elif [ -e "$f" ] && [ ! -f "$f" ]; then
        echo "$f is not a regular file"
    elif [ -e "$f" ] && [ ! -w "$f" ]; then
        echo "$f is not writable"
    elif [ ! -e "$f" ] && [ ! -w "$MEMORY_DIR" ]; then
        echo "$MEMORY_DIR is not writable"
    fi
    return 0
}

# _ev_probe → one line per telemetry file that cannot be written (status, doctor)
_ev_probe() {
    local f why
    for f in "$(_ev_file)" "$(_ev_rb_file)"; do
        why=$(_ev_unwritable "$f")
        [ -n "$why" ] && echo "telemetry: ${f##*/} cannot be written ($why) — the pipeline is unaffected, run telemetry is not recorded"
    done
    return 0
}

# _ev_warn [file] [reason] — once per file per invocation, naming the file that was not written
_ev_warn() {
    local f="${1:-$(_ev_file)}" why
    case "$_EV_WARNED" in *"|${f##*/}|"*) return 0 ;; esac
    _EV_WARNED="$_EV_WARNED|${f##*/}|"
    why="${2:-$(_ev_unwritable "$f")}"
    echo "WARN: telemetry — ${f##*/} was not written (${why:-append failed}). The pipeline is not affected; this step's telemetry is missing." >&2
    return 0
}

# _ev_task_clean <task> → the task as it is written in the last field of a line
_ev_task_clean() {
    local t="$1"
    t=${t//$'\n'/ }; t=${t//$'\r'/ }; t=${t//|/ }
    printf '%s' "$t"
}

# _ev_write <run> <task> <event> <fields> — append one event. Always returns 0.
_ev_write() {
    local run="$1" task="$2" ev="$3" fields="$4" f rt line
    [ "${APD_AUDIT_SYNTHETIC:-}" = "1" ] && return 0
    case "$task" in APD-VERIFY-*) return 0 ;; esac
    task=$(_ev_task_clean "$task")
    fields=${fields//$'\n'/ }; fields=${fields//|/ }
    rt=cc; [ "${APD_RUNTIME:-}" = "codex" ] && rt=codex
    f=$(_ev_file)
    line="$(date +"%Y-%m-%d %H:%M:%S")|v1|${run:-unknown}|${ev}|rt=${rt}${fields:+ $fields}|${task}"
    if [ -z "$(_ev_unwritable)" ] && { printf '%s\n' "$line" >> "$f"; } 2>/dev/null; then
        return 0
    fi
    _ev_warn
    return 0
}

# _ev_tree_fields → `head=… wt=… files=N ins=N del=N untracked=N` for the working
# tree against HEAD, APD's own pipeline and memory directories left out (the
# pipeline writes there on every step). Prints nothing outside a git checkout.
# `git diff` rewrites .git/index whenever a tracked file's stat data is stale,
# with or without --no-optional-locks (measured on git 2.56, audit-740 F3) —
# `git diff-index` compares the same content and leaves the index alone. The
# project's external diff driver and textconv are switched off and untracked
# files are hashed unfiltered: telemetry runs no program a project configured
# (F4). A clean filter still runs for a MODIFIED tracked file — git cannot
# compare it otherwise. Untracked files are read with cksum from the project
# directory: `git hash-object --stdin-paths` resolves names from the repository
# ROOT, so in a project that is a subdirectory of its repo it found none of
# them and `wt` never moved (F9). `--` ends cksum's options: one untracked file
# named `-rf` made cksum fail for the whole batch (N3). `-M` gives the plumbing
# the rename detection `git diff` has by default (a staged rename read as two
# files, N7).
_ev_tree_fields() {
    command -v git >/dev/null 2>&1 || return 0
    git --no-optional-locks -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    local head wt ns untracked out=""
    set -- -- . ':(exclude).apd/pipeline' ':(exclude).apd/memory' ':(exclude).claude/memory'
    head=$(git --no-optional-locks -C "$PROJECT_DIR" rev-parse --short=12 HEAD 2>/dev/null) || head=""
    if [ -n "$head" ]; then
        out="head=$head"
        wt=$( { git --no-optional-locks -C "$PROJECT_DIR" diff-index -p -M --no-ext-diff --no-textconv HEAD "$@" 2>/dev/null
                ( cd "$PROJECT_DIR" 2>/dev/null && git --no-optional-locks ls-files -z --others --exclude-standard "$@" 2>/dev/null \
                    | xargs -0 cksum -- 2>/dev/null )
              } | git --no-optional-locks hash-object --stdin 2>/dev/null | cut -c1-12 )
        [ -n "$wt" ] && out="$out wt=$wt"
        # --numstat, not --shortstat: the sentence is translated by a localised
        # git and a parser that missed it wrote files=0 for a changed tree (F8).
        # A binary file counts as a file; its "-" columns add nothing.
        ns=$(git --no-optional-locks -C "$PROJECT_DIR" diff-index --numstat -M --no-ext-diff --no-textconv HEAD "$@" 2>/dev/null) && \
            out="$out $(printf '%s\n' "$ns" | awk -F'\t' 'NF >= 3 { f++; if ($1 ~ /^[0-9]+$/) i += $1; if ($2 ~ /^[0-9]+$/) d += $2 } END { printf "files=%d ins=%d del=%d", f, i, d }')"
    fi
    if untracked=$(git --no-optional-locks -C "$PROJECT_DIR" ls-files --others --exclude-standard "$@" 2>/dev/null); then
        untracked=$(printf '%s' "$untracked" | grep -c .)
        out="${out:+$out }untracked=${untracked:-0}"
    fi
    printf '%s' "$out"
}

# _ev_tree_bounded → `_ev_tree_fields`, given _EV_TREE_SEC seconds. The git work
# is the only part of this file whose cost grows with the project, and a step
# has callers with a clock (the Codex MCP wrapper allows pipeline-advance 30 s):
# past the budget the fields are replaced by `tree=timeout` and the step ends
# (`tree=unmeasured` when the temp file for the result cannot be created).
# (APD_TELEMETRY_TREE_SEC changes the budget; the suite uses it to hold the
# window open for a kill.)
# The result goes through a temp file, not a pipe, and the subshell redirects
# itself with `exec` BEFORE it starts anything: a redirection written on the
# subshell instead leaves bash's saved copies of the caller's stdout in every
# process the function forks, and the caller's `$(…)` then waits for the last
# git to exit — the budget measured 13 s against a git that hung in `diff`
# (audit-740 F1). A git that outlives the budget is left to finish on its own;
# it holds nothing of the step's.
_EV_TREE_SEC=3
case "${APD_TELEMETRY_TREE_SEC:-}" in ''|*[!0-9]*|0) ;; *) _EV_TREE_SEC=$APD_TELEMETRY_TREE_SEC ;; esac
_ev_tree_bounded() {
    local tmp pid i=0 max=$(( _EV_TREE_SEC * 10 ))
    # No temp file (TMPDIR missing, read-only, full): the fields are not measured.
    # Calling _ev_tree_fields directly here would be the one path with no budget
    # at all — 12 s against a slow git, forever against a hung one (audit-740 B1).
    tmp=$(mktemp "${TMPDIR:-/tmp}/apd-ev.XXXXXX" 2>/dev/null) || { printf 'tree=unmeasured'; return 0; }
    ( exec > "$tmp" 2>/dev/null; _ev_tree_fields ) &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$i" -ge "$max" ]; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            rm -f "$tmp"
            printf 'tree=timeout'
            return 0
        fi
        if sleep 0.1 2>/dev/null; then i=$((i + 1)); else sleep 1; i=$((i + 10)); fi   # a sleep without fractions (busybox)
    done
    wait "$pid" 2>/dev/null
    cat "$tmp" 2>/dev/null
    rm -f "$tmp"
    return 0
}

# _ev_disp_field → `disp=<builder>/<reviewer>/<adversarial>` — dispatches since
# the spec, read from the ledger by the budget's own counter. Nothing when there
# is no ledger (no dispatch was recorded — which is not the same as none ran).
_ev_disp_field() {
    [ -f "$PIPELINE_DIR/.agents" ] || return 0
    type _dispatch_count >/dev/null 2>&1 || return 0
    printf 'disp=%s/%s/%s' "$(_dispatch_count builder)" "$(_dispatch_count reviewer)" "$(_dispatch_count adversarial)"
}

# _ev_join <field group>… → the non-empty groups, one space apart
_ev_join() {
    local o="" a
    for a in "$@"; do [ -n "$a" ] && o="${o:+$o }$a"; done
    printf '%s' "$o"
}

# _ev_capture — remember the run on disk (identity, spec timestamp, dispatch
# counts) in _EV_C_*. A step that deletes pipeline state calls this BEFORE the
# deletion and emits AFTER it, so the telemetry work never sits between two of
# the step's own state changes: a kill during it leaves exactly the state the
# step would have left without telemetry, and one event missing.
_ev_capture() {
    _EV_C_RUN=$(_ev_run); _EV_C_TASK=$(_ev_task); _EV_C_DISP=$(_ev_disp_field)
    _EV_C_SINCE=$(head -1 "$PIPELINE_DIR/spec.done" 2>/dev/null | cut -d'|' -f2)
    _EV_C_HAS=0; [ -f "$PIPELINE_DIR/spec.done" ] && _EV_C_HAS=1
    return 0
}

# _ev_step <advance|rollback> <step> [extra fields] — a phase transition, from
# the captured run when `_ev_capture` ran in this invocation, else from disk.
_ev_step() {
    [ "${_EV_C_HAS:-}" = 1 ] || _ev_capture
    _ev_write "$_EV_C_RUN" "$_EV_C_TASK" "$1" "$(_ev_join "step=$2" "${3:-}" "$_EV_C_DISP" "$(_ev_tree_bounded)")"
    _EV_C_HAS=""
    return 0
}

# _ev_pass_fp → fingerprint of the review state on disk (name, mtime, content of
# each of the four files that exists); empty when none exists. The mtime is part
# of it on purpose: the same files seen twice (a repeated or interrupted
# rollback/reset) give the same value, a summary written again — even with
# identical text — gives a new one.
_ev_pass_fp() {
    local n any=0
    for n in .adversarial-summary .adversarial-rationale.md .supervision-summary .supervision-rationale.md; do
        [ -f "$PIPELINE_DIR/$n" ] && any=1
    done
    [ "$any" = 1 ] || return 0
    for n in .adversarial-summary .adversarial-rationale.md .supervision-summary .supervision-rationale.md; do
        [ -f "$PIPELINE_DIR/$n" ] || continue
        printf '%s %s\n' "$n" "$(_file_mtime "$PIPELINE_DIR/$n")"
        cat "$PIPELINE_DIR/$n" 2>/dev/null
    done | cksum 2>/dev/null | tr -s ' \t' '-' | sed 's/-*$//'
}

# _ev_seen <run> <event> <task> [fp] → 0 when the log holds a line of that event
# for exactly that run AND exactly that task (and, when given, that review-state
# fingerprint). Fields are compared whole: a substring match read task `fix` as
# already recorded once `fix-2` was, and `r`, `v1` or an empty task matched the
# line's own `|run-end|` and `|v1|` (audit-740 N4). The values travel in the
# environment — `awk -v` would interpret a backslash in a task name — and every
# comparison is forced to TEXT with `""`: awk compares two number-looking
# strings as numbers, so task `42.0` was "seen" once `42` was on record (R1).
# A trailing CR on the last field (a log saved with CRLF) is not part of the
# task (R2).
_ev_seen() {
    local f
    f=$(_ev_file)
    [ -f "$f" ] || return 1
    local n
    n=$(EV_R="${1:-unknown}" EV_E="$2" EV_T="$(_ev_task_clean "$3")" EV_F="${4:-}" LC_ALL=C awk -F'|' '
        NF == 6 { t = $6; sub(/\r$/, "", t)
            if (($2 "") == "v1" && ($3 "") == (ENVIRON["EV_R"] "") && ($4 "") == (ENVIRON["EV_E"] "") && (t "") == (ENVIRON["EV_T"] "") \
                && ((ENVIRON["EV_F"] "") == "" || index($5 " ", " fp=" ENVIRON["EV_F"] " "))) found = 1 }
        END { print found + 0 }' "$f" 2>/dev/null)
    [ "$n" = 1 ]
}

# _ev_pass_observe <at> — record the review state as it stands, once. Called at
# the top of every state-changing step, i.e. before any of them can delete it.
_ev_pass_observe() {
    [ -f "$PIPELINE_DIR/spec.done" ] || return 0
    local run task fp fields line n
    fp=$(_ev_pass_fp)
    [ -n "$fp" ] || return 0
    run=$(_ev_run); task=$(_ev_task)
    _ev_seen "$run" review-state "$task" "$fp" && return 0
    fields="at=$1 fp=$fp"
    n=$(_ev_disp_field); [ -n "$n" ] && fields="$fields $n"
    if [ -f "$PIPELINE_DIR/.adversarial-summary" ]; then
        line=$(grep '^ADVERSARIAL:' "$PIPELINE_DIR/.adversarial-summary" 2>/dev/null | head -1)
        case "$line" in
            ADVERSARIAL:*[!0-9:]*|'') fields="$fields adv=unparsed" ;;
            ADVERSARIAL:*:*:*)        fields="$fields adv=${line#ADVERSARIAL:}" ;;
            *)                        fields="$fields adv=unparsed" ;;
        esac
    fi
    if [ -f "$PIPELINE_DIR/.adversarial-rationale.md" ]; then
        n=$(grep -c '^## Finding ' "$PIPELINE_DIR/.adversarial-rationale.md" 2>/dev/null); fields="$fields advf=${n:-0}"
        n=$(grep -c '^\*\*Status:\*\* dismissed$' "$PIPELINE_DIR/.adversarial-rationale.md" 2>/dev/null); fields="$fields do=${n:-0}"
        n=$(grep -c '^\*\*Status:\*\* reviewer-self-dismissed$' "$PIPELINE_DIR/.adversarial-rationale.md" 2>/dev/null); fields="$fields dr=${n:-0}"
    fi
    if [ -f "$PIPELINE_DIR/.supervision-summary" ]; then
        line=$(grep '^SUPERVISION:' "$PIPELINE_DIR/.supervision-summary" 2>/dev/null | head -1)
        case "$line" in
            SUPERVISION:*[!0-9:]*|'') fields="$fields sup=unparsed" ;;
            SUPERVISION:*:*:*)        fields="$fields sup=${line#SUPERVISION:}" ;;
            *)                        fields="$fields sup=unparsed" ;;
        esac
    fi
    if [ -f "$PIPELINE_DIR/.supervision-rationale.md" ]; then
        n=$(grep -c '^## Finding ' "$PIPELINE_DIR/.supervision-rationale.md" 2>/dev/null); fields="$fields supf=${n:-0}"
    fi
    _ev_write "$run" "$task" review-state "$fields "
    return 0
}

# _ev_archive_rollback — a rollback of the reviewer or verifier step deletes the
# rationale files, and until v7.4 nothing kept them (only reset and the spec
# re-advance archive, into adversarial-rationale-archive.md). The text goes to
# its OWN file, adversarial-rationale-rollbacks.md: the existing archive stays
# byte for byte what it was, so a rollback followed by a reset can never put
# one rationale into it twice (audit-740 F7). One entry per review state — the
# `pass-fp` line, written last, is the record. The entry is prepared in a temp
# file and appended with one `cat`; that is not an atomic write (N5): a kill in
# the middle of it leaves a partial entry WITHOUT its mark, and the next
# rollback of the same state then appends the whole entry after it. The files
# are copied, never read into a variable — a command substitution drops NUL
# bytes and trailing blank lines and, under bash ≥ 4.4, says so on stderr (N2).
_ev_archive_rollback() {
    [ "${APD_AUDIT_SYNTHETIC:-}" = "1" ] && return 0
    [ -s "$PIPELINE_DIR/.adversarial-rationale.md" ] || [ -s "$PIPELINE_DIR/.supervision-rationale.md" ] || return 0
    local task run a mark tmp n
    task=$(_ev_task); run=$(_ev_run)
    case "$task" in APD-VERIFY-*) return 0 ;; esac
    a=$(_ev_rb_file)
    [ -z "$(_ev_unwritable "$a")" ] || { _ev_warn "$a"; return 0; }
    mark="<!-- pass-fp: ${run:-unknown}/$(_ev_pass_fp) -->"
    grep -qF -- "$mark" "$a" 2>/dev/null && return 0
    tmp=$(mktemp "${TMPDIR:-/tmp}/apd-ev.XXXXXX" 2>/dev/null) || { _ev_warn "$a" "no temp file to prepare the entry in"; return 0; }
    # An entry is appended — and so marked as kept — only when every source file
    # was read: an unreadable rationale used to leave a marked entry without the
    # text, in silence, and the mark then kept it from ever being added (R3).
    if {
        printf '\n<!-- ============================================================ -->\n'
        printf '## Rolled back %s — %s\n**Run:** %s\n' "$(date +"%Y-%m-%d %H:%M:%S")" "${task:-(unknown)}" "${run:-unknown}"
        for n in .adversarial-summary .adversarial-rationale.md .supervision-summary .supervision-rationale.md; do
            [ -s "$PIPELINE_DIR/$n" ] || continue
            printf '\n### %s\n\n' "$n"
            cat "$PIPELINE_DIR/$n" || { rm -f "$tmp"; break; }
            printf '\n'
        done
        [ -f "$tmp" ] && printf '\n%s\n' "$mark"
    } > "$tmp" 2>/dev/null && [ -f "$tmp" ]; then
        { cat "$tmp" >> "$a"; } 2>/dev/null || _ev_warn "$a"
    else
        _ev_warn "$a" "a summary or rationale file could not be read"
    fi
    rm -f "$tmp"
    return 0
}

# _ev_run_end <status> — the run has left the pipeline directory (reset, or a
# spec advance over a run that was never reset). Needs `_ev_capture` from before
# the deletion; once per run. `blocks=` counts the BLOCK lines guard-audit.log
# holds from the spec's timestamp on, `by=` splits them by reason; both are
# absent when the log is.
_ev_run_end() {
    [ "${_EV_C_HAS:-}" = 1 ] || return 0
    local fields audit by
    _EV_C_HAS=""
    # (run, task): two specs signed in the same second share the epoch (audit-740 F5)
    _ev_seen "$_EV_C_RUN" run-end "$_EV_C_TASK" && return 0
    fields=$(_ev_join "status=$1" "$_EV_C_DISP" "$(_ev_tree_bounded)")
    audit="${MEMORY_DIR:-}/guard-audit.log"
    if [ -f "$audit" ] && [ -n "$_EV_C_SINCE" ]; then
        by=$(awk -F'|' -v s="$_EV_C_SINCE" '
            $2 == "BLOCK" && $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / && $1 >= s { n++; c[$4]++ }
            END { o = ""; for (k in c) o = o (o == "" ? "" : ",") k ":" c[k]; printf "%d %s", n + 0, o }' "$audit" 2>/dev/null \
            | tr -d '\n')
        case "$by" in
            [0-9]*) fields="$fields blocks=${by%% *}"
                    [ -n "${by#* }" ] && [ "${by#* }" != "$by" ] && fields="$fields by=$(printf '%s' "${by#* }" | tr ',' '\n' | LC_ALL=C sort | tr '\n' ',' | sed 's/,$//; s/ /_/g')" ;;
        esac
    fi
    _ev_write "$_EV_C_RUN" "$_EV_C_TASK" run-end "$fields"
    return 0
}
