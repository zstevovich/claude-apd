#!/bin/bash
# APD Guard — blocks unauthorized git operations
# Subagents must not commit, push, or perform destructive operations
#
# Interface: --command <cmd> --agent-id <id> --agent-type <type>
#
# v7.1.5: judges git STATEMENTS, not the command text. guard-bash-scope lends
# its tokenizer (`--emit-git`): one line per git statement, words tab-separated,
# wrappers/assignments/keywords stepped, `sh -c`/`eval`/heredoc shells recursed.
# So `grep -rn "git commit" src/`, `git log | grep "git commit"` and a commit
# message that mentions `--force` are data, while `sh -c "git commit"`,
# `sudo git push` and `git -C dir commit` are the statements they are. If the
# tokenizer cannot run, the pre-v7.1.5 raw scan is used — fail closed, never open.

source "$(dirname "$0")/../lib/resolve-project.sh"
[ "$APD_ACTIVE" = false ] && exit 0

COMMAND=""
AGENT_ID=""
AGENT_TYPE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --command)    COMMAND="$2"; shift 2 ;;
    --agent-id)   AGENT_ID="$2"; shift 2 ;;
    --agent-type) AGENT_TYPE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Log function — logs blocked actions with agent context
log_block() {
  local reason="$1"
  local log_file="$MEMORY_DIR/guard-audit.log"
  if [ -d "$MEMORY_DIR" ]; then
    local agent_info="${AGENT_ID:-orchestrator}"
    [ -n "$AGENT_TYPE" ] && agent_info="${agent_info}(${AGENT_TYPE})"
    # Collapse newlines/CR so each event is exactly one log line
    local cmd="${RAW_COMMAND:-$COMMAND}"
    cmd="${cmd//$'\n'/ }"
    cmd="${cmd//$'\r'/ }"
    # guard-git carries its own log_block (does not source style.sh); mirror the
    # _audit_type() contract so verify-apd's guard-coverage blocks are tagged
    # SYNTHETIC, not BLOCK. guard-git produces the bulk of the self-test sweep
    # (commit-no-prefix, mass-staging, force-push, destructive-git, ...).
    local log_type="BLOCK"
    [ "${APD_AUDIT_SYNTHETIC:-}" = "1" ] && log_type="SYNTHETIC"
    echo "$(date +%Y-%m-%d\ %H:%M:%S)|${log_type}|${agent_info}|${reason}|${cmd}" >> "$log_file" 2>/dev/null
  fi
}

RAW_COMMAND="$COMMAND"

if [ -z "$COMMAND" ]; then
  exit 0
fi
COMMAND=$(echo "$COMMAND" | tr -s ' ' | sed 's/^ //')

# The orchestrator's marker: the whole command starts with it — or (v7.2.3, live:
# `git add a b && git status --short && APD_ORCHESTRATOR_COMMIT=1 git commit …`
# was refused on a real project) a git STATEMENT inside the command carries it
# as its own assignment prefix. The statements are still judged one by one
# (mass-staging, --no-verify, destructive), the marker only answers "did the
# orchestrator sign this".
HAS_PREFIX=false
echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 " && HAS_PREFIX=true
# (v7.2.3, audit G1: a raw-text regex for the mid-command marker was satisfied by a comment
# or a string — the per-statement marker now travels with the tokenized statement as
# `@APD_MARK`, emitted by guard-bash-scope from the statement's own assignment prefix.)
_marked=false
_signed() { [ "$HAS_PREFIX" = true ] || [ "$_marked" = true ]; }

_block() {  # <reason> <message lines...>
  local reason="$1"; shift
  local l; for l in "$@"; do echo "$l" >&2; done
  log_block "$reason"
  exit 2
}
_commit_allowed() {  # the prefixed commit path: pipeline gate + project verification
  # 1. Pipeline gate
  if [ -x "$SCRIPT_DIR/pipeline-gate" ]; then
    if ! bash "$SCRIPT_DIR/pipeline-gate" >&2; then
      echo "" >&2
      _block "pipeline-incomplete" "BLOCKED: Pipeline steps are not completed. Commit rejected."
    fi
  fi
  # 2. Verification (build + lint + test) — verify-all.sh lives in the PROJECT
  if [ -x "$CLAUDE_DIR/scripts/verify-all.sh" ]; then
    echo "-> Running pre-commit verification..." >&2
    if ! bash "$CLAUDE_DIR/scripts/verify-all.sh" >&2; then
      _block "verify-failed" "BLOCKED: Verification failed. Commit rejected."
    fi
  fi
  # Pipeline reset happens in PostToolUse hook (pipeline-post-commit)
  # — only AFTER a successful commit, not before
  echo "Pipeline + Verification passed — commit allowed." >&2
  exit 0
}

# ---------------------------------------------------------------------------
# Statement path (v7.1.5)
# ---------------------------------------------------------------------------
GBS="$SCRIPT_DIR/guard-bash-scope"
US=$'\x1f'
STMTS=""; TOKENIZED=false
if [ -f "$GBS" ]; then
  # Protocol canary first: if the emitter does not speak THIS format (version
  # skew, a broken edit), judge the raw way rather than trusting silence — the
  # first cut of this path allowed everything when the delimiter changed.
  if [ "$(bash "$GBS" --emit-git --command 'git status' 2>/dev/null)" = "GIT${US}status" ]; then
    STMTS=$(bash "$GBS" --emit-git --command "$RAW_COMMAND" 2>/dev/null) && TOKENIZED=true
  fi
fi

# A statement the tokenizer could not read (`$X git commit`, `"$@"`, `eval "$V"`)
# is judged the pre-v7.1.5 way — the raw scan over-blocks, it never under-blocks.
if [ "$TOKENIZED" = true ] && printf '%s\n' "$STMTS" | grep -q '^OPAQUE'; then
  TOKENIZED=false
fi

if [ "$TOKENIZED" = true ]; then
  SAW_COMMIT=false; SAW_ADD_CLAUDE=false
  _sub=""; _args=()
  # split one GIT line into subcommand + args, stepping git's global options
  _hooks_off=false
  _parse_git_line() {  # <unit-separator words after GIT> — a non-whitespace delimiter keeps EMPTY words (git -C "")
    local IFS="$US" w rest="${1#$US}"; local -a words=(); local i=0
    read -r -a words <<< "$rest"
    _sub=""; _args=(); _hooks_off=false; _marked=false
    # v7.2.3: the statement carried APD_ORCHESTRATOR_COMMIT=1 — read past the mark by INDEX: under
    # bash 3.2 a re-slice `words=(${words[@]+"${words[@]:1}"})` collapsed the array into one word
    # (`_sub='commit --no-verify -m x'`, no rule matched, exit 0 — the suite's 3.2 leg caught it)
    if [ "${words[0]:-}" = "@APD_MARK" ]; then _marked=true; i=1; fi
    while [ $i -lt ${#words[@]} ]; do
      w="${words[$i]}"
      case "$w" in
        -c) case "$(printf '%s' "${words[$((i + 1))]:-}" | tr 'A-Z' 'a-z')" in core.hookspath=*) _hooks_off=true ;; esac; i=$((i + 2)); continue ;;
        --config-env) case "$(printf '%s' "${words[$((i + 1))]:-}" | tr 'A-Z' 'a-z')" in core.hookspath=*) _hooks_off=true ;; esac; i=$((i + 2)); continue ;;
        -C|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix) i=$((i + 2)); continue ;;
        -c*) case "$(printf '%s' "$w" | tr 'A-Z' 'a-z')" in -ccore.hookspath=*) _hooks_off=true ;; esac; i=$((i + 1)); continue ;;
        --config-env=*) case "$(printf '%s' "$w" | tr 'A-Z' 'a-z')" in --config-env=core.hookspath=*) _hooks_off=true ;; esac; i=$((i + 1)); continue ;;
        -*) i=$((i + 1)); continue ;;
        *) _sub="$w"; i=$((i + 1)); break ;;
      esac
    done
    while [ $i -lt ${#words[@]} ]; do _args+=("${words[$i]}"); i=$((i + 1)); done
  }
  _cluster_has() {  # <word> <letters> [<value-letters>] → 0 when a single-dash cluster carries one of <letters>
    # BEFORE any letter that takes a stuck value (`-mfinal`, `-uno`, `-Snakey`
    # end the cluster there — audit pass #2): the rest of the word is a value.
    local w="${1#-}" i c
    case "$1" in -|--*) return 1 ;; -*) ;; *) return 1 ;; esac
    i=0
    while [ $i -lt ${#w} ]; do
      c="${w:$i:1}"
      case "$c" in [A-Za-z]) ;; *) return 1 ;; esac
      case "$c" in [$2]) return 0 ;; esac
      [ -n "${3:-}" ] && case "$c" in [$3]) return 1 ;; esac
      i=$((i + 1))
    done
    return 1
  }
  # flags whose NEXT word is a value (never a flag, never a path) — per subcommand
  _skip_values() {  # <subcommand> — rewrites _args without the values of value-taking flags
    local -a out=(); local i=0 a
    while [ $i -lt ${#_args[@]} ]; do
      a="${_args[$i]}"
      case "$1:$a" in
        commit:-m|commit:-F|commit:-C|commit:-c|commit:-t|commit:--message|commit:--file|commit:--author|commit:--date|commit:--template|commit:--fixup|commit:--squash|commit:--reuse-message|commit:--reedit-message|commit:--trailer|commit:--cleanup|commit:--pathspec-from-file|push:-o|push:--push-option|push:--receive-pack|push:--exec|push:--repo|add:--chmod|add:--pathspec-from-file|clean:-e|clean:--exclude)
          i=$((i + 2)); continue ;;
      esac
      out+=("$a"); i=$((i + 1))
    done
    _args=(${out[@]+"${out[@]}"})
  }
  _has_word() {  # <word> [words...] → 0 when the exact word is among the args
    local want="$1"; shift; local a; for a in "$@"; do [ "$a" = "$want" ] && return 0; done; return 1
  }
  while IFS= read -r line; do
    case "$line" in "GIT${US}"*|GIT) ;; *) continue ;; esac
    _parse_git_line "${line#GIT}"
    [ -n "$_sub" ] || continue
    case "$_sub" in commit|push|add|clean) _skip_values "$_sub" ;; esac
    # Block --no-verify (on any git statement) — and its equivalents: commit -n, -c core.hooksPath=…
    _nv=false
    _has_word "--no-verify" ${_args[@]+"${_args[@]}"} && _nv=true
    [ "$_hooks_off" = true ] && _nv=true
    if [ "$_sub" = commit ]; then for a in ${_args[@]+"${_args[@]}"}; do _cluster_has "$a" n mFCctSu && _nv=true; done; fi   # commit -n = --no-verify; a stuck value ends the cluster
    if [ "$_nv" = true ]; then
      _block "--no-verify" "BLOCKED: --no-verify is not allowed. Hooks must pass."
    fi
    case "$_sub" in
      add)
        for a in ${_args[@]+"${_args[@]}"}; do
          case "$a" in
            .|./|:/|-A|-u|-U|--all|--all=*|--update|'*'*)   # `*`-leading = the whole tree (git expands it too); src/*.cs is targeted
              _block "mass-staging" "BLOCKED: git add . / git add -A / git add --all is not allowed." "Use: git add <file1> <file2> ..." ;;
          esac
          _cluster_has "$a" AuU && _block "mass-staging" "BLOCKED: git add . / git add -A / git add --all is not allowed." "Use: git add <file1> <file2> ..."
          case "$a" in *.claude*) _signed || SAW_ADD_CLAUDE=true ;; esac   # v7.2.3: unsigned on THIS statement
        done ;;
      commit)
        SAW_COMMIT=true
        if _signed; then
          for a in ${_args[@]+"${_args[@]}"}; do
            if [ "$a" = --all ] || _cluster_has "$a" a mFCctSu; then
              _block "commit-all" "BLOCKED: git commit -a / --all is not allowed. Stage files explicitly."
            fi
          done
          # Block AI signatures — on the commit that would carry them (v7.1.5:
          # this check never reached a prefixed commit before; it fired only on
          # reads like `git log --grep`).
          if echo "$RAW_COMMAND" | grep -qi "co-authored-by"; then
            _block "ai-signature" "BLOCKED: AI signature (Co-Authored-By) is not allowed."
          fi
        else
          _block "commit-no-prefix" "BLOCKED: git commit is only allowed with APD_ORCHESTRATOR_COMMIT=1 prefix."
        fi ;;
      push)
        for a in ${_args[@]+"${_args[@]}"}; do
          case "$a" in
            --force|--force-with-lease|--force-with-lease=*|--force-if-includes|+?*)   # `+refspec` is a force push by refspec
              _block "force-push" "BLOCKED: git push --force is not allowed." ;;
          esac
          _cluster_has "$a" f o && _block "force-push" "BLOCKED: git push --force is not allowed."
        done
        _signed || _block "push-no-prefix" "BLOCKED: git push is only allowed with APD_ORCHESTRATOR_COMMIT=1 prefix." ;;
      reset)    _has_word "--hard" ${_args[@]+"${_args[@]}"} && _block "destructive-git" "BLOCKED: Destructive git operation is not allowed." ;;
      clean)
        _dry=false; for a in ${_args[@]+"${_args[@]}"}; do { [ "$a" = --dry-run ] || _cluster_has "$a" n e; } && _dry=true; done
        if [ "$_dry" = false ]; then
          for a in ${_args[@]+"${_args[@]}"}; do { [ "$a" = --force ] || _cluster_has "$a" fdxX e; } && _block "destructive-git" "BLOCKED: Destructive git operation is not allowed."; done
        fi ;;
      checkout) { _has_word "--" ${_args[@]+"${_args[@]}"} || _has_word "." ${_args[@]+"${_args[@]}"}; } && _block "destructive-git" "BLOCKED: Destructive git operation is not allowed." ;;
      restore)
        # v7.2.3 (live): `git restore --staged <path>` only unstages — the index moves,
        # the working tree does not. Destructive only when it touches the tree:
        # no --staged at all, or --staged together with -W/--worktree.
        _rs=false; _rw=false
        for a in ${_args[@]+"${_args[@]}"}; do
          case "$a" in --staged) _rs=true ;; --worktree) _rw=true ;; --) break ;;
            --*) ;; -*) _cluster_has "$a" S s && _rs=true; _cluster_has "$a" W s && _rw=true ;;   # (audit G2) git bundles short options: -Wq, -qW, -SWq; `-s` takes a value (-sWIP is not W)
          esac
        done
        { [ "$_rs" = false ] || [ "$_rw" = true ]; } && _block "destructive-git" "BLOCKED: Destructive git operation is not allowed." ;;
      stash)
        # v7.2.2 (Bambi audit): `clear` destroys every stash and was never on the
        # list; and a pipeline AGENT has no business moving the tree's uncommitted
        # state at all — `git stash` from a builder removes other agents' work in
        # a parallel run, `pop`/`apply` drops it back on whatever is there now.
        # The orchestrator keeps push/pop (it owns the tree); drop/clear stay
        # destructive for everyone; list/show are reads for everyone.
        case "${_args[0]:-}" in
          drop|clear) _block "destructive-git" "BLOCKED: Destructive git operation is not allowed." ;;
          list|show|--help|-h)  ;;
          *)          [ -n "$AGENT_TYPE" ] && _block "stash-from-agent" "BLOCKED: git stash is not allowed from a pipeline agent." "  It moves uncommitted work — yours and every other agent's — out of the working tree; the orchestrator owns the tree. Leave your changes in place and report; git stash list / git stash show are allowed." ;;
        esac ;;
      tag)      _has_word "-d" ${_args[@]+"${_args[@]}"} && _block "destructive-git" "BLOCKED: Destructive git operation is not allowed." ;;
      branch)   _has_word "-D" ${_args[@]+"${_args[@]}"} && _block "force-delete-branch" "BLOCKED: git branch -D (force delete) is not allowed. Use -d for safe delete." ;;
    esac
  done <<< "$STMTS"
  # .claude/ protection
  if [ "$SAW_ADD_CLAUDE" = true ]; then   # set only by an UNSIGNED statement (v7.2.3)
    _block "claude-dir-no-prefix" "BLOCKED: git add .claude/ is only allowed with APD_ORCHESTRATOR_COMMIT=1 prefix."
  fi
  # a prefixed commit that passed every statement check goes through the gate
  [ "$SAW_COMMIT" = true ] && _commit_allowed
  exit 0
fi

# ---------------------------------------------------------------------------
# Raw-scan fallback (pre-v7.1.5) — only when the tokenizer could not run.
# Over-blocks on text that mentions git; never under-blocks a real statement.
# ---------------------------------------------------------------------------
_raw_scan_fallback() {
  STRIPPED_CMD=$(echo "$COMMAND" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*//')
  NORMALIZED_GIT=$(echo "$STRIPPED_CMD" | sed -E 's/git[[:space:]]+(-[A-Za-z][[:space:]]+[^ ]+[[:space:]]+)*/git /g')
  if echo "$RAW_COMMAND" | grep -qE '(^| )--no-verify( |$)'; then
    _block "--no-verify" "BLOCKED: --no-verify is not allowed. Hooks must pass."
  fi
  if echo "$NORMALIZED_GIT" | grep -qE "git add[[:space:]]+(\.([[:space:]]|$)|-[AuU]([[:space:]=]|$)|--all([[:space:]=]|$)|\*)"; then
    _block "mass-staging" "BLOCKED: git add . / git add -A / git add --all is not allowed." "Use: git add <file1> <file2> ..."
  fi
  if echo "$NORMALIZED_GIT" | grep -qiE "git commit"; then
    if [ "$HAS_PREFIX" = true ]; then
      if echo "$NORMALIZED_GIT" | grep -qE "git commit[[:space:]]+.*(-a([[:space:]]|$)|--all([[:space:]]|$))"; then
        _block "commit-all" "BLOCKED: git commit -a / --all is not allowed. Stage files explicitly."
      fi
      if echo "$RAW_COMMAND" | grep -qi "co-authored-by"; then
        _block "ai-signature" "BLOCKED: AI signature (Co-Authored-By) is not allowed."
      fi
      _commit_allowed
    else
      _block "commit-no-prefix" "BLOCKED: git commit is only allowed with APD_ORCHESTRATOR_COMMIT=1 prefix."
    fi
  fi
  if echo "$NORMALIZED_GIT" | grep -qiE "git push"; then
    if echo "$NORMALIZED_GIT" | grep -qE "git push.*(-f([[:space:]]|$)|--force([[:space:]]|$)|--force-with-lease([[:space:]]|$))"; then
      _block "force-push" "BLOCKED: git push --force is not allowed."
    fi
    [ "$HAS_PREFIX" = true ] && exit 0
    _block "push-no-prefix" "BLOCKED: git push is only allowed with APD_ORCHESTRATOR_COMMIT=1 prefix."
  fi
  if echo "$RAW_COMMAND" | grep -qi "co-authored-by"; then
    _block "ai-signature" "BLOCKED: AI signature (Co-Authored-By) is not allowed."
  fi
  if echo "$RAW_COMMAND" | grep -qiE "git add.*\.claude"; then
    [ "$HAS_PREFIX" = true ] && exit 0
    _block "claude-dir-no-prefix" "BLOCKED: git add .claude/ is only allowed with APD_ORCHESTRATOR_COMMIT=1 prefix."
  fi
  if echo "$NORMALIZED_GIT" | grep -qiE "git (reset[[:space:]]+--hard|clean[[:space:]]+-[fdx]|checkout[[:space:]]+--[[:space:]]|checkout[[:space:]]+\.([[:space:]]|$)|stash[[:space:]]+(drop|clear)|tag[[:space:]]+-d([[:space:]]|$))"; then
    _block "destructive-git" "BLOCKED: Destructive git operation is not allowed."
  fi
  # v7.2.3: restore is destructive unless it is --staged without --worktree — judged per
  # OCCURRENCE (audit G3: one --staged exempted every other restore in the text)
  while IFS= read -r _occ; do
    [ -n "$_occ" ] || continue
    _rs=false; _rw=false
    printf '%s' "$_occ" | grep -qE "(^|[[:space:]])(--staged|-[a-zA-RT-Z]*S[a-zA-Z]*)([[:space:]]|$)" && _rs=true
    printf '%s' "$_occ" | grep -qE "(^|[[:space:]])(--worktree|-[a-zA-VX-Z]*W[a-zA-Z]*)([[:space:]]|$)" && _rw=true
    { [ "$_rs" = false ] || [ "$_rw" = true ]; } && _block "destructive-git" "BLOCKED: Destructive git operation is not allowed."
  done < <(printf '%s\n' "$NORMALIZED_GIT" | grep -oE 'git restore[^;&|)]*' || true)
  # v7.2.2: the agent stash rule in the raw path too — anything but list/show/help.
  # (a `)` or `"` may follow the word in this path — `echo "$(git stash)"` — so the
  # boundary is "not a word character", not whitespace. The read forms are
  # REMOVED from the text before the positive match — a per-command negative
  # grep let one `git stash list` veto every write in the same command:
  # `git stash show; echo "$(git stash)"` passed (audit F1).)
  _RAW_STASH=$(echo "$NORMALIZED_GIT" | sed -E 's/git stash[[:space:]]+(list|show|--help|-h)([^A-Za-z0-9_-]|$)/git stash-read\2/g')
  if [ -n "$AGENT_TYPE" ] && echo "$_RAW_STASH" | grep -qE "git stash([^A-Za-z0-9_-]|$)"; then
    _block "stash-from-agent" "BLOCKED: git stash is not allowed from a pipeline agent." "  It moves uncommitted work — yours and every other agent's — out of the working tree; the orchestrator owns the tree. Leave your changes in place and report; git stash list / git stash show are allowed."
  fi
  if echo "$NORMALIZED_GIT" | grep -qE "git branch[[:space:]]+-D([[:space:]]|$)"; then
    _block "force-delete-branch" "BLOCKED: git branch -D (force delete) is not allowed. Use -d for safe delete."
  fi
  exit 0
}
_raw_scan_fallback
