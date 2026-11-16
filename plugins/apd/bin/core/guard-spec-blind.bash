#!/bin/bash
# APD Spec-Blind Guard — enforces the adversarial reviewer's decontextualisation
#
# WHY THIS EXISTS
# The adversarial reviewer's value is positional: it judges the diff without
# knowing the intent behind it. Until v7.0 that was INTENT ONLY. Measured
# 2026-07-25 on a fixture, every channel returned exit 0:
#
#   guard-bash-scope  cat .apd/pipeline/spec-card.md   -> 0  (blocks WRITES only)
#   guard-secrets     Read .apd/pipeline/spec-card.md  -> 0  (env files + keys)
#   guard-pipeline-state                               -> 0  (PreToolUse Write|Edit)
#
# The template never mentions the spec, but the agent carries Read/Glob/Grep/
# Bash and reading the spec is the most natural thing an agent does when it
# wants to understand a task. Nothing stopped it, so "blind" was a claim.
#
# HOW THE CALLER IS IDENTIFIED
# The obvious home for a per-role guard is the agent's own frontmatter `hooks:`
# block. That block DOES NOT FIRE — measured on CC 2.1.220: a logging hook wired
# there never ran, in either schema form, while the identical hook in
# settings.json fired and blocked. Wiring it there would have been decoration.
#
# So the guard runs session-level from hooks/hooks.json, for every caller, and
# gates on `--agent-type` (the payload's `agent_type`, which CC sets to the
# agent's name for any tool call made inside a subagent and omits for the
# orchestrator's own calls). Anything that is not the adversarial reviewer
# leaves immediately: the orchestrator, the builders and the supervisor all need
# the spec, and blinding them would deadlock the pipeline.
#
# TWO CHANNELS, TWO MATCHERS
# A path matcher alone cannot scope Bash: its target is a command string, not a
# path. So the Read channel compares canonicalised paths, and the Bash channel
# scans tokens plus the sanctioned read commands. Both must hold.
#
# Interface: --agent-type <name> --file-path <path> --command <cmd>

source "$(dirname "$0")/../lib/resolve-project.sh"
source "$(dirname "$0")/../lib/style.sh"
[ "$APD_ACTIVE" = false ] && exit 0
[ "${APD_SKIP_SPEC_BLIND_GUARD:-}" = "1" ] && exit 0

FILE_PATH=""
COMMAND=""
AGENT_TYPE=""
TOOL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent-type) AGENT_TYPE="$2"; shift 2 ;;
    --file-path)  FILE_PATH="$2"; shift 2 ;;
    --command)    COMMAND="$2"; shift 2 ;;
    --tool)       TOOL="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# --- Whose calls this guard governs ---------------------------------------
# Empty agent_type = the orchestrator's own call. It writes the spec card;
# blinding it would deadlock the pipeline.
[ -z "$AGENT_TYPE" ] && exit 0
# Match the canonical name, and any renamed variant that still says what it is.
# A project that renames the role should not silently lose its blindness.
case "$AGENT_TYPE" in
  adversarial-reviewer|*adversarial*) : ;;
  *) exit 0 ;;
esac

# --- What is blinded -------------------------------------------------------
# The whole pipeline directory (spec-card, implementation-plan, the adversarial
# and supervision rationales — a prior pass's triage contaminates a fresh one)
# and the APD memory directory (status.md and the rationale archive carry the
# running task narrative). Blinding directories rather than a file list means a
# new state file is covered the day it is introduced, not the day someone
# remembers to add it here.
#
# ONE exception: .reviewed-files IS the reviewer's scope and the template tells
# it to read that file. Blinding it would break the role it is meant to protect.
ALLOWED_BASENAME=".reviewed-files"

PIPE_REL="${PIPELINE_DIR#"$PROJECT_DIR"/}"
MEM_REL="${APD_MEMORY_DIR#"$PROJECT_DIR"/}"

# Sanctioned read paths are still leaks for THIS role: `apd pipeline show spec`
# prints the spec-card, and `apd report` prints adversarial counts.
BLIND_COMMANDS=("pipeline show" "pipeline status" "pipeline metrics" "pipeline report" "apd report")

# Canonicalise PROJECT_DIR once — ABS_PATH below is physical (realpath/pwd -P)
# while PROJECT_DIR may be a logical, symlinked form (macOS /var, /tmp). The
# mismatch left REL_PATH absolute and silently missed every match (v6.37.1).
PROJ_CANON=""
if command -v realpath >/dev/null 2>&1; then
  PROJ_CANON=$(realpath "$PROJECT_DIR" 2>/dev/null || true)
fi
[ -z "$PROJ_CANON" ] && PROJ_CANON="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)"
[ -z "$PROJ_CANON" ] && PROJ_CANON="$PROJECT_DIR"

_rel_path() {
  local p="$1" abs="" d
  [ -z "$p" ] && return 0
  if command -v realpath >/dev/null 2>&1; then
    abs=$(realpath "$p" 2>/dev/null || true)
  fi
  if [ -z "$abs" ]; then
    d=$(dirname "$p")
    [ -d "$d" ] && abs="$(cd "$d" 2>/dev/null && pwd -P)/$(basename "$p")"
  fi
  [ -z "$abs" ] && abs="$p"
  # The project root itself strips to nothing, not to an absolute path: `path: "."`
  # resolves to PROJ_CANON exactly, where the `#PROJ_CANON/` strip does not match
  # (no trailing slash) and left the value absolute, so every comparison missed.
  [ "$abs" = "$PROJ_CANON" ] && { printf ''; return 0; }
  printf '%s' "${abs#"$PROJ_CANON"/}"
}

_deny() {
  echo "BLOCKED: adversarial-reviewer may not read $1" >&2
  echo "" >&2
  echo "  Your review is decontextualised BY DESIGN — you judge the diff on its" >&2
  echo "  own merit, without the spec, the plan or a previous pass's triage." >&2
  echo "  That blindness is the whole reason this role exists; reading intent" >&2
  echo "  would make your findings the same ones a contextual reviewer already" >&2
  echo "  produced." >&2
  echo "" >&2
  echo "  Your scope is $PIPE_REL/$ALLOWED_BASENAME — read the files it lists," >&2
  echo "  in full, and nothing else. If it is empty or missing, say so and stop." >&2
  log_block "spec-blind" "$2"
  exit 2
}

# Normalise a project-relative path for comparison: strip surrounding quotes,
# collapse `//` and `/./`, drop a leading `./` and any trailing `/`. The audit
# found the raw form let `.apd/./pipeline/spec-card.md` and `.apd//pipeline/...`
# through while the identical path without the extra separators was blocked —
# one character of difference, same file.
_norm() {
  local p="$1"
  p="${p//\"/}"; p="${p//\'/}"
  # The replacement is a BARE slash, not an escaped one. bash 5 strips the
  # backslash from `\/` in a replacement; bash 3.2 — which is what macOS ships
  # and what CI runs — keeps it, so `.apd/./pipeline/x` normalised to
  # `.apd\/pipeline/x`, no comparison matched, and spec-blindness silently
  # failed OPEN on every stock Mac. Measured on both interpreters side by side.
  while [ "$p" != "${p//\/.\///}" ]; do p="${p//\/.\///}"; done
  while [ "$p" != "${p//\/\///}" ]; do p="${p//\/\///}"; done
  p="${p#./}"
  p="${p%/}"
  [ "$p" = "." ] && p=""
  printf '%s' "$p"
}

# Does $1 reach $2 — by being it, being inside it, or being an ANCESTOR of it?
# The ancestor half is the one that was missing: a recursive read rooted at `.`
# or `.apd` reaches the pipeline directory just as surely as naming it, and the
# empty string means the project root.
_reaches() {
  local p="$1" blinded="$2"
  [ -z "$p" ] && return 0
  case "$p" in "$blinded"|"$blinded"/*) return 0 ;; esac
  case "$blinded" in "$p"/*) return 0 ;; esac
  return 1
}

# --- v7.4.2: a path token the SHELL will rewrite before the command sees it ---
# Every comparison above is on the text of a token. The shell expands a token
# first: `.apd/pipe*/spec-card.md`, `.apd/pipelin[e]/…`, `.apd/{pipeline,x}/…`,
# `.ap\d/pipeline/…` and `.apd/pipe${x}line/…` all name the spec card and none
# of them contains the string `.apd/pipeline` (measured on v7.4.1: exit 0 for
# each). `_gtok` reduces a token to a glob — quotes and backslashes removed, a
# brace group and a `$…` expansion each replaced by `*` (anything, the empty
# string included) — and `_glob_reaches` asks whether that glob can match a
# blinded directory, something inside it, or an ancestor of it.
_gtok() {
  local p="$1" pre rest
  p="${p##*[<>]}"                                   # a redirection target: `3<.a*/p*/s*`, `<.apd/pipe*`
  p="${p//[;&|()]/}"
  p="${p//\"/}"; p="${p//\'/}"; p="${p//\\/}"
  case "$p" in [A-Za-z_]*=*) pre="${p%%=*}"; case "$pre" in *[!A-Za-z0-9_]*) ;; *) p="${p#*=}" ;; esac ;; esac   # NAME=value, --opt=value: the value
  case "$p" in --*=*) p="${p#*=}" ;; esac
  # brace groups, innermost first — `{pipe{l,m}ine,x}` is one group, not two halves
  while :; do
    case "$p" in *'{'*'}'*) rest=$(printf '%s' "$p" | sed "s/{[^{}]*}/$_ANY/g"); [ "$rest" = "$p" ] && break; p="$rest" ;; *) break ;; esac
  done
  p="${p//\`/$_ANY}"                                 # a backtick substitution glued to the token: `echo .apd`/pipeline
  case "$p" in *'$'*) p=$(printf '%s' "$p" | sed "s/\\\$[A-Za-z0-9_*@#?!:.-]*/$_ANY/g") ;; esac
  printf '%s' "$p"
}
# _brace_alts <token> → the words the shell's brace expansion makes of it, one
# per line: `{.apd,.claude}/*/*` is two paths, each with its literal text —
# collapsed to one wildcard the dot-names inside the group were lost (audit pass
# 11). Innermost group first; a range (`{a..z}`) or more than 24 words fall back
# to the wildcard; `{x}` and `${var}` have no comma and keep their text.
_brace_alts() {
  local list="$1" out item pre grp post rest alt changed n
  while :; do
    changed=false; out=""; n=0
    while IFS= read -r item; do
      [ -n "$item" ] || continue
      case "$item" in
        *'{'*'}'*)
          pre="${item%%\}*}"; post="${item#*\}}"; grp="${pre##*\{}"
          case "$pre" in *'{'*) pre="${pre%\{*}" ;; *) out="$out$item"$'\n'; n=$((n + 1)); continue ;; esac   # a `}` with no `{` before it
          changed=true
          case "$grp" in
            *..*|'') out="$out$pre$_ANY$post"$'\n'; n=$((n + 1)) ;;
            *,*)  rest="$grp,"
                  while [ -n "$rest" ]; do alt="${rest%%,*}"; rest="${rest#*,}"; out="$out$pre$alt$post"$'\n'; n=$((n + 1)); done ;;
            *)    out="$out$pre$grp$post"$'\n'; n=$((n + 1)) ;;
          esac ;;
        *) out="$out$item"$'\n'; n=$((n + 1)) ;;
      esac
    done <<< "$list"
    list="${out%$'\n'}"
    [ "$n" -gt 24 ] && { printf '%s\n' "$1"; return 0; }      # too many: the caller's _gtok turns each group into _ANY
    [ "$changed" = true ] || break
  done
  printf '%s\n' "$list"
}
# `_ANY` stands for text only the shell knows — a `$…` expansion, a brace group,
# a backtick substitution. Unlike `*` it can be a name that begins with a dot
# (`d=.apd; cat $d/pipeline/…`, `{.apd,x}/pipeline/…` were not matched while
# these were plain `*`: audit pass 9), so the leading-dot rule does not apply to
# a component that carries one.
_ANY=$'\x01'
# One path component against one name, as the shell's pathname expansion does it:
# a pattern that begins with a wildcard does not match a name that begins with a dot.
# Only a component that BEGINS with `_ANY` is exempt — there the expansion can
# supply the dot (`${d}apd`, `{.,x}apd`); `*.{go,py}` still begins with a wildcard.
_comp_match() {
  local pat="$1" name="$2"
  case "$name" in .*) case "$pat" in '*'*|'?'*|'['*) return 1 ;; esac ;; esac   # judged BEFORE `_ANY` becomes `*`
  pat="${pat//$_ANY/*}"
  # shellcheck disable=SC2254
  case "$name" in $pat) return 0 ;; esac
  return 1
}
# Can glob <token> match <blinded>? Sets _GR to
#   full  the token can name the blinded directory or something inside it
#   anc   the token can name an ANCESTOR of it (`.a*`, `.*`) and stops there
#   ''    neither
# The components are tried at every offset for a FULL match (the token may be
# absolute, or relative to another directory: `cd src && cat ../.apd/pipe*/x`);
# an ancestor counts only at offset 0 — `src/*.{go,py}` is not `.apd`.
# A match proves something only if a matched component carries literal text:
# `"$f"`, `"$a/$b"` and `$dir/*` are the reviewer's own loops, not a path to
# pipeline state (audit pass 10).
_glob_reaches() {
  local tok="$1" b="$2" c k j n np nb ok lit t
  local -a P B
  local IFS=/
  _GR=""
  set -f
  for c in $tok; do case "$c" in ''|.) ;; *) P[${#P[@]}]="$c" ;; esac; done
  for c in $b;   do case "$c" in ''|.) ;; *) B[${#B[@]}]="$c" ;; esac; done
  set +f
  np=${#P[@]}; nb=${#B[@]}
  [ "$np" -gt 0 ] && [ "$nb" -gt 0 ] || return 1
  for ((k = 0; k < np; k++)); do
    ok=1; lit=0; n=$((np - k)); [ "$n" -gt "$nb" ] && n=$nb
    for ((j = 0; j < n; j++)); do
      c="${P[$((k + j))]}"
      _comp_match "$c" "${B[$j]}" || { ok=0; break; }
      t="${c//$_ANY/}"; t="${t//[*?]/}"; t="${t//[][]/}"
      [ -n "$t" ] && lit=1
    done
    [ "$ok" = 1 ] && [ "$lit" = 1 ] || continue
    if [ "$n" -eq "$nb" ]; then _GR=full; return 0; fi
    if [ "$k" -eq 0 ]; then _GR=anc; return 0; fi
  done
  return 1
}
# <token> is an abbreviation git would accept for long option <full> (git takes
# any unambiguous prefix), at least <min> characters long.
_abbr() {
  [ "${#1}" -ge "$3" ] || return 1
  case "$2" in "$1"*) return 0 ;; esac
  return 1
}

# --- Channel 1: Read / Glob / Grep target ----------------------------------
# A Grep or Glob with NO path searches the whole project, so it reaches blinded
# content while carrying nothing for a path matcher to match. That is not an
# evasion, it is the tool's default form — and it is also outside this role's
# contract, which is to read the files `.reviewed-files` lists and nothing else.
if [ -z "$FILE_PATH" ] && [ -z "$COMMAND" ]; then
  case "$TOOL" in
    Grep|Glob) _deny "the whole project (a $TOOL with no path)" "tool:$TOOL:nopath" ;;
  esac
fi

if [ -n "$FILE_PATH" ]; then
  REL=$(_norm "$(_rel_path "$FILE_PATH")")

  # Unresolved traversal means the prefix comparison below cannot be trusted.
  # Fail closed: an unverifiable path is never allowed through.
  case "/$REL/" in
    */../*|*/..|../*) _deny "a path with unresolved traversal ($REL)" "$REL" ;;
  esac

  if [ "$REL" != "$PIPE_REL/$ALLOWED_BASENAME" ]; then
    _reaches "$REL" "$PIPE_REL" && _deny "pipeline state (${REL:-the project root})" "${REL:-.}"
    _reaches "$REL" "$MEM_REL"  && _deny "project memory (${REL:-the project root})" "${REL:-.}"
  fi
fi

# --- Channel 2: Bash command -----------------------------------------------
# v7.2.3 (live, efiskalizacija ×3 + audit S1–S4): two passes.
#   1. NAMED blinded paths over the RAW text — heredoc bodies included, because an
#      interpreter RUNS its body (`python3 <<EOF … open(".apd/pipeline/spec-card.md")`).
#   2. The ANCESTOR rule (a bare `.` = the project root; `.apd` reaches the pipeline
#      dir) over the TOKENIZED statements guard-bash-scope emits (`--emit-words`:
#      wrappers, assignments and keywords stepped, nested shells and substitutions
#      as their own statements, heredoc bodies as data). The root counts only as the
#      argument of a recursive READER — `grep -c .` is a regex, the PHP `.` concat
#      operator in a heredoc body is data; `env find .`, `sudo find .`, `FOO=1 find .`,
#      `echo x;find .`, `wc -l $(find . …)`, a `find .` on the next line are reads.
#      If the tokenizer cannot read the command (OPAQUE, no END), the pre-v7.2.3 rule
#      applies: any bare `.` token denies (fail closed).
if [ -n "$COMMAND" ]; then
  for bc in "${BLIND_COMMANDS[@]}"; do
    if [[ "$COMMAND" == *"$bc"* ]]; then
      _deny "pipeline state via \`$bc\`" "cmd:$bc"
    fi
  done

  # git is exempt from the ANCESTOR rule (not from named blinded paths): the
  # pipeline directory is gitignored, so `git diff .` cannot surface its content,
  # and that is the role's most legitimate command.
  _CMD_HEAD="${COMMAND%% *}"; _CMD_HEAD="${_CMD_HEAD##*/}"

  # The tokenized statements (used by pass 2) are computed first: pass 1 needs
  # to know whether the command could be read at all.
  _GBS="$(dirname "$0")/guard-bash-scope"
  _WORDS=$(APD_GBS_DEPTH=0 bash "$_GBS" --emit-words --command "$COMMAND" 2>/dev/null || printf 'OPAQUE\n')
  _OPAQUE=true
  if [ "$(printf '%s\n' "$_WORDS" | tail -n 1)" = END ] && ! printf '%s\n' "$_WORDS" | grep -qx 'OPAQUE'; then _OPAQUE=false; fi

  # --- pass 1: named paths, raw text, bodies included --------------------------
  # Three kinds of word never reach pass 2 as an argument (measured on the
  # tokenizer, audit pass 11): the target of a redirection written after a
  # space (`done < .a*/p*/s*`), the list of a `for`/`select` loop
  # (`for f in .a*/p*/*`), and whatever follows a process substitution on the
  # same command (`cat <(echo x) .a*/p*/s*`). They are judged here, as paths.
  _ctx_redir=false; _ctx_for=0; _ctx_procsub=false
  case "$COMMAND" in *'<('*|*'>('*) _ctx_procsub=true ;; esac
  set -f
  for raw in $COMMAND; do
    _was_redir=$_ctx_redir; _ctx_redir=false
    case "$raw" in '<'|'>'|'>>'|'<<<'|'<>'|[0-9]'<'|[0-9]'>'|[0-9]'>>'|'&>'|'&>>'|*'$(<') _ctx_redir=true ;; esac
    _in_list=false
    case "$_ctx_for:$raw" in
      0:for|0:select|0:*';for'|0:*';select') _ctx_for=1 ;;
      1:*) _ctx_for=2 ;;                                   # the loop variable
      2:in) _ctx_for=3 ;;
      2:*) _ctx_for=0 ;;                                   # `for ((…))` or a list-less form
      3:do|3:*';'*) case "$raw" in do) ;; *) _in_list=true ;; esac; _ctx_for=0 ;;
      3:*) _in_list=true ;;
    esac
    tok="${raw//[;&|()<>]/}"
    [ -z "$tok" ] && continue
    # A blinded path can ride INSIDE a token that is not a path at all —
    # `git show HEAD:.apd/pipeline/spec-card.md` is the shipped example.
    _plain="${tok//\"/}"; _plain="${_plain//\'/}"
    case "$_plain" in
      *"$PIPE_REL/$ALLOWED_BASENAME") : ;;                   # the review scope — allowed
      *"$PIPE_REL"*) set +f; _deny "pipeline state ($_plain)" "cmd:$_plain" ;;
      *"$MEM_REL"*)  set +f; _deny "project memory ($_plain)" "cmd:$_plain" ;;
    esac
    # v7.4.2 — what the shell makes of the token (see _gtok): the literal test
    # again on the unescaped text, then the glob test.
    _g=$(_gtok "$raw")
    case "$_g" in
      *"$PIPE_REL/$ALLOWED_BASENAME") : ;;
      *"$PIPE_REL"*) set +f; _deny "pipeline state ($_plain)" "cmd:$_plain" ;;
      *"$MEM_REL"*)  set +f; _deny "project memory ($_plain)" "cmd:$_plain" ;;
    esac
    # The glob test belongs to pass 2, where the command is known (a grep
    # pattern `.*/pipeline`, a `find -name '.*'` value or an awk program is not
    # a path — audit pass 10). Here it runs only for what pass 2 does not see:
    # a redirection target, and every token of a command that could not be
    # tokenized (fail closed).
    case "$raw" in *'<'*|*'>'*) _pg=true ;; *) _pg=$_OPAQUE ;; esac
    [ "$_was_redir" = true ] && _pg=true
    [ "$_in_list" = true ] && _pg=true
    [ "$_ctx_procsub" = true ] && _pg=true
    # a loop list or a redirection target that NAMES an ancestor of the blinded
    # directories (`for d in .apd .claude; do cat $d/*/*; done`) — pass 2 never
    # sees the word, so the ancestor rule is applied to it here
    if [ "$_in_list" = true ] || [ "$_was_redir" = true ]; then
      _lt=$(_norm "$_g")
      if [ -n "$_lt" ] && [ "$_lt" != "$PIPE_REL/$ALLOWED_BASENAME" ] && { _reaches "$_lt" "$PIPE_REL" || _reaches "$_lt" "$MEM_REL"; }; then
        set +f; _deny "a directory that contains pipeline state ($_plain, in a loop list or a redirection)" "cmd:$_plain"
      fi
    fi
    if [ "$_pg" = true ]; then
      case "$_g" in
        *[*?[]*|*"$_ANY"*)
          _gn=$(_norm "$_g")
          if _glob_reaches "$_gn" "$PIPE_REL" || _glob_reaches "$_gn" "$MEM_REL"; then
            set +f; _deny "pipeline state or project memory (a pattern that can match it: $_plain)" "cmd:$_plain"
          fi ;;
      esac
    fi
    # v7.4.2 — shell settings that change what a glob matches (`shopt -s dotglob`
    # makes `*/pipeline/spec-card.md` match `.apd`; `GLOBIGNORE` and zsh `globdots`
    # do the same, `extglob` adds `+(…)`/`@(…)` forms this guard does not read),
    # and GREP_OPTIONS, which makes a plain grep recursive.
    # As an ASSIGNMENT anywhere, or as any word of a command that could not be
    # tokenized; `shopt -s dotglob` and `bash -O extglob` are judged in pass 2,
    # so that `grep -n extglob src/x.sh` is a search and not a setting.
    case "$_plain" in
      GLOBIGNORE=*|GREP_OPTIONS=*)
        set +f; _deny "pipeline state (a shell or grep setting that widens what a pattern reads: $_plain)" "cmd:$_plain" ;;
      *dotglob*|*globdots*|*GLOBDOTS*|*extglob*)
        [ "$_OPAQUE" = true ] && { set +f; _deny "pipeline state (a shell or grep setting, in a command that could not be tokenized: $_plain)" "cmd:$_plain"; } ;;
    esac
    # v7.4.2 — options that make git read the WORKING TREE instead of the index:
    # `git grep --no-index` / `--untracked` / `--no-exclude-standard` and
    # `git diff --no-index` read every file under the current directory, ignored
    # ones included — the spec card and the rationale — without naming one
    # (measured on v7.3.2 and v7.4.1: exit 0, and the spec card in the output).
    # git accepts any unambiguous prefix of a long option.
    _o="${_plain%%=*}"; _o="${_o//\\/}"
    if _abbr "$_o" "--no-index" 7 || _abbr "$_o" "--untracked" 5 || _abbr "$_o" "--no-exclude-standard" 8; then
      set +f; _deny "files git does not track (\`$_o\` reads the working tree past the index, pipeline state included)" "cmd:$_o"
    fi
    tok=$(_norm "$tok")
    case "$tok" in *[*?[]*) tok="${tok%%[*?[]*}"; tok="${tok%/}" ;; esac
    [ -z "$tok" ] && continue                                 # the root is judged in pass 2
    [ "$tok" = "$PIPE_REL/$ALLOWED_BASENAME" ] && continue
    case "$tok" in
      "$PIPE_REL"|"$PIPE_REL"/*|"$MEM_REL"|"$MEM_REL"/*) set +f; _deny "pipeline state or project memory ($tok)" "cmd:$tok" ;;
    esac
  done
  set +f

  # --- pass 2: the ancestor rule over tokenized statements ---------------------
  _US=$'\x1f'
  _is_reader() {  # <cmd> <args…> — does this statement read a directory tree it is handed?
    local c="$1"; shift; local a
    case "$c" in
      find|fd|fdfind|bfs|gfind|ls|gls|eza|exa|lsd|tree|du|gdu|cat|head|tail|less|more|diff|cp|gcp|rsync|tar|gtar|zip|7z|7za|unzip|xargs|stat|file|wc|sort|awk|gawk|sed|gsed|python|python3|node|php|ruby|perl|rg|ag|ack|ack-grep|sift|pt|ucg|rgrep|ditto) return 0 ;;   # rg/ag/ack recurse by default
      grep|egrep|fgrep|ggrep|ugrep|ug|zgrep|bzgrep|xzgrep|zegrep|zfgrep|pcregrep|pcre2grep)
        for a in "$@"; do
          case "$a" in recurse|--di*=r*|--rec*|--deref*) return 0 ;; esac   # `-d recurse`, `--directories recurse`, `--dir=recurse`
          case "$a" in
            -r|-R|--recursive|--dereference-recursive|-d|--directories=recurse|-rn|-nr|-rl|-lr|-ri|-ir|-rni|-rin|-nri|-nir|-Rn|-nR) return 0 ;;
            --*) ;;
            -*[rR]*) return 0 ;;   # a short cluster carrying r or R (-rn, -Hrn, -nrw)
          esac
        done; return 1 ;;
    esac
    return 1
  }
  # v7.4.2 — `git add` (and `git stage`): staging is how an ignored or untracked
  # file reaches `git diff --cached` (`git add -f .` puts the spec card there),
  # and this role reads — it has nothing to stage.
  _judge_git() {
    local a sub=""
    while [ $# -gt 0 ]; do
      a="$1"; shift
      case "$a" in
        -c) case "${1:-}" in alias.*|"'alias."*|'"alias.'*) _deny "the index or the working tree (a git alias defined on the command line can run anything: ${1:-})" "cmd:git-alias" ;; esac
            [ $# -gt 0 ] && shift ;;
        -C|--git-dir|--work-tree|--namespace|--super-prefix|--config-env) [ $# -gt 0 ] && shift ;;
        -*) ;;
        *) sub="$a"; break ;;
      esac
    done
    case "$sub" in
      add|stage) _deny "the index (git $sub stages files — ignored ones with -f — for \`git diff --cached\`; this role reads, it does not stage)" "cmd:git-$sub" ;;
      '$'*|'`'*) _deny "the index or the working tree (the git subcommand is text only the shell knows: $sub)" "cmd:git-subst" ;;
      config) for a in "$@"; do case "$a" in alias.*) _deny "the index or the working tree (defining a git alias: $a)" "cmd:git-alias" ;; esac; done ;;
      update-index) for a in "$@"; do case "$a" in --add|--index-info|--stdin) _deny "the index (git update-index $a puts files into it, ignored ones included)" "cmd:git-update-index" ;; esac; done ;;
      ls-files)   # -o without --exclude-standard, or -i, lists the IGNORED files — the pipeline state — ready for `xargs cat`
        local _o=false _std=false
        for a in "$@"; do
          case "$a" in
            -o|--others) _o=true ;;
            --exclude-standard) _std=true ;;
            --*) if _abbr "$a" "--ignored" 4; then _deny "the names of ignored files (git ls-files $a)" "cmd:git-ls-files-ignored"; fi
                 if _abbr "$a" "--others" 3; then _o=true; fi
                 if _abbr "$a" "--exclude-standard" 12; then _std=true; fi ;;
            -*i*) _deny "the names of ignored files (git ls-files $a lists pipeline state for a reader down the pipe)" "cmd:git-ls-files-ignored" ;;
            -*o*) _o=true ;;
          esac
        done
        [ "$_o" = true ] && [ "$_std" = false ] && _deny "the names of ignored files (git ls-files --others without --exclude-standard lists pipeline state)" "cmd:git-ls-files-others" ;;
    esac
    return 0
  }
  # v7.4.2 — a recursive reader with NO path operand reads the current directory:
  # `grep -rn foo`, `rg foo`, `find -name x`, `ls -R`, `tree`. Nothing in such a
  # command is a path for the rules above to match, and it reaches the pipeline
  # and memory directories all the same (grep -r does not care what git ignores).
  # The same rule the Grep and Glob tools have had since v7.0: name a path.
  _reads_cwd() {  # <cmd> <args…>
    local c="$1"; shift
    local a n=0 skip=false haspat=false rec=false
    case "$c" in
      find|gfind|bfs)
        while [ $# -gt 0 ]; do case "$1" in -H|-L|-P|-O*) shift ;; -D) shift; [ $# -gt 0 ] && shift ;; *) break ;; esac; done
        case "${1:-}" in ''|-*|'('|'!'|'\(') return 0 ;; esac
        return 1 ;;
      tree|du|gdu)
        for a in "$@"; do
          if [ "$skip" = true ]; then skip=false; continue; fi
          case "$a" in -L|-P|-I|-o|-d|--max-depth|--exclude|-B|--block-size|--threshold|-t|--filelimit|--charset|--sort|--timefmt) skip=true ;; -*) ;; *) n=$((n + 1)) ;; esac
        done
        [ "$n" = 0 ] && return 0; return 1 ;;
      ls|gls|eza|exa|lsd)
        for a in "$@"; do
          case "$a" in --recursive|--tree) rec=true ;; --*) ;; -*R*) rec=true ;; -*) ;; *) n=$((n + 1)) ;; esac
        done
        [ "$rec" = true ] && [ "$n" = 0 ] && return 0; return 1 ;;
      fd|fdfind)
        for a in "$@"; do
          if [ "$skip" = true ]; then skip=false; continue; fi
          case "$a" in
            --search-path|--base-directory|--search-path=*|--base-directory=*) return 1 ;;
            -e|-E|-t|-d|-x|-X|-j|-c|-S|-o|--extension|--exclude|--type|--max-depth|--min-depth|--exact-depth|--exec|--exec-batch|--color|--size|--changed-within|--changed-before|--owner|--threads|--max-results|--batch-size|--ignore-file|--path-separator|--format) skip=true ;;
            -*) ;;
            *) n=$((n + 1)) ;;
          esac
        done
        [ "$n" -lt 2 ] && return 0; return 1 ;;
      rgrep) n=0; for a in "$@"; do case "$a" in -*) ;; *) n=$((n + 1)) ;; esac; done; [ "$n" -le 1 ] && return 0; return 1 ;;   # always recursive: pattern + paths
      grep|egrep|fgrep|ggrep|ugrep|ug|zgrep|bzgrep|xzgrep|zegrep|zfgrep|pcregrep|pcre2grep)
        for a in "$@"; do
          if [ "$skip" = true ]; then skip=false; continue; fi
          case "$a" in
            -e|-f|--regexp|--file) haspat=true; skip=true ;;
            --regexp=*|--file=*) haspat=true ;;
            -m|-A|-B|-C|-D|--include|--exclude|--exclude-dir|--exclude-from|--max-count|--after-context|--before-context|--context|--label|--devices|--binary-files|--directories) skip=true ;;
            -d) skip=true ;;                                   # its value is judged below
            -r|-R|--recursive|--dereference-recursive|--directories=recurse) rec=true ;;
            --di*=r*|--rec*|--deref*) rec=true ;;               # `--dir=recurse`, `--directories=rec`, `--recurs`: GNU grep takes prefixes
            --di*) skip=true ;;                                # `--dir recurse`: its value is judged by the `recurse` scan below
            --*) ;;
            -*[ef]) haspat=true; skip=true; case "$a" in -*[rR]*) rec=true ;; esac ;;   # a cluster ending in -e/-f takes the pattern as its value
            -*[rR]*) rec=true ;;
            -*) ;;
            *) n=$((n + 1)) ;;
          esac
        done
        [ "$rec" = true ] || { for a in "$@"; do case "$a" in rec|recu|recur|recurs|recurse) rec=true ;; esac; done; }   # `-d recurse`, `--directories rec`
        [ "$rec" = true ] || return 1
        [ "$haspat" = true ] || n=$((n - 1))                   # the first operand is the pattern
        [ "$n" -le 0 ] && return 0; return 1 ;;
      rg|ag|ack|ack-grep|sift|pt|ucg)
        for a in "$@"; do
          if [ "$skip" = true ]; then skip=false; continue; fi
          case "$a" in
            --files|--type-list) haspat=true ;;                # no pattern operand in these modes
            -e|-f|--regexp|--file) haspat=true; skip=true ;;
            --regexp=*|--file=*) haspat=true ;;
            -g|-t|-T|-A|-B|-C|-m|-j|-M|-E|-r|-d|-G|--glob|--iglob|--type|--type-not|--type-add|--type-clear|--max-count|--context|--after-context|--before-context|--max-depth|--depth|--threads|--encoding|--sort|--sortr|--color|--colors|--replace|--max-columns|--max-filesize|--pre|--pre-glob|--engine|--field-match-separator|--field-context-separator|--path-separator|--ignore-file|--context-separator|--dfa-size-limit|--regex-size-limit|--ignore|--ignore-dir|--file-search-regex|--pager|--workers|--ackrc|--match) skip=true ;;
            -*) ;;
            *) n=$((n + 1)) ;;
          esac
        done
        [ "$haspat" = true ] || n=$((n - 1))
        [ "$n" -le 0 ] && return 0; return 1 ;;
    esac
    return 1
  }
  # v7.4.2 — the glob test, on the arguments that are PATHS. A grep/rg pattern,
  # the value of an option that takes a pattern or a glob (`-e`, `--include`,
  # `-g`, find's `-name`/`-path`/`-regex`) and the program of awk/sed/jq/an
  # interpreter are text for that tool, not for the shell's pathname expansion
  # as far as this rule can tell — judging them refused `grep -rn '.*' src` and
  # `find src -name '.*'`.
  _judge_globs() {  # <reader true|false> <cmd> <args…>
    local reader="$1" c="$2"; shift 2
    local a b cand skip=0 first=true hasprog=false forced=false g gn gsub=""
    # does the tool get its pattern / program from an option (then every operand is a path)?
    for a in "$@"; do
      case "$c:$a" in
        *:-e|*:-f|*:--regexp|*:--file|*:--regexp=*|*:--file=*|*:--from-file|*:--from-file=*) hasprog=true ;;
      esac
    done
    for a in "$@"; do
      if [ "$skip" -gt 0 ]; then skip=$((skip - 1)); continue; fi
      case "$c" in
        grep|egrep|fgrep|ggrep|ugrep|ug|zgrep|bzgrep|xzgrep|zegrep|zfgrep|pcregrep|pcre2grep|rgrep|rg|ag|ack|ack-grep|sift|pt|ucg)
          case "$a" in
            -e|-f|--regexp|--file|-g|-t|-T|-m|-A|-B|-C|-D|-d|-j|-M|-E|-G|--glob|--iglob|--type|--type-not|--type-add|--include|--exclude|--exclude-dir|--exclude-from|--max-count|--after-context|--before-context|--context|--label|--devices|--binary-files|--directories|--max-depth|--replace|--pre|--pre-glob|--ignore-file|--ignore|--ignore-dir|--file-search-regex|--match|--color|--colors|--sort|--sortr|--encoding|--threads) skip=1; continue ;;
            --regexp=*|--include=*|--exclude=*|--exclude-dir=*|--glob=*|--iglob=*|--file-search-regex=*|--match=*) continue ;;
            -*) continue ;;
          esac
          if [ "$hasprog" = false ] && [ "$first" = true ]; then first=false; continue; fi   # the pattern operand
          ;;
        find|gfind|bfs)
          case "$a" in -name|-iname|-path|-ipath|-wholename|-iwholename|-regex|-iregex|-lname|-ilname|-printf|-fprintf|-user|-group|-perm|-size|-mtime|-mmin|-type|-maxdepth|-mindepth) skip=1; continue ;; esac ;;
        fd|fdfind)
          case "$a" in -e|-E|-t|-d|-x|-X|-g|--extension|--exclude|--type|--max-depth|--glob) skip=1; continue ;; -*) continue ;; esac
          if [ "$first" = true ]; then first=false; continue; fi ;;                          # the pattern operand
        python|python2|python3|node|nodejs|php)
          case "$a" in -c|-e|-r|-p|-m|--eval|--print|-W|-X) skip=1; continue ;; -*) continue ;; esac ;;
        jq|yq)
          case "$a" in
            -f|--from-file|--indent) skip=1; continue ;;
            --arg|--argjson) skip=2; continue ;;
            --slurpfile|--rawfile) skip=1; forced=true; continue ;;                           # the name; the file after it is a path
            -*) continue ;;
          esac
          if [ "$forced" = true ]; then forced=false                                           # … judged, never taken for the filter
          elif [ "$hasprog" = false ] && [ "$first" = true ]; then first=false; continue; fi ;;   # the filter
        git)   # pattern-valued options and the pattern operand of `git grep` are not paths
          case "$a" in
            -C|-c|--git-dir|--work-tree|--namespace|--grep|-G|-S|--author|--committer|--format|--pretty|-m|--message|-L|--since|--until|--date) skip=1; continue ;;
            -e) skip=1; continue ;;
            --grep=*|--author=*|--committer=*|--format=*|--pretty=*|--since=*|--until=*|-G?*|-S?*) continue ;;
            -*) ;;
            *) if [ -z "$gsub" ]; then gsub="$a"; continue; fi
               if [ "$gsub" = grep ] && [ "$hasprog" = false ] && [ "$first" = true ]; then first=false; continue; fi ;;
          esac ;;
      esac
      while IFS= read -r cand; do
        [ -n "$cand" ] || continue
        g=$(_gtok "$cand")
        case "$g" in
          *"$PIPE_REL/$ALLOWED_BASENAME") continue ;;
          *"$PIPE_REL"*|*"$MEM_REL"*) _deny "pipeline state or project memory ($a)" "cmd:$a" ;;
        esac
        case "$g" in
          *[*?[]*|*"$_ANY"*)
            gn=$(_norm "$g")
            for b in "$PIPE_REL" "$MEM_REL"; do
              _glob_reaches "$gn" "$b"
              case "$_GR" in
                full) _deny "pipeline state or project memory (a pattern that can match it: $a)" "cmd:$a" ;;
                anc)  case "$reader:$c" in true:*|*:cd|*:pushd) _deny "a directory that contains pipeline state (a pattern that can match it: $a)" "cmd:$a" ;; esac ;;
              esac
            done ;;
        esac
      done <<< "$(_brace_alts "$a")"
    done
    return 0
  }
  # v7.4.2 — a shell told to match dot names with a plain `*` (`shopt -s dotglob`,
  # `setopt globdots`, `bash -O dotglob`), or to read `+(…)` forms (`extglob`)
  _judge_shell_settings() {  # <cmd> <args…>
    local c="$1"; shift; local a
    case "$c" in
      shopt|setopt|set) for a in "$@"; do case "$a" in dotglob|globdots|GLOB_DOTS|GLOBDOTS|glob_dots|extglob|extendedglob|EXTENDED_GLOB|kshglob) _deny "pipeline state (a shell setting that widens what a pattern matches: $c $a)" "cmd:$c-$a" ;; esac; done ;;
      bash|zsh|sh|ksh|dash) for a in "$@"; do case "$a" in dotglob|globdots|extglob|extendedglob|GLOB_DOTS) _deny "pipeline state (a shell started with a setting that widens what a pattern matches: $a)" "cmd:$c-$a" ;; esac; done ;;
    esac
    return 0
  }
  _raw_has_dot() {  # does the RAW command carry a bare `.`/`./` token anywhere? (fail-closed helper)
    local r2
    # (pass 3) a dot inside a list literal — `["find", ".", …]` — counts; `tr -d`, because a `]` inside a
    # `${var//[…]/}` bracket mis-parses on both bashes
    # v7.4.2: `set -f` — unquoted `$COMMAND` was pathname-expanded HERE, in the
    # hook's own directory, so `.*` became `. ..` under bash 3.2 (refused) and
    # `.apd .claude` under bash 5 (allowed): one command, two verdicts (audit
    # pass 11). A `*` is dropped with the other punctuation, so `.*` — the dot
    # names, `.` and `..` among them for half the shells — counts as a dot on both.
    set -f
    for r2 in $COMMAND; do case "$(printf '%s' "$r2" | tr -d '][{};&|()<>"'"'"',*')" in *[!./]*) ;; "") ;; *) set +f; return 0 ;; esac; done
    set +f
    return 1
  }
  _judge_stmt() {  # <cmd> <args…>
    local c="$1"; shift; local a t
    [ -z "$c" ] && return 0
    case "$c" in git) _judge_git "$@"; _judge_globs false git "$@"; return 0 ;; esac   # git exempt from the ancestor rule (not from named paths); v7.4.2: not from `git add`, nor from a glob that names pipeline state (`git diff /dev/null .a*/p*/s*` reads it)
    # (pass 3) a substitution in COMMAND position (`$(which find) .`) or a dot as the command word
    # (`. file` sources; `W␟.␟-name` is what `$(echo find) . -name …` leaves) — the real command is
    # invisible, so fail closed on any bare dot in the command
    case "$c" in
      '$'|'$'*)   # a substitution in COMMAND position (`$(which grep) -r x .`): the real command is its output;
                  # the words after it arrive as a statement of their own — fail closed on any bare dot
                  # (a bare `$` inside a DATA substitution arrives as an N line and is skipped by the caller)
                _raw_has_dot && _deny "a directory that contains pipeline state (the project root, behind a substitution)" "cmd:."; return 0 ;;
      '`'*|.)   _raw_has_dot && _deny "a directory that contains pipeline state (the project root, behind a substitution)" "cmd:."; return 0 ;;   # `which find` . / `. -name` left by $(echo find) .
    esac
    while :; do case "$c" in -a) shift; [ $# -gt 0 ] || return 0; c="$1"; shift ;; -*) [ $# -gt 0 ] || return 0; c="$1"; shift ;; *) break ;; esac; done   # `command -p find .`, `exec -a NAME find .`: the stepped wrapper left its option (and -a's value) as the command word
    _judge_shell_settings "$c" "$@"
    _reads_cwd "$c" "$@" && _deny "the whole project (a recursive $c with no path reads the current directory, pipeline state and memory included — name the path)" "cmd:$c:nopath"
    local reader=false; _is_reader "$c" "$@" && reader=true
    # (pass 2/3) a wrapper or runner the tokenizer does not step hands its arguments to the real
    # command — which word that is cannot be told here, so the whole statement counts as a reader,
    # and an argument that is itself a command line (`watch "find . -name x"`, `ssh h "…"`) is judged as one
    case "$c" in
      stdbuf|setsid|unbuffer|flock|script|watch|busybox|chrt|taskset|strace|ltrace|nohup|command|exec|time|env|nice|ionice|sudo|doas|caffeinate|timeout|hyperfine|parallel|ssh|perf|valgrind|gdb|docker|podman|make|npx|npm|pnpm|yarn|composer|bundle|poetry|uv|pipx|cargo|go|dotnet|mvn|gradle)
        reader=true
        for a in "$@"; do
          case "$a" in *[[:space:]]*) _judge_text "$a" ;; esac
          case "$a" in sh|bash|zsh|dash|ksh) [ "$_HD_BODIES_JUDGED" != true ] && case "$COMMAND" in *'<<'*) _HD_BODIES_JUDGED=true; _judge_text "$_HD_BODIES" ;; esac ;; esac   # `cat <<EOF | script -q /dev/null sh`
        done ;;
    esac
    case "$c" in
      xargs)   # the targets come from stdin (`echo . | xargs find`, `… | xargs -I{} sh -c "find {}"`): fail closed on any bare dot
        _raw_has_dot && _deny "a directory that contains pipeline state (the project root, through xargs)" "cmd:." ;;
      sh|bash|zsh|dash|ksh|source)   # a heredoc piped into a shell runs its body (`cat <<EOF | sh`, `sh -s -- x`, `source /dev/stdin`): judge the bodies as statements
        local _hasc=false _pos=false _stdin=false
        for a in "$@"; do case "$a" in -c) _hasc=true ;; -s) _stdin=true ;; -*) ;; /dev/stdin|-) _stdin=true ;; *) _pos=true ;; esac; done
        if { [ "$_stdin" = true ] || { [ "$_hasc" = false ] && [ "$_pos" = false ]; }; } && [ "$_HD_BODIES_JUDGED" != true ]; then
          case "$COMMAND" in *'<<'*) _HD_BODIES_JUDGED=true; _judge_text "$_HD_BODIES" ;; esac
        fi
        if [ "$_hasc" = true ]; then for a in "$@"; do case "$a" in *'$('*|*'`'*|'$') _raw_has_dot && _deny "a directory that contains pipeline state (the project root, through a shell fed a substitution)" "cmd:." ;; esac; done; fi ;;
      python|python2|python3|node|nodejs|php|ruby|perl|awk|gawk)   # (pass 3/4) a program that shells out runs whatever it names: deny when a
        # shell-out call carries a READER word and a bare dot in the same call (`os.system('find . -name x')`,
        # `subprocess.run(["find", ".", …])`) — `subprocess.run(['pytest', '.'])` and `os.system('echo .')` are not reads
        # (quotes, brackets and commas become spaces first — a backslash or a `]` inside an ERE bracket
        # expression mis-parses on both greps)
        _flat=$(printf '%s' "$COMMAND" | tr '\n"\047[](){},' '           ')   # \047 = apostrophe (tr knows octal, not \xHH)
        # v7.4.2 (audit pass 9) — a program that WALKS the tree itself needs no shell-out:
        # `os.walk('.')`, `Path('.').rglob('*')`, `glob.glob('**/*', recursive=True)`,
        # `fs.readdirSync('.', {recursive: true})`, `Dir.glob("**/*", File::FNM_DOTMATCH)`
        if printf '%s' "$_flat" | grep -qE '(os\.walk|os\.fwalk|glob\.glob|glob\.iglob|scandir|listdir|readdirSync|readdir|opendir|Dir\.glob|Dir\.entries|Dir\.children|Find\.find|File::Find|RecursiveDirectoryIterator|\.rglob|\.glob|\.iterdir)[^;]* (\.|\./|\*\*[^ ]*)( |$)' \
           || printf '%s' "$_flat" | grep -qE ' (\.|\./) +\.(walk|rglob|glob|iterdir)' \
           || { printf '%s' "$_flat" | grep -qE '(getcwd|os\.curdir|Path\.cwd|Path  *\.|process\.cwd|Dir\.pwd|Dir\.getwd|cwd  *\.)' \
                && printf '%s' "$_flat" | grep -qE '(os\.walk|os\.fwalk|glob\.glob|glob\.iglob|scandir|listdir|readdirSync|readdir|opendir|Dir\.glob|Dir\.entries|Find\.find|File::Find|find *[^a-z]|\.rglob|\.glob|\.iterdir)'; }; then
          _deny "a directory that contains pipeline state (the project root, walked by a program)" "cmd:walk"
        fi
        if printf '%s' "$_flat" | grep -qE '(system|exec|popen|spawn|subprocess|run|shell_exec|passthru|child_process|Open3|proc_open|pexpect|delegator|invoke|qx|%x|`)[^;]* (find|fd|ls|tree|du|rg|ag|ack|grep|cat|head|tail|diff|cp|rsync|tar|zip)( [^;]*)? \.( |$)' \
           || printf '%s' "$_flat" | grep -qE ' (find|fd|ls|tree|du|rg|ag|ack|grep|cat|head|tail|diff|cp|rsync|tar|zip)( [^;]*)? \.( |$).*(system|exec|popen|spawn|subprocess|run|shell_exec|passthru|child_process|Open3|proc_open|pexpect|delegator|invoke|qx|%x|`)' \
           || printf '%s' "$_flat" | grep -qE ' (find|fd|ls|tree|du|rg|ag|ack|grep)( [^|]*)? \. [^|]*\| *getline'; then
          _deny "a directory that contains pipeline state (the project root, through a program that shells out)" "cmd:."
        fi ;;
      sed|gsed|vim|vi|nvim|ex|less|more)   # (pass 4) these run shell text through `e`/`:!`/`!`; a reader word and a bare dot in the raw command deny
        if printf '%s' "$COMMAND" | grep -qE '(^|[^A-Za-z0-9_])(find|fd|ls|tree|du|rg|ag|ack|grep)([^A-Za-z0-9_])' && _raw_has_dot; then
          _deny "a directory that contains pipeline state (the project root, through an editor or sed shell escape)" "cmd:."
        fi ;;
    esac
    _judge_globs "$reader" "$c" "$@"
    if [ "$reader" = true ]; then   # (pass 2) a reader whose argument is a substitution — `find $(echo .)` — reads whatever it yields
      # v7.4.2: … and `$(git rev-parse --show-toplevel)` yields the project root without a dot anywhere in the text
      for a in "$@"; do case "$a" in '$'|'$('*')'|'`'*'`') case "$COMMAND" in *--show-toplevel*|*--show-cdup*) _deny "a directory that contains pipeline state (the project root, through git rev-parse)" "cmd:toplevel" ;; esac ;; esac; done
      for a in "$@"; do case "$a" in '$'|*'$('*|*'`'*) _raw_has_dot && _deny "a directory that contains pipeline state (the project root, through a substitution)" "cmd:." ;; esac; done
    fi
    for a in "$@"; do
      a="${a//\"/}"; a="${a//\'/}"
      # v7.4.2 (audit pass 9) — an absolute or ~ operand is resolved: the project
      # root or one of its ancestors is the root (`grep -rn X /abs/project` read
      # everything while `grep -rn X .` was refused), a path inside the project
      # is judged by its project-relative form like any other.
      case "$a" in
        '~'|'~/'*) a="${HOME:-}${a#\~}" ;;
        # the working directory under its other names — taken as the project root
        # (`grep -rn X $PWD` and `rg X "$(pwd)"` read everything while `.` was refused)
        '$PWD'*)   a="$PROJ_CANON${a#\$PWD}" ;;
        '${PWD}'*) a="$PROJ_CANON${a#\$\{PWD\}}" ;;
        '$(pwd)'*) a="$PROJ_CANON${a#\$\(pwd\)}" ;;
        '`pwd`'*)  a="$PROJ_CANON${a#\`pwd\`}" ;;
        '$(git rev-parse --show-toplevel)'*) a="$PROJ_CANON${a#\$\(git rev-parse --show-toplevel\)}" ;;
        # … and under the names the harness and the shell give it (audit pass 10:
        # `grep -rn X "$CLAUDE_PROJECT_DIR"` is the nearest thing to a natural read left)
        '$CLAUDE_PROJECT_DIR'*)   a="$PROJ_CANON${a#\$CLAUDE_PROJECT_DIR}" ;;
        '${CLAUDE_PROJECT_DIR}'*) a="$PROJ_CANON${a#\$\{CLAUDE_PROJECT_DIR\}}" ;;
        '$APD_PROJECT_DIR'*)      a="$PROJ_CANON${a#\$APD_PROJECT_DIR}" ;;
        '${APD_PROJECT_DIR}'*)    a="$PROJ_CANON${a#\$\{APD_PROJECT_DIR\}}" ;;
        '$OLDPWD'*)               a="$PROJ_CANON${a#\$OLDPWD}" ;;
        '$INIT_CWD'*)             a="$PROJ_CANON${a#\$INIT_CWD}" ;;
        '$(pwd -P)'*)             a="$PROJ_CANON${a#\$\(pwd -P\)}" ;;
        '$(pwd -L)'*)             a="$PROJ_CANON${a#\$\(pwd -L\)}" ;;
        '${PWD:-.}'*)             a="$PROJ_CANON${a#\$\{PWD:-.\}}" ;;
        '${PWD%/}'*)              a="$PROJ_CANON${a#\$\{PWD%/\}}" ;;
        '~+'|'~+/'*)              a="$PROJ_CANON${a#\~+}" ;;
      esac
      case "$a" in
        /*)
          _abs=$(_rel_path "$a")
          case "$_abs" in
            '') [ "$reader" = true ] && _deny "a directory that contains pipeline state (the project root: $a)" "cmd:$a"; continue ;;
            /*) case "$PROJ_CANON/" in "${_abs%/}"/*) [ "$reader" = true ] && _deny "a directory that contains pipeline state (an ancestor of the project: $a)" "cmd:$a"; continue ;; esac ;;
            *)  a="$_abs" ;;
          esac ;;
      esac
      # v7.4.2 (audit pass 11, pre-existing) — a relative path that climbs back:
      # `src/..` is the project root, `src/../..` its parent
      case "$a" in
        ..|../*|/*) ;;
        */..|*/../*)
          _abs=$(_rel_path "$PROJ_CANON/$a")
          case "$_abs" in
            '') [ "$reader" = true ] && _deny "a directory that contains pipeline state (the project root: $a)" "cmd:$a"; continue ;;
            /*) case "$PROJ_CANON/" in "${_abs%/}"/*) [ "$reader" = true ] && _deny "a directory that contains pipeline state (an ancestor of the project: $a)" "cmd:$a"; continue ;; esac ;;
            *)  a="$_abs" ;;
          esac ;;
      esac
      t=$(_norm "$a")
      case "$t" in *[*?[]*) t="${t%%[*?[]*}"; t="${t%/}" ;; esac
      # (pass 3/4) `..`, `../..`, `/`, `/.` are ANCESTORS of the project — a read rooted there reaches it;
      # `../<name>` is a SIBLING (a monorepo reviewer reading ../shared/config.json), not an ancestor
      case "$t" in *...*) ;; ..|../..|../../..|../../../..|../../../../..|/.|//|/./.) [ "$reader" = true ] && _deny "a directory that contains pipeline state (an ancestor of the project: $t)" "cmd:$t"; continue ;; esac   # (pass 5) never `...`: `go test ./...` is the canonical Go form
      if [ -z "$t" ]; then
        case "$a" in
          *[!./]*|"") ;;                                 # not a root spelling
          *) [ "$reader" = true ] && _deny "a directory that contains pipeline state (the project root)" "cmd:." ;;   # `.`, `./`, `./.`, `.//`, `././` (pass 2)
        esac
        continue
      fi
      [ "$t" = "$PIPE_REL/$ALLOWED_BASENAME" ] && continue
      if _reaches "$t" "$PIPE_REL" || _reaches "$t" "$MEM_REL"; then
        _deny "a directory that contains pipeline state ($t)" "cmd:$t"
      fi
    done
    return 0
  }
  _judge_text() {  # <shell text> — tokenize and judge every statement (used for heredoc bodies fed to a shell)
    local _t="$1" _tw _tl _tr; local -a _tv
    [ -n "$_t" ] || return 0
    _tw=$(APD_GBS_DEPTH=0 bash "$_GBS" --emit-words --command "$_t" 2>/dev/null || printf 'OPAQUE\n')
    if [ "$(printf '%s\n' "$_tw" | tail -n 1)" = END ] && ! printf '%s\n' "$_tw" | grep -qx 'OPAQUE'; then
      while IFS= read -r _tl; do
        case "$_tl" in "W${_US}"*) _tr="${_tl#W${_US}}" ;; "N${_US}"*) _tr="${_tl#N${_US}}"; case "$_tr" in '$'|'$'"$_US"*|'`'*) continue ;; esac ;; *) continue ;; esac
        _tv=(); IFS="$_US" read -r -a _tv <<< "$_tr"
        _judge_stmt ${_tv[@]+"${_tv[@]}"}
      done <<< "$_tw"
    else
      local _r3; for _r3 in $_t; do case "${_r3//[;&|()<>\"\']/}" in *[!./]*|"") ;; *) _deny "a directory that contains pipeline state (the project root; a shell body could not be tokenized)" "cmd:." ;; esac; done
    fi
  }
  _HD_BODIES=""; _HD_BODIES_JUDGED=false
  case "$COMMAND" in *'<<'*) _HD_BODIES=$(printf '%s\n' "$COMMAND" | awk '
    body { if ($0 == tag || (strip && $0 ~ ("^\t*" tag "$"))) { body = 0; next } print; next }
    match($0, /<<-?[ \t]*[\x27"]?[A-Za-z_][A-Za-z0-9_]*/) {
      t = substr($0, RSTART, RLENGTH); strip = (substr(t, 3, 1) == "-"); sub(/^<<-?[ \t]*/, "", t); gsub(/[\x27"]/, "", t); tag = t; body = 1
    }') ;; esac
  if [ "$(printf '%s\n' "$_WORDS" | tail -n 1)" = END ] && ! printf '%s\n' "$_WORDS" | grep -qx 'OPAQUE'; then
    while IFS= read -r _line; do
      case "$_line" in "W${_US}"*) _rest="${_line#W${_US}}" ;; "N${_US}"*) _rest="${_line#N${_US}}"; case "$_rest" in '$'|'$'"$_US"*|'`'*) continue ;; esac ;; *) continue ;; esac   # an N line is a statement inside a DATA substitution: its leading `$`/backtick is the substitution, not a command
      _w=(); IFS="$_US" read -r -a _w <<< "$_rest"
      _judge_stmt ${_w[@]+"${_w[@]}"}
    done <<< "$_WORDS"
  else
    # fail closed: the pre-v7.2.3 crude rule — every bare `.`/`./` and every
    # ancestor token denies, git head exempt from the ancestor part
    # v7.4.2, same spirit: the statements cannot be read, so a `git add` or a
    # recursive reader anywhere in the text denies (its operands cannot be told).
    _fb_git=false; _fb_grep=false; _fb_rec=false
    set -f
    for raw in $COMMAND; do
      tok="${raw//[;&|()<>\"\']/}"; tok="${tok##*/}"
      case "$tok" in
        git) _fb_git=true ;;
        add|stage) [ "$_fb_git" = true ] && { set +f; _deny "the index (git $tok; the command could not be tokenized)" "cmd:git-$tok"; } ;;
        find|gfind|bfs|fd|fdfind|tree|du|gdu|rg|ag|ack) set +f; _deny "the whole project (a recursive $tok in a command that could not be tokenized)" "cmd:$tok:opaque" ;;
        grep|egrep|fgrep|ggrep|ugrep|ug) _fb_grep=true ;;
        --recursive|--dereference-recursive) _fb_rec=true ;;
        --*) ;;
        -*[rR]*) _fb_rec=true ;;
      esac
    done
    set +f
    [ "$_fb_grep" = true ] && [ "$_fb_rec" = true ] && _deny "the whole project (a recursive grep in a command that could not be tokenized)" "cmd:grep:opaque"
    set -f
    for raw in $COMMAND; do
      tok="${raw//[;&|()<>\"\']/}"
      [ -z "$tok" ] && continue
      t=$(_norm "$tok")
      case "$t" in *[*?[]*) t="${t%%[*?[]*}"; t="${t%/}" ;; esac
      if [ -z "$t" ]; then
        case "$tok" in .|./) [ "$_CMD_HEAD" != git ] && { set +f; _deny "a directory that contains pipeline state (the project root; the command could not be tokenized)" "cmd:."; } ;; esac
        continue
      fi
      [ "$t" = "$PIPE_REL/$ALLOWED_BASENAME" ] && continue
      if { _reaches "$t" "$PIPE_REL" || _reaches "$t" "$MEM_REL"; } && [ "$_CMD_HEAD" != git ]; then
        set +f; _deny "a directory that contains pipeline state ($t)" "cmd:$t"
      fi
    done
    set +f
  fi
fi

exit 0
