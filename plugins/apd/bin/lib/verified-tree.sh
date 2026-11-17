#!/bin/bash
# verified-tree.sh — which working tree did the verifier step pass, and a way to
# run a command that must answer before a hook's time limit.
#
# Sourced by pipeline-advance (records the tree at the verifier step), guard-git
# (reads the record before a signed commit) and pipeline-post-commit (reads the
# recorded HEAD). Needs PROJECT_DIR, PIPELINE_DIR.
#
# Why: guard-git runs the project's verification inside a PreToolUse hook. Claude
# Code CANCELS a hook that passes its time limit and then RUNS the call, so a
# verification slower than the limit meant the commit went through unjudged. The
# record lets the guard see that the tree is the one the verifier step already
# verified, and the bounded runner lets it refuse — instead of being cancelled —
# when it is not and the verification does not fit.
#
# Nothing here WRITES the record: the one writer is the verifier step, and it
# signs it the way the step flags are signed (validate-agent), so a record
# written by hand is refused like a hand-written `verifier.done`.

_vt_file() { printf '%s' "$PIPELINE_DIR/verified-tree.done"; }

_vt_validator() {
    local os arch
    os=$(uname -s | tr '[:upper:]' '[:lower:]'); arch=$(uname -m)
    [ "$arch" = "x86_64" ] && arch="amd64"
    [ "$arch" = "aarch64" ] && arch="arm64"
    printf '%s' "${APD_PLUGIN_ROOT}/bin/compiled/validate-agent-${os}-${arch}"
}

# _vt_record_ok — the record carries its signature. Where the validator does
# not exist the step flags are unsigned too, and the record is taken as it is.
_vt_record_ok() {
    local v; v=$(_vt_validator)
    [ -f "$(_vt_file)" ] || return 1
    [ -x "$v" ] || return 0
    "$v" verify -step verified-tree -pipeline-dir "$PIPELINE_DIR" >/dev/null 2>&1
}

# What the framework itself writes between the verifier step and the commit
# (pipeline state, logs, the shortcut) — the list the reviewed scope leaves out.
# With these in, a project that tracks its memory directory would never match
# its own record.
_VT_FRAMEWORK=".apd/pipeline .apd/memory .apd/lessons.md .apd/.pending-reload .claude/memory .claude/bin .claude/rules/workflow.md .claude/agents/*.bak.* .claude/settings.local.json .agents"

# _vt_head → the commit HEAD names, `unborn` before the first commit, empty
# outside a git work tree.
_vt_head() {
    command -v git >/dev/null 2>&1 || return 0
    git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    git -C "$PROJECT_DIR" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null || printf 'unborn\n'
}

# _vt_fingerprint → `<HEAD>.<tree>`: the tree git itself would write for the
# project's working files as they are now — content, file modes, links, deleted
# and new files, the commit a submodule or a nested repository stands on.
# Staging changes nothing. Computed in a copy of the index with a throwaway
# object directory, so neither the repository's index nor its objects are
# touched. Prints nothing when it cannot be computed (no git, not a work tree,
# git refuses to add something).
_vt_fingerprint() {
    local head tmp tree
    head=$(_vt_head)
    [ -n "$head" ] || return 0
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/apd-vt.$$.XXXXXX" 2>/dev/null) || return 0
    tree=$(
        cd "$PROJECT_DIR" 2>/dev/null || exit 0
        idx=$(git rev-parse --git-path index 2>/dev/null)
        obj=$(git rev-parse --git-path objects 2>/dev/null)
        case "$obj" in (/*) ;; (*) obj="$PWD/$obj" ;; esac   # `(pattern)`: bash 3.2 reads a bare `)` here as the end of the substitution
        # -p: with a newer time on the copy git would trust the sizes and times it
        # holds and miss a same-size edit made in the second the index was written
        [ -f "$idx" ] && cp -p "$idx" "$tmp/index" 2>/dev/null
        # the repository's objects as an alternate, named in a file: the
        # environment variable is a `:`-separated list and breaks on a path with one
        mkdir -p "$tmp/objects/info" 2>/dev/null || exit 0
        printf '%s\n' "$obj" > "$tmp/objects/info/alternates" || exit 0
        export GIT_INDEX_FILE="$tmp/index" GIT_OBJECT_DIRECTORY="$tmp/objects"
        # a file marked assume-unchanged or skip-worktree is not read by `git add`;
        # in this copy every file is read
        if git ls-files -v 2>/dev/null | grep -q '^[a-zS] '; then
            # one call per bit: given together, git clears only the first
            git ls-files -z 2>/dev/null | git update-index -z --no-assume-unchanged --stdin >/dev/null 2>&1 || exit 0
            git ls-files -z 2>/dev/null | git update-index -z --no-skip-worktree --stdin >/dev/null 2>&1 || exit 0
        fi
        git add -A -- . >/dev/null 2>&1 || exit 0
        # shellcheck disable=SC2086
        git rm -r -q --cached --ignore-unmatch -- $_VT_FRAMEWORK >/dev/null 2>&1
        git write-tree 2>/dev/null
    )
    rm -rf "$tmp" 2>/dev/null
    [ -n "$tree" ] && printf '%s.%s\n' "$head" "$tree"
    return 0
}

# _vt_script_id <file> → what identifies the verification script that ran: the
# guard skips its own run only when the script it would run is that same one.
_vt_script_id() { printf 's%s' "$(cksum < "$1" 2>/dev/null | tr -s ' \t' '-')"; }   # never empty: an absent record has no id to equal

# The record's first line is `<epoch>|<time>|<HEAD>.<tree>|<script id>`; the tree
# is empty when the step verified nothing it can vouch for.
_vt_recorded_fp()     { [ -f "$(_vt_file)" ] && head -1 "$(_vt_file)" 2>/dev/null | awk -F'|' '{ print $3 }'; }
_vt_recorded_script() { [ -f "$(_vt_file)" ] && head -1 "$(_vt_file)" 2>/dev/null | awk -F'|' '{ print $4 }'; }
_vt_recorded_head()   { _vt_recorded_fp | awk -F. 'NF == 2 { print $1 }'; }

# _vt_bounded <deadline> <output file> <command…> — runs the command in its own
# process group with stdout and stderr in the file, and returns its exit status,
# or 124 once the shell's SECONDS reaches the deadline; the whole group is then
# killed. The output goes to a file and not to the caller's stderr because a
# survivor holding the hook's pipe would keep the hook waiting past its limit.
_vt_bounded() {
    local deadline="$1" out="$2" pid rc
    shift 2
    set -m
    ( "$@" ) > "$out" 2>&1 < /dev/null &
    pid=$!
    set +m
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
            sleep 0.2 2>/dev/null || sleep 1
            kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
            { wait "$pid"; } 2>/dev/null
            return 124
        fi
        sleep 0.1 2>/dev/null || sleep 1
    done
    { wait "$pid"; rc=$?; } 2>/dev/null
    return "$rc"
}
