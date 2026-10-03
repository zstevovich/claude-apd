#!/bin/bash
# APD Bash Scope Guard — blocks Bash commands that write outside the allowed scope
# Complements guard-scope which protects Write/Edit operations
#
# Detects:
#   1. Shell write operations: redirect (>), tee, sed -i, cp, mv, dd, install
#   2. Runtime write operations: node -e, python -c, ruby -e, php -r, perl -e
#      with write functions (writeFileSync, open().write, file_put_contents...)
#
# Interface: --command <cmd> [--cwd <dir>] [--deny-all-writes] [allowed_path_1] [allowed_path_2] ...

source "$(dirname "$0")/../lib/resolve-project.sh"
source "$(dirname "$0")/../lib/style.sh"
[ "$APD_ACTIVE" = false ] && exit 0

COMMAND=""
CWD_ARG=""
DENY_ALL_WRITES=false
EMIT_GIT=false   # v7.1.5: lend the tokenizer to guard-git — print git statements, judge nothing
EMIT_WORDS=false # v7.2.3: lend it to guard-spec-blind — one `W` line per statement (wrappers, assignments, keywords stepped), judge nothing
_emit_opaque() { { [ "$EMIT_GIT" = true ] || [ "$EMIT_WORDS" = true ]; } && printf 'OPAQUE\n'; return 0; }
EMIT_NESTED=0
ALLOWED_PATHS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --command) COMMAND="$2"; shift 2 ;;
    # v7.1: the Bash tool's working directory (hook payload `cwd`). Relative
    # write targets and `cd` operands resolve against it; default PROJECT_DIR.
    --cwd) CWD_ARG="$2"; shift 2 ;;
    # A writable agent whose scope did not resolve. The caller cannot name a
    # path, but "no scope" must not read as "every path": this keeps the write
    # DETECTION here, where it already lives, so the agent is stopped at writes
    # and still free to run `git diff` or the test command.
    --deny-all-writes) DENY_ALL_WRITES=true; shift ;;
    --emit-git) EMIT_GIT=true; shift ;;
    --emit-words) EMIT_WORDS=true; shift ;;
    *) ALLOWED_PATHS+=("$1"); shift ;;
  esac
done

if [ -z "$COMMAND" ]; then
  exit 0
fi

# --- 0. Protected paths — ALWAYS enforced, even without ALLOWED_PATHS ---
# .apd/pipeline/ state files must only be modified by pipeline-advance (not direct Bash writes)
# Plugin cache must never be modified by orchestrator
# (audit pass #3) a quoted word that spans lines is ONE word — the tokenizer
# keeps reading it across the newline exactly as bash does (record end below);
# only a quote still open at the END of the text is reported (`OPENQ` → OPAQUE).
if [ -z "${APD_GBS_BUDGET_FILE:-}" ]; then   # the top level owns the nested-shell budget (audit pass #2 D; v7.1.7: every mode — quoted substitutions recurse in scope mode too)
  APD_GBS_BUDGET_FILE=$(mktemp -t apd-gbs-budget.XXXXXX 2>/dev/null || echo "")
  if [ -n "$APD_GBS_BUDGET_FILE" ]; then
    echo 40 > "$APD_GBS_BUDGET_FILE"; export APD_GBS_BUDGET_FILE
    trap 'rm -f "$APD_GBS_BUDGET_FILE"' EXIT
  fi
fi

PROTECTED_PIPELINE=(".apd/pipeline/")
SHELL_WRITE_CHECK=('>>' '>' 'tee ' 'sed -i' 'sed --in-place' 'cp ' 'mv ' 'dd ' 'install ' 'mkdir ' 'mkdir -p' 'touch ' 'rm ' 'rm -f' 'rm -rf' 'rmdir ')
# Write checks for plugin cache — exclude '>' and '>>' (false positives from 2>&1 redirects)
PLUGIN_WRITE_CHECK=('tee ' 'sed -i' 'sed --in-place' 'cp ' 'mv ' 'dd ' 'install ' 'mkdir ' 'mkdir -p' 'touch ' 'rm ' 'rm -f' 'rm -rf' 'rmdir ')

_runtime_write_detected() {
  local cmd="$1"
  if echo "$cmd" | grep -qE '(^|[;&|] *)node\s+(-e|--eval|--print)\s' &&
     echo "$cmd" | grep -qiE 'writeFile|writeFileSync|appendFile|appendFileSync|createWriteStream|mkdirSync|copyFile'; then
    return 0
  fi
  if echo "$cmd" | grep -qE '(^|[;&|] *)python[3]?\s+(-c)\s' &&
     echo "$cmd" | grep -qiE "open\s*\(|\.write\s*\(|Path\s*\(|shutil\.|os\.rename|os\.replace|pathlib"; then
    return 0
  fi
  if echo "$cmd" | grep -qE '(^|[;&|] *)ruby\s+(-e)\s' &&
     echo "$cmd" | grep -qiE 'File\.(write|open|rename)|FileUtils\.(cp|mv|mkdir)'; then
    return 0
  fi
  if echo "$cmd" | grep -qE '(^|[;&|] *)php\s+(-r)\s' &&
     echo "$cmd" | grep -qiE 'file_put_contents|fwrite|fopen|rename|copy|mkdir'; then
    return 0
  fi
  if echo "$cmd" | grep -qE '(^|[;&|] *)perl\s+(-e)\s' &&
     echo "$cmd" | grep -qiE 'open\s*\(|print\s+\$|File::Copy|rename'; then
    return 0
  fi
  return 1
}

# v7.1.4: the plugin cache is fenced by the PARSER, on canonical targets —
# see the block after the tokenizer. The raw-string scan that stood here
# (`<writer>…plugins/cache`, `>[^&].*plugins/cache`, a runtime regex) refused
# read-only commands whenever `2>/dev/null`, a quoted `>` or a quoted `rm `
# appeared anywhere before a plugin path (reported and reproduced 2026-09-30).

# v6.15 (#5) — three-way channel guidance for pipeline-state BLOCKs.
# The guard cannot tell a read from a write from a fabrication attempt, so it
# blocks ALL bash access conservatively — but the old message ("use the apd
# command instead") misdirected: for reads the channel is `apd pipeline show`,
# for allowlisted files it is the Write/Edit tool, and only state transitions
# go through `apd pipeline <phase>`. Cross-project evidence (Bambi/FFAI/
# ig-commerce ~1 block/run): orchestrator mostly READS (cat .reviewed-files)
# and burned a turn per block because no message pointed at the read path.
_pipeline_block_guidance() {
  echo "" >&2
  echo "  Bash access to .apd/pipeline/ is blocked. Use the right channel:" >&2
  echo "    READ state      → bash $APD_SHORTCUT_DISPLAY pipeline show [spec|plan|state]" >&2
  echo "                      (never cat/ls/head files under .apd/pipeline/)" >&2
  echo "    WRITE your file → Write/Edit tool for allowlisted files only:" >&2
  echo "                      spec-card.md, implementation-plan.md," >&2
  echo "                      .adversarial-summary, .adversarial-rationale.md," >&2
  echo "                      .supervision-summary, .supervision-rationale.md, .guide-marker" >&2
  echo "    ADVANCE phase   → bash $APD_SHORTCUT_DISPLAY pipeline <spec|builder|reviewer|verifier|reset>" >&2
}

# Block writes to .apd/pipeline/ (APD tools whitelisted)
# Uses PLUGIN_WRITE_CHECK (no > and >>) to avoid false positives from 2>/dev/null redirects
if [ "$EMIT_GIT" != true ]; then   # (v7.1.5) in emit mode nothing is judged here
for ppath in "${PROTECTED_PIPELINE[@]}"; do
  if [[ "$COMMAND" == *"$ppath"* ]]; then
    # Allow APD's own tools to write to .apd/pipeline/
    if [[ "$COMMAND" == *"pipeline-advance"* ]] || [[ "$COMMAND" == *"apd pipeline"* ]] || [[ "$COMMAND" == *"verify-apd"* ]] || [[ "$COMMAND" == *"pipeline-post-commit"* ]] || [[ "$COMMAND" == *"pipeline-gate"* ]]; then
      break
    fi
    # v6.15 — allow .guide-marker writes (apd-pipeline-guide skill writes it as
    # final exit action before pipeline-advance spec; without this exception the
    # printf > .apd/pipeline/.guide-marker would BLOCK at this guard).
    # v7.0 — the `.brainstorm-marker` legacy entry is gone. It was kept through
    # the v6.15 upgrade window so a task mid-flight at the switch could still
    # write its marker; nothing has written one since, and an allowlisted path
    # nothing produces is surface without a purpose.
    if [[ "$COMMAND" == *".guide-marker"* ]]; then
      break
    fi
    # Check non-redirect write operations
    for wp in "${PLUGIN_WRITE_CHECK[@]}"; do
      if [[ "$COMMAND" == *"$wp"*"$ppath"* ]] || [[ "$COMMAND" == *"$wp"*".apd/pipeline/"* ]]; then
        echo "BLOCKED: Bash write to protected pipeline state directory." >&2
        _pipeline_block_guidance
        log_block "pipeline-state-write" "${COMMAND:0:200}"
        exit 2
      fi
    done
    # Check redirect operators only when they TARGET .apd/pipeline/ (not 2>/dev/null)
    if echo "$COMMAND" | grep -qE '>[^&].*\.apd/pipeline/|>>.*\.apd/pipeline/' 2>/dev/null; then
      echo "BLOCKED: Bash redirect to protected pipeline state directory." >&2
      _pipeline_block_guidance
      log_block "pipeline-state-write" "${COMMAND:0:200}"
      exit 2
    fi
    if _runtime_write_detected "$COMMAND"; then
      echo "BLOCKED: Runtime write to protected pipeline state directory." >&2
      _pipeline_block_guidance
      log_block "pipeline-state-write" "${COMMAND:0:200}"
      exit 2
    fi
  fi
done
fi

# v7.1 (gates delta audit R1): the substring checks above need the literal
# `.apd/pipeline/` in the command. `cd .apd/pipeline && rm .dispatch-classes`,
# `cd .apd && rm pipeline/.agents`, `rm -rf .apd/pipeline`, `truncate -s0 …`
# reached the ledger and the class snapshot untouched — the `rm -rf
# .apd/pipeline` bypass class known since 2026-05-23, now carrying the budget.
# A caller with NO scope (the orchestrator) therefore still runs the parser
# below, in PROTECT_ONLY mode: nothing is judged except targets that resolve
# under the pipeline dir. APD's own tools are exempt as before.
PROTECT_ONLY=false
if [ ${#ALLOWED_PATHS[@]} -eq 0 ] && [ "$DENY_ALL_WRITES" = false ]; then
  # v7.1.4 (audit C1, M-a): this used to `exit 0` here, BEFORE the parser,
  # on a substring match — so "# apd pipeline status" in a comment unlocked
  # every fence below. APD's own tools are now recognised by a command WORD
  # inside _process_stmt (comments never reach it), and they are exempt from
  # the PIPELINE fence only; the parser and the cache fence always run.
  PROTECT_ONLY=true
fi

# --- 1. Read the command the way the shell reads it (v7.1) --------------------
#
# Everything below replaces a substring scanner. That scanner grepped the raw
# command for `>` and for op names, so it could not tell a redirect from a
# generic (`IReadOnlyList<string>`), a quoted pattern (`'^> Task'`) or the body
# of a heredoc from shell, and it compared the raw token against relative scope
# roots by string prefix, so an absolute path INSIDE the agent's scope, a path
# relative to a `cd`, or `$SP/out.txt` all read as "outside". Measured on one
# project in September 2026: 170 blocks, 166 on subagents, and three agents had
# written themselves memory notes on how to phrase commands around the guard.
# CC tried the same substring idea (Read-deny on Bash arguments, 2.1.259) and
# reverted it one release later for the same reason.
#
# So: a single-pass tokenizer (awk, POSIX, bash-3.2-safe) that tracks quote,
# escape, arithmetic and heredoc state, emits words with quotes removed,
# separators, redirect TARGETS (only where the shell would redirect: outside
# quotes and arithmetic, not `=>`/`->`/`>=`, not fd dups, not `>(…)`), and
# heredoc bodies as data. Then, per statement: shell keywords and wrappers
# (`then`, `do`, `{`, `!`, `sudo -u x`, `timeout 10`, `nice -n 5`, `env -i`,
# `xargs`) are stepped over, same-command assignments resolve `$VAR`, `cd` /
# `pushd` / `popd` move the working directory (subshells push and pop it),
# every write target is canonicalised through bin/lib/path-canon.sh and
# compared against the canonical scope roots, `bash -c` / `eval` / a heredoc
# fed to a shell are re-parsed by this same guard, and an interpreter fed by
# `-c` / `-e` or a heredoc is scanned for WRITE calls only (a read `open(p)` is
# not a write). The fail-closed direction is kept: an unresolvable variable, an
# unknown `cd`, a `popd` past the stack, targets that come from stdin
# (`xargs`), or a surviving `..` block.
#
# Independent audit 2026-09-29 (parser): four fail-open classes and thirteen
# more were found in the first cut — keywords in command position, `\`-newline
# continuation, a heredoc followed by `|`, `sed -Ei`, `eval`, wrappers with
# arguments, `xargs`/`find -exec`, `popd`, `PWD=`, `> >(…)`, `<<\EOF`,
# `$((1<<3))`, `perl -pi`, `git rm/mv`, interpreter argv. Each is a paired
# check in §134 now.
#
# Still not read, and said so: `[[ $a > $b ]]` outside quotes reads as a
# redirect; tool-level writers outside the model (`patch`, `ex`, `gzip`,
# `split`, `mkfifo`, `os.system`/`subprocess`/`child_process` inside a program,
# `dotnet format`, `prettier --write`) are not seen; two heredocs on one line
# keep only the first.

source "$(dirname "$0")/../lib/path-canon.sh"

# bash 5.2+ expands `&` in a ${var//pat/repl} REPLACEMENT to the matched text
# (patsub_replacement); bash 3.2 keeps a QUOTED replacement's quote characters
# in the result. The only form that is literal on both is an unquoted
# replacement with the option off — so turn it off where it exists.
shopt -u patsub_replacement 2>/dev/null || true

APD_GBS_DEPTH="${APD_GBS_DEPTH:-0}"
BASE_CWD="${CWD_ARG:-$PROJECT_DIR}"
[ -d "$BASE_CWD" ] || BASE_CWD="$PROJECT_DIR"
PROJ_CANON=$(_proj_canon)
CUR_CWD=$(_canon_abs "$BASE_CWD")     # physical form, like every target and PROJ_CANON
CWD_UNKNOWN=false

# v7.0.5: the session scratchpad is a sanctioned write target — the rule
# (`_is_session_scratchpad`) lives in bin/lib/path-canon.sh since v7.1.4 and
# is shared with guard-scope and guard-orchestrator.

_scope_hint() {
  if [ "$DENY_ALL_WRITES" = true ] && [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
    echo "  This agent declares no writable scope, so it may not write anywhere —" >&2
    echo "  not through Write/Edit and not through the shell (the session scratchpad" >&2
    echo "  is the one exception, /tmp is not)." >&2
    echo "  A review role has no scope by design: send scratch output to the session" >&2
    echo "  scratchpad, and run a mutation proof on a copy of the tree there." >&2
    echo "  A builder: fix the scope in its agent definition (an unfilled" >&2
    echo "  {{SCOPE_PATHS}} reads as 'no scope')." >&2
  else
    echo "  Allowed paths: ${ALLOWED_PATHS[*]} (relative to the project root; absolute forms of the same paths are fine)" >&2
    echo "  Session scratchpad writes are always allowed. 'mv' counts its SOURCE too (use cp to bring a file in)." >&2
  fi
}

# Canonical scope roots, computed once. A root that does not exist yet still
# resolves (deepest existing ancestor + tail), same as a target.
SCOPE_CANON=()
for _r in ${ALLOWED_PATHS[@]+"${ALLOWED_PATHS[@]}"}; do
  _r="${_r%/}"
  case "$_r" in
    /*) SCOPE_CANON+=("$(_canon_abs "$_r")") ;;
    *)  SCOPE_CANON+=("$(_canon_abs "$_r" "$PROJ_CANON")") ;;
  esac
done

# _in_scope <canonical-abs-path> → 0 when under a scope root or the scratchpad
_in_scope() {
  local p="$1" r
  _is_session_scratchpad "$p" && return 0
  for r in ${SCOPE_CANON[@]+"${SCOPE_CANON[@]}"}; do
    [ "$p" = "$r" ] && return 0
    case "$p/" in "$r/"*) return 0 ;; esac
  done
  return 1
}

# Canonicalisation with a per-directory cache: realpath + `cd && pwd -P` per
# target cost 9–14 s on a 700-target command (audit I12); most targets share a
# handful of directories.
CD_K=(); CD_V=()
_canon_cached() {  # <path> [<base>] [nofollow]
  local p="$1" base="${2:-$CUR_CWD}" nofollow="${3:-}" d b i abs
  case "$p" in
    /*) ;;
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
    *) p="$base/$p" ;;
  esac
  case "$p" in */..|*/../*|*/.|*/./*|*//*) _canon_abs "$p"; return 0 ;; esac
  # a symlink as the LAST component points wherever it likes (audit N2:
  # `echo > src/link` with link → outside/secret.txt escaped through the cache)
  # `rm`/`unlink`/`rmdir` act on the link itself, never on what it points to
  # (delta audit: `rm src/link` false-blocked once the target was followed).
  if [ -z "$nofollow" ] && [ -L "$p" ]; then _canon_abs "$p"; return 0; fi
  d="${p%/*}"; b="${p##*/}"
  [ -z "$d" ] && d="/"
  for ((i = 0; i < ${#CD_K[@]}; i++)); do
    if [ "${CD_K[$i]}" = "$d" ]; then
      abs="${CD_V[$i]%/}/$b"
      if [ -z "$nofollow" ] && [ -L "$abs" ]; then _canon_abs "$abs"; else printf '%s\n' "$abs"; fi
      return 0
    fi
  done
  abs=$(_canon_abs "$d")
  CD_K+=("$d"); CD_V+=("$abs")
  abs="${abs%/}/$b"
  if [ -z "$nofollow" ] && [ -L "$abs" ]; then _canon_abs "$abs"; else printf '%s\n' "$abs"; fi
}

# --- same-command variables (bash 3.2: no associative arrays) ---
VN=(); VV=(); SUBST_ORDER=""
_setvar() {
  local i
  for ((i = 0; i < ${#VN[@]}; i++)); do
    if [ "${VN[$i]}" = "$1" ]; then VV[$i]="$2"; return; fi
  done
  VN+=("$1"); VV+=("$2"); SUBST_ORDER=""
}
# _subst <string> — expand $NAME/${NAME} from this command's assignments, then
# HOME/PWD/TMPDIR; longest name first (so $HOME_DIR is not eaten by $HOME —
# audit M4) and a same-command PWD= wins over the tracked cwd (audit I8).
_subst() {
  local s="$1" i n v
  case "$s" in *\$*) ;; *) printf '%s' "$s"; return 0 ;; esac
  if [ ${#VN[@]} -gt 0 ]; then
    if [ -z "$SUBST_ORDER" ]; then
      SUBST_ORDER=$(for ((i = 0; i < ${#VN[@]}; i++)); do printf '%d %d\n' "${#VN[$i]}" "$i"; done | sort -rn | awk '{print $2}')
    fi
    for i in $SUBST_ORDER; do
      n="${VN[$i]}"; v="${VV[$i]}"
      s="${s//\$\{$n\}/$v}"; s="${s//\$$n/$v}"
    done
  fi
  # builtins, only where the command did not redefine them (order: longest first)
  v="${TMPDIR:-/tmp}"; s="${s//\$\{TMPDIR\}/$v}"; s="${s//\$TMPDIR/$v}"
  v="${CLAUDE_PLUGIN_ROOT:-}"; [ -n "$v" ] && { s="${s//\$\{CLAUDE_PLUGIN_ROOT\}/$v}"; s="${s//\$CLAUDE_PLUGIN_ROOT/$v}"; }
  v="$HOME";           s="${s//\$\{HOME\}/$v}";   s="${s//\$HOME/$v}"
  v="$CUR_CWD";        s="${s//\$\{PWD\}/$v}";    s="${s//\$PWD/$v}"
  printf '%s' "$s"
}
_unresolved() { case "$1" in *\$*|*\`*) return 0 ;; esac; return 1; }
# v7.1.4 (audit F1): inside a writing PROGRAM, `$name` is a shell variable only
# when this command assigned it or the guard expands it (HOME, PWD, TMPDIR,
# CLAUDE_PLUGIN_ROOT). Perl's `$fh`, PHP's `$f`, Ruby's `$stdin`, a JS `${n}`
# template and a literal `\$5` are the program's own business.
_known_var() {
  local i
  for ((i = 0; i < ${#VN[@]}; i++)); do [ "${VN[$i]}" = "$1" ] && return 0; done
  case "$1" in HOME|PWD|TMPDIR) return 0 ;; CLAUDE_PLUGIN_ROOT) [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && return 0 ;; esac
  return 1
}
# (audit F-a) does the raw command name a fenced directory? The cache by its
# literal, the pipeline dir anchored to a path segment (`.apd/pipeline-notes.md`
# and `my.apd/pipelines.md` are not it).
_PIPE_MENTION_RE='\.apd/pipeline(/|[^A-Za-z0-9_./-]|$)'
_names_fenced_dir() {
  case "$COMMAND" in *plugins/cache*) return 0 ;; esac
  [[ "$COMMAND" =~ $_PIPE_MENTION_RE ]] && return 0
  return 1
}
_var_name() { local v="${1#\$}"; v="${v#\{}"; printf '%s' "$v" | sed -E 's/[^A-Za-z0-9_].*$//'; }
# (audit R2) `$ENV{HOME}/.bashrc`, `${process.env.HOME}/x`: the variable head is
# the program's, the path glued after it is still a path — judge the remainder.
_var_tail() { printf '%s' "$1" | sed -E 's/^\$\{[^}]*\}//; s/^\$[A-Za-z0-9_]*(\{[^}]*\})?//'; }

# --- targets ---
TARGET_RAW=(); TARGET_ABS=(); TARGET_NOTE=(); TARGET_APD=()   # TARGET_APD: registered by an APD tool's own statement (audit M-a2)
STMT_APD=false
RUNTIME_WRITE=false; RUNTIME_TEXT=""; WRITE_TYPE=""
RT_CWD_CACHE=false; RT_CWD_UNKNOWN=false; RT_CWD_ALL_IN_SCOPE=true; RT_CWD_ALL_IN_PROJ=true

_add_target() {   # <raw word> [nofollow]
  local raw="$1" nofollow="${2:-}" s abs
  case "$raw" in ''|/dev/null|/dev/stdout|/dev/stderr|/dev/tty|'&'*) return 0 ;; esac
  case "$raw" in /dev/fd/[0-9]|/dev/fd/[0-9][0-9]) return 0 ;; esac   # v7.2.4: a descriptor, like >&2
  case "$raw" in *\\*) TARGET_RAW+=("$raw"); TARGET_ABS+=(""); TARGET_NOTE+=("a backslash escape in a path is not decoded (ANSI-C \$'…', a literal backslash)"); TARGET_APD+=("${STMT_APD:-false}"); return 0 ;; esac   # v7.1.7
  s=$(_subst "$raw")
  if _unresolved "$s"; then
    TARGET_RAW+=("$raw"); TARGET_ABS+=(""); TARGET_NOTE+=("unresolved variable or substitution"); TARGET_APD+=("${STMT_APD:-false}"); return 0
  fi
  case "$s" in
    /*|"~"|"~/"*) abs=$(_canon_cached "$s" "$CUR_CWD" "$nofollow") ;;
    *)
      if [ "$CWD_UNKNOWN" = true ]; then
        TARGET_RAW+=("$raw"); TARGET_ABS+=(""); TARGET_NOTE+=("relative to a working directory the guard could not resolve (cd to a substitution, cd -, or popd past the stack)"); TARGET_APD+=("${STMT_APD:-false}"); return 0
      fi
      abs=$(_canon_cached "$s" "$CUR_CWD" "$nofollow") ;;
  esac
  TARGET_RAW+=("$raw"); TARGET_ABS+=("$abs"); TARGET_NOTE+=(""); TARGET_APD+=("${STMT_APD:-false}")
}
_add_unknown_target() {  # <what> — a write whose targets the guard cannot see
  _emit_opaque   # (audit) depth cap / ANSI-C text: unreadable for guard-git too
  TARGET_RAW+=("$1"); TARGET_ABS+=(""); TARGET_NOTE+=("its targets are not visible to the guard — name the files instead"); TARGET_APD+=("${STMT_APD:-false}")
}

# --- runtime write heuristics, keyed to WRITE calls ---
_rt_write() {  # <lang> <text> → 0 when the text performs a filesystem write
  local lang="$1" t="$2"
  case "$lang" in
    python) printf '%s' "$t" | grep -qiE "open[[:space:]]*\([^)]*,[[:space:]]*['\"][rwax+b]*[wax]|mode[[:space:]]*=[[:space:]]*['\"][rwax+b]*[wax]|\.write\(|write_text\(|write_bytes\(|shutil\.|os\.(rename|replace|remove|unlink|makedirs|mkdir|rmdir|link|symlink|system)|subprocess|\.unlink\(|rmtree\(|\.mkdir\(|\.touch\(|\.rename\(|\.replace\(" ;;
    node)   printf '%s' "$t" | grep -qiE "writeFile|appendFile|createWriteStream|mkdirSync|\.mkdir\(|copyFile|renameSync|\.rename\(|unlink|rmSync|\.rm\(|rmdir|truncate|child_process|execSync" ;;
    ruby)   printf '%s' "$t" | grep -qiE "File\.(write|open\([^)]*,[[:space:]]*['\"][rwax+b]*[wax]|rename|delete|unlink)|FileUtils\.|IO\.write|system\(|\`" ;;
    php)    printf '%s' "$t" | grep -qiE "file_put_contents|fwrite|fopen\([^)]*,[[:space:]]*['\"][rwax+b]*[wax]|rename\(|copy\(|mkdir\(|unlink\(|rmdir\(|exec\(|shell_exec|system\(" ;;
    perl)   printf '%s' "$t" | grep -qiE "open[[:space:]]*\([^)]*,[[:space:]]*['\"]?[[:space:]]*>|open[[:space:]]+[A-Z_]+[[:space:]]*,[[:space:]]*['\"]>|File::Copy|rename\(|unlink|mkdir\(|rmdir\(|system\(|\`" ;;
    *) return 1 ;;
  esac
}
_rt_mark() {  # <text>
  RUNTIME_WRITE=true; WRITE_TYPE="runtime"
  RUNTIME_TEXT="${RUNTIME_TEXT}${1}"$'\n'
  # v7.1.4 (audit N2): the working directory that matters is the one at the
  # moment the program runs — `(cd <cache> && python …)` or `cd <cache>; … ; cd /tmp`
  # ended the parse somewhere else and the old final-cwd test missed it.
  _is_plugin_cache "$CUR_CWD" && RT_CWD_CACHE=true
  [ "$CWD_UNKNOWN" = true ] && RT_CWD_UNKNOWN=true
  _in_scope "$CUR_CWD" || RT_CWD_ALL_IN_SCOPE=false
  case "$CUR_CWD/" in "$PROJ_CANON/"*) ;; *) RT_CWD_ALL_IN_PROJ=false ;; esac
}

# Re-parse shell text with THIS guard (bash -c, eval, a heredoc fed to a shell).
# Depth-limited; a nested refusal is this refusal.
_recurse_shell() {  # <shell text>
  local text="$1" rc
  [ -n "$text" ] || return 0
  text="${text//$'\x1e'/$'\n'}"   # (v7.1.5) a multi-line body arrives with 0x1e for its newlines; the nested tokenizer wants real ones
  # v7.1.4 (audit C2): `sh -c "$CMD"` handed the nested guard the literal
  # `$CMD`. Expand this command's own assignments first; a body that still
  # BEGINS with a variable or a substitution is a shell fed text the guard
  # cannot read — refused for every caller (write the command out).
  text=$(_subst "$text")
  # (audit F2) `eval "$(direnv hook bash)"` / `sh -c "$(cat x)"` are ordinary
  # bootstrap: the inner command is visible, only its output is not — the
  # pre-v7.1.4 behaviour. A body that begins with `$NAME`, `${…}`, `$@`, `$*`
  # or a positional is the hidden-variable shape and stays refused.
  case "${text#"${text%%[! ]*}"}" in
    '$('*|'`'*)
      # (audit R1) the OUTPUT of the substitution is what runs, and that is
      # invisible: when the command names the cache or the pipeline dir, refuse.
      # v7.2.3 (live): NOT when the text is a quoted substitution in ARGUMENT
      # position (`echo "lines: $(wc -l < <cache file>)"`) — there the output is
      # data for a command already judged; the inner command is parsed below.
      # The eval / sh -c / command-position paths reset APD_GBS_DATA before
      # calling here, so an executed body keeps the refusal.
      if [ "${APD_GBS_DATA:-}" != 1 ] && _names_fenced_dir; then TARGET_RAW+=("${text:0:60}"); TARGET_ABS+=(""); { _emit_opaque; }; TARGET_NOTE+=("opaque shell body: ${text:0:40}"); TARGET_APD+=("${STMT_APD:-false}"); return 0; fi ;;
    \$*) TARGET_RAW+=("${text:0:60}"); TARGET_ABS+=(""); { _emit_opaque; }; TARGET_NOTE+=("opaque shell body: ${text:0:40}"); TARGET_APD+=("${STMT_APD:-false}"); return 0 ;;
  esac
  if printf '%s' "$text" | grep -qE '\\x[0-9a-fA-F]|\\[0-7]{3}|\\u[0-9a-fA-F]|\\U[0-9a-fA-F]'; then
    _add_unknown_target "shell text with ANSI-C escapes"; return 0
  fi
  if [ "$APD_GBS_DEPTH" -ge 3 ] 2>/dev/null; then
    # v7.2.3 (audit B3): beyond the cap the text is unreadable — when the command names a fence, refuse (PROTECT_ONLY skips unknown targets)
    if _names_fenced_dir; then TARGET_RAW+=("${text:0:60}"); TARGET_ABS+=(""); _emit_opaque; TARGET_NOTE+=("opaque shell body: nested shell beyond the depth cap"); TARGET_APD+=("${STMT_APD:-false}"); return 0; fi
    _add_unknown_target "nested shell (depth > 3)"; return 0
  fi
  if [ "$EMIT_WORDS" = true ]; then   # v7.2.3: nested statements are emitted through our stdout, as emit-git does
    EMIT_NESTED=$((EMIT_NESTED + 1)); if [ "$EMIT_NESTED" -gt 8 ]; then printf 'OPAQUE\n'; return 0; fi
    APD_GBS_DEPTH=$((APD_GBS_DEPTH + 1)) bash "$0" --emit-words --command "$text" --cwd "$CUR_CWD" 2>/dev/null || printf 'OPAQUE\n'
    return 0
  fi
  if [ "$EMIT_GIT" = true ]; then   # (v7.1.5) nested git statements are emitted through our stdout
    EMIT_NESTED=$((EMIT_NESTED + 1))
    if [ "$EMIT_NESTED" -gt 8 ]; then printf 'OPAQUE\n'; return 0; fi   # (audit) a wall of nested shells is not parsed one by one
    # (audit pass #2 D) a TOTAL budget across the whole tree — per-level caps
    # still allowed 8×8×8 = 512 shells ≈ 29 s against a 5 s hook timeout that
    # does not block on CC. The counter lives in a file the top level owns.
    if [ -n "${APD_GBS_BUDGET_FILE:-}" ] && [ -f "$APD_GBS_BUDGET_FILE" ]; then
      _b=$(cat "$APD_GBS_BUDGET_FILE" 2>/dev/null || echo 0)
      if [ "${_b:-0}" -le 0 ] 2>/dev/null; then printf 'OPAQUE\n'; return 0; fi
      echo $((_b - 1)) > "$APD_GBS_BUDGET_FILE"
    fi
    APD_GBS_DEPTH=$((APD_GBS_DEPTH + 1)) bash "$0" --emit-git --command "$text" --cwd "$CUR_CWD" 2>/dev/null || printf 'OPAQUE\n'
    return 0
  fi
  if [ -n "${APD_GBS_BUDGET_FILE:-}" ] && [ -f "$APD_GBS_BUDGET_FILE" ]; then   # (v7.1.7, audit I1) the total budget binds here too
    _b=$(cat "$APD_GBS_BUDGET_FILE" 2>/dev/null || echo 0)
    if [ "${_b:-0}" -le 0 ] 2>/dev/null; then
      if _names_fenced_dir; then TARGET_RAW+=("${text:0:60}"); TARGET_ABS+=(""); TARGET_NOTE+=("opaque shell body: nested shells beyond the budget"); TARGET_APD+=("${STMT_APD:-false}"); return 0; fi   # v7.2.3 (audit B3)
      _add_unknown_target "nested shells beyond the budget (40 per command)"; return 0
    fi
    echo $((_b - 1)) > "$APD_GBS_BUDGET_FILE"
  fi
  APD_GBS_DEPTH=$((APD_GBS_DEPTH + 1)) bash "$0" --command "$text" --cwd "$CUR_CWD" \
      $( [ "$DENY_ALL_WRITES" = true ] && printf -- '--deny-all-writes' ) \
      ${ALLOWED_PATHS[@]+"${ALLOWED_PATHS[@]}"} >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 2 ]; then
    TARGET_RAW+=("${text:0:60}"); TARGET_ABS+=(""); TARGET_NOTE+=("nested shell text writes outside the scope"); TARGET_APD+=("${STMT_APD:-false}")
  fi
  return 0
}

# --- per-statement processing ---
ST=(); RT=(); HB=""; ST_HAS_HD=false; HD_PENDING=false
DEF_ST=(); DEF_RT=(); DEF_SET=false
CWD_STACK=(); DIR_STACK=()
NF=()

# _positionals <flags-with-values regex> — fills NF[] from A[]; a flag that
# matches the regex consumes the next word; `--` ends flags; `-` alone is data.
_positionals() {
  local vflags="${1:-^$}" a flags_done=false skip=false
  NF=()
  for a in ${A[@]+"${A[@]}"}; do
    if [ "$skip" = true ]; then skip=false; continue; fi
    if [ "$flags_done" = false ]; then
      case "$a" in
        --) flags_done=true; continue ;;
        -?*)
          if printf '%s' "$a" | grep -qE "$vflags"; then skip=true; fi
          continue ;;
      esac
    fi
    NF+=("$a")
  done
}

_apd_tool_word() {  # <word> <next word> → 0 when <word> is one of APD's own tools
  case "$1" in
    */plugins/apd/bin/core/pipeline-advance|*/plugins/apd/bin/core/verify-apd|*/plugins/apd/bin/core/pipeline-post-commit|*/plugins/apd/bin/core/pipeline-gate) return 0 ;;
    *APD_PLUGIN_ROOT*/bin/core/pipeline-advance|*APD_PLUGIN_ROOT*/bin/core/verify-apd|*APD_PLUGIN_ROOT*/bin/core/pipeline-post-commit|*APD_PLUGIN_ROOT*/bin/core/pipeline-gate) return 0 ;;
    apd|.claude/bin/apd|*/.claude/bin/apd|*/plugins/apd/bin/apd) [ "$2" = pipeline ] && return 0 ;;
  esac
  return 1
}
_process_stmt() {
  local n=${#ST[@]} i=0 w name cmd a last lang text has_expr seen_pat expect_expr inplace body abs
  [ "$n" -eq 0 ] && [ ${#RT[@]} -eq 0 ] && return 0
  STMT_MARK=false   # v7.2.3: this statement's own assignment prefix carried the orchestrator marker
  STMT_XARGS=false  # v7.2.3: the command word came through xargs (its targets are stdin — emit-words consumers must know)
  # leading assignments, shell keywords, and wrappers (with their own arguments)
  while [ $i -lt $n ]; do
    w="${ST[$i]}"
    case "$w" in
      *=*)
        name="${w%%=*}"
        case "$name" in ''|*[!A-Za-z0-9_]*) break ;; esac
        [ "$name" = APD_ORCHESTRATOR_COMMIT ] && [ "${w#*=}" = 1 ] && STMT_MARK=true
        _setvar "$name" "$(_subst "${w#*=}")"; i=$((i + 1)); continue ;;
      for|select)
        # `for NAME in a b c`: the loop variable takes the candidate that is NOT
        # in scope if there is one (so the body's write on it is refused), else
        # the first — a glob like `src/*.cs` is judged as the path string it is.
        if [ $((i + 2)) -lt $n ] && [ "${ST[$((i + 2))]}" = "in" ]; then
          name="${ST[$((i + 1))]}"; w=""; last=""
          for ((a = i + 3; a < n; a++)); do
            [ -z "$last" ] && last="${ST[$a]}"
            body=$(_subst "${ST[$a]}")
            if _unresolved "$body"; then w="${ST[$a]}"; break; fi
            case "$body" in /*|"~"|"~/"*) abs=$(_canon_cached "$body") ;; *) abs=$(_canon_cached "$body" "$CUR_CWD") ;; esac
            if ! _in_scope "$abs"; then w="${ST[$a]}"; break; fi
          done
          case "$name" in ''|*[!A-Za-z0-9_]*) ;; *) _setvar "$name" "${w:-$last}" ;; esac
          i=$n; continue
        fi
        i=$((i + 1)); continue ;;
      if|then|else|elif|fi|while|until|do|done|in|case|esac|'{'|'}'|'!'|function|coproc|time|export|local|declare|typeset|readonly|command|builtin|exec|nohup|caffeinate)
        i=$((i + 1)); continue ;;
      sudo|doas)
        i=$((i + 1))
        while [ $i -lt $n ]; do
          case "${ST[$i]}" in
            -u|-g|-p|-h|-C|-D|-r|-t|-U) i=$((i + 2)) ;;
            -*) i=$((i + 1)) ;;
            *) break ;;
          esac
        done; continue ;;
      nice|ionice)
        i=$((i + 1))
        while [ $i -lt $n ]; do
          case "${ST[$i]}" in -n|-c|-p) i=$((i + 2)) ;; -*) i=$((i + 1)) ;; *) break ;; esac
        done; continue ;;
      timeout)
        i=$((i + 1))
        while [ $i -lt $n ]; do
          case "${ST[$i]}" in -k|-s|--kill-after|--signal) i=$((i + 2)) ;; -*) i=$((i + 1)) ;; *) i=$((i + 1)); break ;; esac   # last: the DURATION
        done; continue ;;
      env)
        i=$((i + 1))
        while [ $i -lt $n ]; do
          case "${ST[$i]}" in -u|-C|-S|--unset|--chdir) i=$((i + 2)) ;; -*) i=$((i + 1)) ;; *) break ;; esac
        done; continue ;;
      xargs)
        # the command's targets come from stdin: not visible → fail closed
        STMT_XARGS=true; i=$((i + 1))
        while [ $i -lt $n ]; do
          case "${ST[$i]}" in -I|-n|-P|-L|-s|-d|-E|-a) i=$((i + 2)) ;; -*) i=$((i + 1)) ;; *) break ;; esac
        done
        case "${ST[$i]:-}" in
          cp|mv|rm|rmdir|mkdir|touch|tee|sed|perl|install|dd|ln|truncate|chmod|chown|rsync|git)
            _add_unknown_target "xargs ${ST[$i]}" ;;
        esac
        continue ;;
    esac
    break
  done
  cmd=""; [ $i -lt $n ] && cmd="${ST[$i]}"
  A=()
  if [ $((i + 1)) -lt $n ]; then A=("${ST[@]:$((i + 1))}"); fi

  if [ "$EMIT_WORDS" = true ]; then   # v7.2.3: one W line per statement — the command word by basename, a leading backslash dropped
    _wc="${cmd##*/}"; _wc="${_wc#\\}"
    if [ "${APD_GBS_DATA:-}" = 1 ]; then printf 'N'; else printf 'W'; fi   # N = a statement inside a DATA substitution (its leading `$` is the substitution itself, not a command)
    [ "$STMT_XARGS" = true ] && printf '\x1fxargs'
    printf '\x1f%s' "${_wc//$'\n'/$'\x1e'}"; for a in ${A[@]+"${A[@]}"}; do printf '\x1f%s' "${a//$'\n'/$'\x1e'}"; done; printf '\n'
  fi

  STMT_APD=false
  # v7.1.4 (audit N1): a VARIABLE in command position (`CMD="rm …"; $CMD`,
  # `"$@"`). Expand this command's own assignments and re-parse the statement;
  # a command word that is still a variable or positional after that is a body
  # the guard cannot read — refused for every caller.
  case "$cmd" in
    '$'|'$('*|'`'*)   # a command substitution in command position (the tokenizer emits `$` then a subshell): the inner command is visible (audit F2)…
      # …but its OUTPUT is the command that runs (audit R1): refuse when the command names the cache or the pipeline dir
      # (v7.2.3: unless this parse is the DATA text of a quoted substitution — see _recurse_shell)
      # (audit B2: inside a `(`…`)` group of a data text — `"$($(cat <fence>))"` — the inner substitution's output RUNS)
      if { [ "${APD_GBS_DATA:-}" != 1 ] || [ ${#CWD_STACK[@]} -gt 0 ]; } && _names_fenced_dir; then TARGET_RAW+=("${cmd:0:60}"); TARGET_ABS+=(""); { _emit_opaque; }; TARGET_NOTE+=("opaque shell body: ${cmd:0:40}"); TARGET_APD+=("${STMT_APD:-false}"); return 0; fi ;;
    *\\*)   # (v7.1.7, audit C2) an undecoded escape in the command word hides the writer
      TARGET_RAW+=("${cmd:0:60}"); TARGET_ABS+=(""); { _emit_opaque; }; TARGET_NOTE+=("opaque shell body: ${cmd:0:40}"); TARGET_APD+=("${STMT_APD:-false}"); return 0 ;;
    \$*)
      text=$(_subst "$cmd${A[@]+ ${A[*]}}")
      case "${text#"${text%%[! ]*}"}" in
        \$*) TARGET_RAW+=("${cmd:0:60}"); TARGET_ABS+=(""); { _emit_opaque; }; TARGET_NOTE+=("opaque shell body: ${cmd:0:40}"); TARGET_APD+=("${STMT_APD:-false}"); return 0 ;;
      esac
      APD_GBS_DATA= _recurse_shell "$text"; return 0 ;;
  esac
  # v7.1.4 (audit M-a/M-a2): APD's own tools, by command word — and the
  # exemption from the pipeline fence covers only THIS statement's targets
  # (`apd pipeline status; rm -rf .apd/pipeline` no longer rides along).
  # (audit P2) anchored to the plugin's own paths: a foreign executable that
  # merely ends in `pipeline-gate` owns nothing.
  STMT_APD=false
  case "$cmd" in
    bash|sh) _apd_tool_word "${A[0]:-}" "${A[1]:-}" && STMT_APD=true ;;
    *)       _apd_tool_word "$cmd" "${A[0]:-}" && STMT_APD=true ;;
  esac
  # v7.1.5: guard-git borrows this parser. One line per git STATEMENT (after
  # wrappers, assignments and keywords are stepped), words tab-separated so a
  # quoted argument stays one word; a heredoc fed to git travels as GITBODY.
  if [ "$EMIT_GIT" = true ]; then
    # (audit) a substitution ANYWHERE in the statement is executed by the shell
    # and invisible here → OPAQUE; a bare `$` word is the tokenizer's own mark
    # for a substitution in command position.
    for a in "$cmd" ${A[@]+"${A[@]}"}; do
      case "$a" in *'$('*|*'`'*|'$') printf 'OPAQUE\n'; break ;; esac
    done
    # git by any spelling and behind ANY wrapper: EVERY word that is `git` or
    # ends in `/git` starts a statement (xcrun git, /usr/bin/git, find -exec
    # git …; `runuser -u git -- git commit` — the user name is a git word too,
    # so both are emitted and the real one is judged: audit pass #2 B). Words
    # are unit-separator delimited so a quoted argument — even an EMPTY one
    # (`git -C ""`) — stays one word; a newline inside a word becomes 0x1e so
    # the line is not cut (audit A); a literal 0x1f inside a word is opaque.
    _W=("$cmd" ${A[@]+"${A[@]}"}); _k=0
    for a in "${_W[@]}"; do case "$a" in *$'\x1f'*|*\\*|'@APD_MARK') printf 'OPAQUE\n' ;; esac; done   # a backslash is an escape the guard did not decode (audit P3: bash 5 runs git \$'\u0070ush' --force); a user word spelled like the marker is unreadable (pass 2)
    while [ $_k -lt ${#_W[@]} ]; do
      a="${_W[$_k]}"
      if [ "$a" = git ] || [ "${a##*/}" = git ]; then
        printf 'GIT'; [ "$STMT_MARK" = true ] && printf '\x1f@APD_MARK'; _j=$((_k + 1))   # v7.2.3: the statement's own marker travels with it (audit G1: a raw-text regex was satisfied by a comment)
        while [ $_j -lt ${#_W[@]} ]; do _w="${_W[$_j]}"; printf '\x1f%s' "${_w//$'\n'/$'\x1e'}"; _j=$((_j + 1)); done; printf '\n'
        [ -n "$HB" ] && printf 'GITBODY\x1f%s\n' "$(printf '%s' "$HB" | tr '\n' ' ')"
      fi
      _k=$((_k + 1))
    done
  fi

  case "$cmd" in
    cd)
      _positionals '^$'
      w=""; [ ${#NF[@]} -gt 0 ] && w="${NF[0]}"
      case "$w" in
        ''|'~') CUR_CWD="$HOME"; CWD_UNKNOWN=false ;;
        -)      CWD_UNKNOWN=true ;;
        *)      w=$(_subst "$w")
                if _unresolved "$w"; then CWD_UNKNOWN=true
                else CUR_CWD=$(_canon_cached "$w" "$CUR_CWD"); CWD_UNKNOWN=false; fi ;;
      esac ;;
    pushd)
      _positionals '^$'
      w=""; [ ${#NF[@]} -gt 0 ] && w="${NF[0]}"
      DIR_STACK+=("$CUR_CWD|$CWD_UNKNOWN")
      case "$w" in
        '') ;;   # pushd with no operand swaps the top two: keep it simple, cwd unknown
        *)  w=$(_subst "$w")
            if _unresolved "$w"; then CWD_UNKNOWN=true
            else CUR_CWD=$(_canon_cached "$w" "$CUR_CWD"); CWD_UNKNOWN=false; fi ;;
      esac
      [ -z "$w" ] && CWD_UNKNOWN=true ;;
    popd)
      if [ ${#DIR_STACK[@]} -gt 0 ]; then
        w="${DIR_STACK[$((${#DIR_STACK[@]} - 1))]}"
        CUR_CWD="${w%|*}"; CWD_UNKNOWN="${w##*|}"
        unset "DIR_STACK[$((${#DIR_STACK[@]} - 1))]"
      else
        CWD_UNKNOWN=true
      fi ;;
    cp|install)
      # GNU `-t DIR` / `--target-directory=DIR`: the directory is the target
      w=""
      for ((last = 0; last < ${#A[@]}; last++)); do
        case "${A[$last]}" in
          -t|--target-directory) w="${A[$((last + 1))]:-}" ;;
          --target-directory=*)  w="${A[$last]#--target-directory=}" ;;
        esac
      done
      if [ -n "$w" ]; then _add_target "$w"
      else
        _positionals '^(-t|--target-directory|-m|-o|-g|--mode|--owner|--group)$'
        [ ${#NF[@]} -gt 0 ] && _add_target "${NF[$((${#NF[@]} - 1))]}"
      fi ;;
    mv)
      # every positional: the source leaves its place, so it is a write too
      _positionals '^(-t|--target-directory)$'
      for a in ${NF[@]+"${NF[@]}"}; do _add_target "$a"; done
      for ((last = 0; last < ${#A[@]}; last++)); do
        case "${A[$last]}" in
          -t|--target-directory) _add_target "${A[$((last + 1))]:-}" ;;
          --target-directory=*)  _add_target "${A[$last]#--target-directory=}" ;;
        esac
      done ;;
    mkdir)
      _positionals '^(-m|--mode)$'
      for a in ${NF[@]+"${NF[@]}"}; do _add_target "$a"; done ;;
    touch)
      _positionals '^(-t|-r|-d|--date|--reference)$'
      for a in ${NF[@]+"${NF[@]}"}; do _add_target "$a"; done ;;
    rm|rmdir|tee|unlink|chmod|chown|chgrp|truncate|ln|rsync|shred)
      case "$cmd" in
        chmod|chown|chgrp) _positionals '^(--reference)$'; NF=(${NF[@]+"${NF[@]:1}"}) ;;   # first positional is the mode/owner
        truncate)          _positionals '^(-s|-r|--size|--reference)$' ;;
        rsync)             _positionals '^(-e|--rsh|--exclude|--include|--filter|--files-from|--log-file)$'
                           [ ${#NF[@]} -gt 0 ] && NF=("${NF[$((${#NF[@]} - 1))]}") ;;   # destination only
        ln)                _positionals '^(-t|--target-directory|-S|--suffix)$'
                           # `ln [-s] target linkname`: the LINK is created; with one operand it lands in cwd
                           if [ ${#NF[@]} -ge 2 ]; then NF=("${NF[$((${#NF[@]} - 1))]}"); elif [ ${#NF[@]} -eq 1 ]; then NF=("${NF[0]##*/}"); fi ;;
        *)                 _positionals '^$' ;;
      esac
      case "$cmd" in
        rm|rmdir|unlink) for a in ${NF[@]+"${NF[@]}"}; do _add_target "$a" nofollow; done ;;
        *)               for a in ${NF[@]+"${NF[@]}"}; do _add_target "$a"; done ;;
      esac ;;
    dd)
      for a in ${A[@]+"${A[@]}"}; do case "$a" in of=*) _add_target "${a#of=}" ;; esac; done ;;
    curl|wget)
      for ((last = 0; last < ${#A[@]}; last++)); do
        case "${A[$last]}" in
          -o|--output|-O|--output-document) _add_target "${A[$((last + 1))]:-}" ;;
          --output=*|--output-document=*)   _add_target "${A[$last]#*=}" ;;
          -o*) [ "$cmd" = curl ] && _add_target "${A[$last]#-o}" ;;
          -O*) [ "$cmd" = wget ] && [ "${A[$last]}" != "-O" ] && _add_target "${A[$last]#-O}" ;;
        esac
      done
      { [ "$cmd" = wget ] && ! printf '%s\n' ${A[@]+"${A[@]}"} | grep -qE '^(-O|--output-document)'; } && _add_target "./" ;;
    sort)
      for ((last = 0; last < ${#A[@]}; last++)); do
        case "${A[$last]}" in -o|--output) _add_target "${A[$((last + 1))]:-}" ;; --output=*) _add_target "${A[$last]#*=}" ;; -o?*) _add_target "${A[$last]#-o}" ;; esac
      done ;;
    tar|unzip)
      w=""
      for ((last = 0; last < ${#A[@]}; last++)); do
        case "${A[$last]}" in
          -C|--directory|-d) w="${A[$((last + 1))]:-}" ;;
          --directory=*) w="${A[$last]#*=}" ;;
        esac
      done
      body=false
      case "$cmd" in
        tar) for a in ${A[@]+"${A[@]}"}; do case "$a" in --extract|-*x*) body=true ;; [a-zA-Z]*x*) body=true ;; esac; done ;;   # `tar xf`, `tar -xf`, `tar -C d -xf`
        unzip) body=true ;;
      esac
      if [ "$body" = true ]; then _add_target "${w:-./}"; fi ;;
    sed)
      inplace=false; has_expr=false
      for a in ${A[@]+"${A[@]}"}; do
        case "$a" in
          --in-place*) inplace=true ;;
          -e|--expression|-f|--file) has_expr=true ;;
          -e?*|-f?*) has_expr=true ;;
          -[A-Za-z]*) case "$a" in *i*) inplace=true ;; esac ;;     # -i, -Ei, -ri, -ni, -i.bak …
        esac
      done
      if [ "$inplace" = true ]; then
        seen_pat=false; expect_expr=false
        for a in ${A[@]+"${A[@]}"}; do
          if [ "$expect_expr" = true ]; then expect_expr=false; continue; fi
          case "$a" in
            '') continue ;;                                   # BSD `-i ''` empty suffix
            -e|--expression|-f|--file) expect_expr=true; continue ;;
            -*) continue ;;
          esac
          if [ "$has_expr" = false ] && [ "$seen_pat" = false ]; then seen_pat=true; continue; fi
          _add_target "$a"
        done
      fi ;;
    perl)
      inplace=false
      for a in ${A[@]+"${A[@]}"}; do case "$a" in -i*|-[a-zA-Z0-9]*i*) case "$a" in -e|-E) ;; *) inplace=true ;; esac ;; esac; done
      if [ "$inplace" = true ]; then
        expect_expr=false
        for a in ${A[@]+"${A[@]}"}; do
          if [ "$expect_expr" = true ]; then expect_expr=false; continue; fi
          case "$a" in -e|-E|-M|-m) expect_expr=true; continue ;; -*) continue ;; esac
          _add_target "$a"
        done
      else
        text=""; expect_expr=false
        for a in ${A[@]+"${A[@]}"}; do
          if [ "$expect_expr" = true ]; then text="${text}${a}"$'\n'; expect_expr=false; continue; fi
          case "$a" in -e|-E) expect_expr=true ;; esac
        done
        [ -n "$HB" ] && text="${text}${HB}"
        text="${text//$'\x1e'/$'\n'}"
        [ -n "$text" ] && _rt_write perl "$text" && _rt_mark "$text"$'\n'"${A[*]}"
      fi ;;
    git)
      w=""; [ ${#A[@]} -gt 0 ] && w="${A[0]}"
      case "$w" in
        rm|mv|restore|clean)
          A=(${A[@]+"${A[@]:1}"}); _positionals '^(--source|--pathspec-from-file)$'
          for a in ${NF[@]+"${NF[@]}"}; do _add_target "$a"; done
          [ "$w" = clean ] && [ ${#NF[@]} -eq 0 ] && _add_target "./" ;;
        checkout)
          # `git checkout -- <paths>` / `git checkout <ref> -- <paths>` overwrite working files
          if printf '%s\n' ${A[@]+"${A[@]}"} | grep -qx -- '--'; then
            body=false
            for a in ${A[@]+"${A[@]:1}"}; do
              if [ "$body" = true ]; then _add_target "$a"; elif [ "$a" = "--" ]; then body=true; fi
            done
          fi ;;
      esac ;;
    eval)
      APD_GBS_DATA= _recurse_shell "${A[*]}" ;;
    bash|sh|zsh|dash|su)
      # `-c <string>` is shell (su -c too); a heredoc-fed shell is shell; a script file is not readable here
      text=""; w=false
      for a in ${A[@]+"${A[@]}"}; do
        if [ "$w" = true ]; then text="$a"; break; fi
        case "$a" in -c) w=true ;; -c?*) text="${a#-c}"; break ;; esac
      done
      [ -z "$text" ] && [ -n "$HB" ] && text="$HB"
      [ -n "$text" ] && APD_GBS_DATA= _recurse_shell "$text" ;;
    python|python2|python3|node|nodejs|ruby|php)
      case "$cmd" in python*) lang=python ;; node*) lang=node ;; ruby) lang=ruby ;; php) lang=php ;; esac
      text=""; w=false
      for a in ${A[@]+"${A[@]}"}; do
        if [ "$w" = true ]; then text="${text}${a}"$'\n'; w=false; continue; fi
        case "$a" in
          -c|-e|-r|--eval|--print|-p) w=true ;;
          --eval=*|--print=*) text="${text}${a#*=}"$'\n' ;;
          -c?*|-e?*|-r?*) text="${text}${a#-?}"$'\n' ;;       # glued: python3 -c"…", node -e"…"
        esac
      done
      # program on stdin: heredoc body, unless a script file was named
      if [ -n "$HB" ]; then
        _positionals '^(-c|-e|-r|--eval|-m|-W|-X|-r|-d)$'
        last=""; for a in ${NF[@]+"${NF[@]}"}; do [ "$a" != "-" ] && last="$a"; done
        [ -z "$last" ] && text="${text}${HB}"
      fi
      # argv after the program is part of the write surface (audit I5)
      text="${text//$'\x1e'/$'\n'}"
      [ -n "$text" ] && _rt_write "$lang" "$text" && _rt_mark "$text"$'\n'"${A[*]}" ;;
    find)
      # `find <roots> … -delete | -exec <writeop> …`: the roots are what gets written
      body=false
      for a in ${A[@]+"${A[@]}"}; do
        case "$a" in
          -delete) body=true ;;
          -exec|-execdir|-ok|-okdir)
            last=$(printf '%s\n' ${A[@]+"${A[@]}"} | grep -A1 -x -- "$a" | tail -1)
            case "$last" in cp|mv|rm|rmdir|mkdir|touch|tee|sed|perl|install|dd|ln|truncate|chmod|chown|rsync|sh|bash) body=true ;; esac ;;
        esac
      done
      if [ "$body" = true ]; then
        NF=()
        for a in ${A[@]+"${A[@]}"}; do case "$a" in -*|'('|'!') break ;; *) NF+=("$a") ;; esac; done
        [ ${#NF[@]} -eq 0 ] && NF=("./")
        for a in "${NF[@]}"; do _add_target "$a"; done
      fi ;;
  esac
  for a in ${RT[@]+"${RT[@]}"}; do _add_target "$a"; done
  return 0
}

_TOKENIZER='
function emit_word() {
  if (nsub) { emit_n(substr(tok, nstart)); nsub = 0 }
  if (have) { gsub(/\n/, "\036", tok); if (rd) { print "R " tok; rd = 0 } else { print "W " tok } }   # a newline INSIDE a quoted token would cut the line protocol (audit pass #2 A): carry it as 0x1e
  tok = ""; have = 0
}
function emit(t, v) { print t " " v }
function emit_n(v) { gsub(/\n/, "\036", v); print "N " v }   # v7.1.7: a substitution inside double quotes — its text is a command of its own
function prep_parens(l,   i, c, qs, sp, st, n2) {
  # v7.2 (audit P1, pass 2): one left-to-right pass per line that contains "$((" — the matching
  # close of every "(" (quotes and backslashes honoured) goes into cp[open]. is_arith() then
  # answers in O(1), so a line of unclosed "$((" is linear, not quadratic (830 of them on 10 KB
  # took 8.6 s with a per-call scan — past the 5 s hook timeout, and a timed-out hook does not block).
  delete cp; sp = 0; qs = ""; n2 = length(l); i = 1
  while (i <= n2) {
    c = substr(l, i, 1)
    if (qs != "") { if (c == "\\" && qs == "\042") i++; else if (c == qs) qs = ""; i++; continue }
    if (c == "\\") { i += 2; continue }
    if (c == "\047" || c == "\042") { qs = c; i++; continue }
    if (c == "(") { st[++sp] = i }
    else if (c == ")") { if (sp > 0) { cp[st[sp]] = i; sp-- } }
    i++
  }
}
function is_arith(l, p) {
  # v7.2 (audit P1): "$((" at p is arithmetic only when the inner "(" closes right before the
  # outer one closes ("))" adjacent); bash tries arithmetic first and falls back to a
  # substitution of a subshell — `$((echo x > a) )` writes a file. -1 = the close is not on
  # this line (unreadable here; the consumer fails closed as OPENARITH).
  if (!((p + 1) in cp) || !((p + 2) in cp)) return -1
  return (cp[p + 2] + 1 == cp[p + 1])
}
function cont_sub(l, i,   c, n2) {
  # v7.2 (audit pass 3): continue an OPEN substitution of an unquoted heredoc body (state in
  # bsub/bsubd/bsubq/bsubesc/bsubtxt) from position i; returns the index after its close, or
  # length+1 with bsub still set when the line ends inside it (the body goes on next line).
  n2 = length(l)
  while (i <= n2) {
    c = substr(l, i, 1); pv = substr(bsubtxt, length(bsubtxt), 1); bsubtxt = bsubtxt c
    if (bsubesc) { bsubesc = 0; i++; continue }
    if (bsubq != "") { if (c == "\\" && (bsubq == "\042" || bsubq == "A")) bsubesc = 1; else if (c == (bsubq == "A" ? "\047" : bsubq)) bsubq = ""; i++; continue }
    if (c == "\\") { bsubesc = 1; i++; continue }
    # v7.2 (audit pass 4): a `)` inside a comment or an ANSI-C word does not close the substitution —
    # a comment runs to the end of the line (kept in the text; the nested tokenizer drops it), an
    # ANSI-C word honours the escaped quote. (A bare `case` pattern `a)` is a stated limit.)
    if (c == "#" && (pv == "" || pv == "(" || pv == " " || pv == "\t" || pv == "\n" || pv == ";" || pv == "|" || pv == "&")) { bsubtxt = bsubtxt substr(l, i + 1) "\n"; return n2 + 1 }
    if (c == "$" && substr(l, i + 1, 1) == "\047") { bsubtxt = bsubtxt "\047"; bsubq = "A"; i += 2; continue }
    if (c == "\047" || c == "\042") { bsubq = c; i++; continue }
    if (bsub == 1) { if (c == "(") bsubd++; else if (c == ")") { bsubd--; if (bsubd == 0) { emit_n(bsubtxt); bsub = 0; bsubtxt = ""; return i + 1 } } }
    else if (c == "`") { emit_n(substr(bsubtxt, 2, length(bsubtxt) - 2)); bsub = 0; bsubtxt = ""; return i + 1 }   # the INNER text: a leading backtick is an unresolvable word to the consumer (pre-existing, fail closed)
    i++
  }
  bsubtxt = bsubtxt "\n"
  return n2 + 1
}
function scan_subs(l,   i, c, n2) {
  # v7.2 (audit I4): an UNQUOTED heredoc body is expanded by bash — every `$(…)` and backtick in it
  # RUNS. The body stays data (HB), but each substitution goes out as an N record for the nested
  # parse. `$((` is arithmetic expansion (skipped as an opener; a `$(` inside it is still found).
  # pass 2: a backslash quotes the next char, `$$` is the pid. pass 3: a substitution that spans
  # body LINES is carried as state (cont_sub) and emitted at its close — or at the terminator.
  n2 = length(l); i = 1
  if (bsub) { i = cont_sub(l, i); if (bsub) return }
  while (i <= n2) {
    c = substr(l, i, 1)
    if (c == "\\") { i += 2; continue }                              # pass 2: `\$(…)`, `\`` in an unquoted body are LITERAL (the script-writing idiom)
    if (c == "$" && substr(l, i + 1, 1) == "$") { i += 2; continue }   # pass 2: `$$` is the pid — `$$(…)` opens nothing
    if (c == "$" && substr(l, i + 1, 1) == "(" && substr(l, i + 2, 1) != "(") {
      bsub = 1; bsubd = 1; bsubq = ""; bsubesc = 0; bsubtxt = "$("
      i = cont_sub(l, i + 2); if (bsub) return
      continue
    }
    if (c == "`") {
      bsub = 2; bsubq = ""; bsubesc = 0; bsubtxt = "`"
      i = cont_sub(l, i + 1); if (bsub) return
      continue
    }
    i++
  }
}
BEGIN { q = 0; esc = 0; tok = ""; have = 0; rd = 0; skip = 0; pending = 0; hd_tag = ""; hd_strip = 0; hd_quoted = 0; arith = 0; insub = 0; subd = 0; subq = 0; subesc = 0; nsub = 0; nstart = 0; subarith = 0; bsub = 0; bsubd = 0; bsubq = ""; bsubesc = 0; bsubtxt = "" }
{
  line = $0
  sub(/\r$/, "", line)
  if (index(line, "$((") > 0) prep_parens(line)
  if (skip) {
    chk = line
    if (hd_strip) sub(/^\t+/, "", chk)
    if (chk == hd_tag) { if (bsub) { emit_n(bsub == 2 ? substr(bsubtxt, 2) : bsubtxt); bsub = 0; bsubtxt = "" }; skip = 0; emit("HE", ""); next }   # pass 3: a substitution still open at the terminator goes out as collected
    emit("HB", line); if (!hd_quoted) scan_subs(line); next
  }
  n = length(line); i = 1
  while (i <= n) {
    c = substr(line, i, 1)
    if (insub) {
      # v7.1.7 (audit b): a substitution inside double quotes — bash runs the inner text; it
      # used to vanish into the word. The text is kept IN the word (guard-git still sees the
      # dollar-paren) and, once the quoted segment closes, everything from the dollar-paren to
      # the end of that segment goes out as an N record for the consumer to re-parse as shell
      # (audit I2: a comment, a case pattern or a heredoc inside it can hide a paren, so the
      # nested parse gets the whole tail, not the paren-balanced slice). Inner quotes and
      # escapes are honoured only to find the end of the segment; lines are crossed.
      tok = tok c; have = 1
      if (subesc) { subesc = 0; i++; continue }
      if (subq) { if (c == "\\" && subq == 2) subesc = 1; else if ((subq == 1 && c == "\047") || (subq == 2 && c == "\042")) subq = 0; i++; continue }
      if (c == "\\") { subesc = 1; i++; continue }
      if (c == "\047") { subq = 1; i++; continue }
      if (c == "\042") { subq = 2; i++; continue }
      if (insub == 1) { if (c == "(") subd++; else if (c == ")") { subd--; if (subd == 0) insub = 0 } }
      else if (c == "`") insub = 0
      if (!insub && subarith) { emit_n(substr(tok, nstart)); nsub = 0; subarith = 0 }   # v7.2 (audit I3): opened from arithmetic — no quote close will emit it
      i++; continue
    }
    if (q == 1) { if (c == "\047") q = 0; else tok = tok c; have = 1; i++; continue }
    if (q == 2) {
      if (esc) { tok = tok c; esc = 0 }
      else if (c == "\\") { esc = 1 }
      else if (c == "\042") { q = 0; if (nsub) { emit_n(substr(tok, nstart)); nsub = 0 } }
      else if (c == "$" && substr(line, i + 1, 1) == "(" && (substr(line, i + 2, 1) != "(" || is_arith(line, i) != 1)) { if (!nsub) { nsub = 1; nstart = length(tok) + 1 }; tok = tok "$("; have = 1; insub = 1; subd = 1; i += 2; continue }
      else if (c == "`") { if (!nsub) { nsub = 1; nstart = length(tok) + 1 }; tok = tok "`"; have = 1; insub = 2; i++; continue }
      else { tok = tok c }
      have = 1; i++; continue
    }
    if (q == 3) {
      # v7.1.7 (audit a): ANSI-C quoting (dollar-quote): backslash-quote is an escaped quote, not
      # the end of the word. Escapes are DECODED (audit I3: an escaped slash in a path spelled the
      # fence): quote, backslash, double quote, n t r a b e f v, x-hex and octal; anything else
      # keeps the backslash, and a target or command word that still carries one is refused.
      if (esc) {
        esc = 0
        if (c == "\047" || c == "\\" || c == "\042") tok = tok c
        else if (c == "n") tok = tok "\n"
        else if (c == "t") tok = tok "\t"
        else if (c == "r") tok = tok "\r"
        else if (c == "a") tok = tok sprintf("%c", 7)
        else if (c == "b") tok = tok sprintf("%c", 8)
        else if (c == "e" || c == "E") tok = tok sprintf("%c", 27)
        else if (c == "f") tok = tok sprintf("%c", 12)
        else if (c == "v") tok = tok sprintf("%c", 11)
        else if (c == "x") {
          v = 0; d = 0
          while (d < 2 && (h = index("0123456789abcdef", tolower(substr(line, i + 1 + d, 1)))) > 0) { v = v * 16 + h - 1; d++ }
          if (d == 0 || v == 0) tok = tok "\\x"; else { tok = tok sprintf("%c", v); i += d }
        }
        else if (c ~ /[0-7]/) {
          v = c + 0; d = 1
          while (d < 3 && substr(line, i + d, 1) ~ /[0-7]/) { v = v * 8 + substr(line, i + d, 1); d++ }
          if (v == 0) tok = tok "\\" c; else { tok = tok sprintf("%c", v); i += d - 1 }
        }
        else tok = tok "\\" c
      }
      else if (c == "\\") { esc = 1 }
      else if (c == "\047") { q = 0 }
      else { tok = tok c }
      have = 1; i++; continue
    }
    if (esc) { tok = tok c; have = 1; esc = 0; i++; continue }
    if (c == "\\") { esc = 1; i++; continue }
    if (c == "$" && substr(line, i + 1, 1) == "\047") {
      # v7.1.7 (audit C1): only a dollar that is not the second of a pair opens ANSI-C quoting —
      # a double dollar is the shell pid, and the quote after it is an ordinary single quote
      k = 0; j = i - 1
      while (j >= 1 && substr(line, j, 1) == "$") { k++; j-- }
      if (k % 2 == 1) { tok = tok c; have = 1; i++; continue }
      q = 3; have = 1; i += 2; continue
    }
    if (c == "\047") { q = 1; have = 1; i++; continue }
    if (c == "\042") { q = 2; have = 1; i++; continue }
    if (arith > 0) {
      # v7.2 (audit I3): a command substitution INSIDE arithmetic runs before the expression is
      # evaluated — `$(( $(cmd) ))`, `(( $(cmd) ))`, `for ((i=$(cmd);…))`, `a[$(cmd)]`. Capture it as
      # the quoted path does and send it out as an N record when it closes.
      if (c == "$" && substr(line, i + 1, 1) == "(" && substr(line, i + 2, 1) != "(") { if (!nsub) { nsub = 1; nstart = length(tok) + 1 }; tok = tok "$("; have = 1; insub = 1; subd = 1; subarith = 1; i += 2; continue }
      if (c == "`") { if (!nsub) { nsub = 1; nstart = length(tok) + 1 }; tok = tok "`"; have = 1; insub = 2; subarith = 1; i++; continue }
      if (c == ")" && substr(line, i + 1, 1) == ")") { arith--; tok = tok "))"; have = 1; i += 2; continue }
      if (c == "(" && substr(line, i + 1, 1) == "(") { arith++; tok = tok "(("; have = 1; i += 2; continue }
      if (c == " " || c == "\t") { tok = tok c; have = 1; i++; continue }
      tok = tok c; have = 1; i++; continue
    }
    if (c == "$" && substr(line, i + 1, 2) == "((") {
      ia = is_arith(line, i)
      if (ia == 1) { arith++; tok = tok "$(("; have = 1; i += 3; continue }
      if (ia == -1) { emit_word(); emit("S", "OPENARITH") }   # v7.2 (audit I1): closes on a later line — unreadable; the groups below still parse the text of this line
      # v7.2 (audit P1): not arithmetic — a substitution of a subshell. Open the two groups here:
      # left to the "(" path, a bare "((" with no word pending reads as an arithmetic COMMAND.
      emit_word(); emit("S", "("); emit("S", "("); i += 3; continue
    }
    if (c == "(" && substr(line, i + 1, 1) == "(" && !have) { arith++; tok = "(("; have = 1; i += 2; continue }
    if (c == "#" && !have) break
    if (c == " " || c == "\t") { emit_word(); i++; continue }
    if (c == ";") { emit_word(); emit("S", ";"); i++; continue }
    if (c == "(") { emit_word(); emit("S", "("); i++; continue }
    if (c == ")") { emit_word(); emit("S", ")"); i++; continue }
    if (c == "{" && !have && (substr(line, i + 1, 1) == " " || substr(line, i + 1, 1) == "\t" || i == n)) { emit("W", "{"); i++; continue }
    if (c == "}" && !have && (i == n || substr(line, i + 1, 1) ~ /[ \t;&|)]/)) { emit("W", "}"); i++; continue }
    if (c == "|") {
      emit_word()
      if (substr(line, i + 1, 1) == "|") { emit("S", "||"); i += 2 } else if (substr(line, i + 1, 1) == "&") { emit("S", "|"); i += 2 } else { emit("S", "|"); i++ }
      continue
    }
    if (c == "&") {
      nx = substr(line, i + 1, 1)
      if (nx == "&") { emit_word(); emit("S", "&&"); i += 2; continue }
      if (nx == ">") {
        emit_word(); i += 2
        if (substr(line, i, 1) == ">") i++
        while (substr(line, i, 1) == " " || substr(line, i, 1) == "\t") i++
        rd = 1; continue
      }
      emit_word(); emit("S", "&"); i++; continue
    }
    if (c == "<") {
      if (substr(line, i + 1, 2) == "<<") { i += 3; continue }
      if (substr(line, i + 1, 1) == "<") {
        i += 2; strip = 0
        if (substr(line, i, 1) == "-") { strip = 1; i++ }
        while (substr(line, i, 1) == " " || substr(line, i, 1) == "\t") i++
        # v7.2 (audit P2): the tag is a bash WORD — a quoted segment, a double-quoted segment, a
        # backslash + char and bare text may mix (NO apostrophes in this comment: the program is a
        # single-quoted bash string). Read it segment by segment: a quoted segment to its closing quote, a
        # backslash + next char, bare text to a delimiter. A quote still open at the end of
        # the line spans lines — bash keeps reading the COMMAND; unreadable here → fail closed.
        tag = ""; opentag = 0; hd_q = 0
        while (i <= n) {
          ch = substr(line, i, 1)
          if (ch == "$" && substr(line, i + 1, 1) == "\047") {
            # v7.2 (audit I2): an ANSI-C segment in the tag — decoded like the q==3 path; an escape this
            # reader does not decode makes the tag unreadable (fail closed)
            hd_q = 1; i += 2
            while (i <= n && substr(line, i, 1) != "\047") {
              ch2 = substr(line, i, 1)
              if (ch2 == "\\") {
                e2 = substr(line, i + 1, 1)
                if (e2 == "\047" || e2 == "\\" || e2 == "\042") tag = tag e2
                else if (e2 == "t") tag = tag "\t"
                else if (e2 == "n") tag = tag "\n"
                else if (e2 == "r") tag = tag "\r"
                else { opentag = 1; break }
                i += 2; continue
              }
              tag = tag ch2; i++
            }
            if (opentag || i > n) { opentag = 1; break }
            i++; continue
          }
          if (ch == "$" && substr(line, i + 1, 1) == "\042") { i++; continue }   # v7.2 (audit I2): $"…" is a plain double-quoted segment
          if (ch == "\047" || ch == "\042") {
            qq = ch; i++; hd_q = 1
            while (i <= n && substr(line, i, 1) != qq) {
              if (qq == "\042" && substr(line, i, 1) == "\\" && substr(line, i + 1, 1) ~ /["\\$`]/) { tag = tag substr(line, i + 1, 1); i += 2; continue }   # v7.2 (audit M1): \" inside "…"
              tag = tag substr(line, i, 1); i++
            }
            if (i > n) { opentag = 1; break }
            i++; continue
          }
          if (ch == "\\") { if (i == n) { opentag = 1; break }; tag = tag substr(line, i + 1, 1); i += 2; hd_q = 1; continue }
          if (ch ~ /[ \t;|&<>()]/) break
          tag = tag ch; i++
        }
        if (opentag) { emit("S", "OPENTAG"); continue }
        if (!pending) { hd_tag = tag; hd_strip = strip; hd_quoted = hd_q; pending = 1; emit("HS", tag) }
        continue
      }
      if (substr(line, i + 1, 1) == "(") { i++; continue }
      i++; continue
    }
    if (c == ">") {
      prev = (i > 1) ? substr(line, i - 1, 1) : ""
      nx = substr(line, i + 1, 1)
      if (prev == "=" || prev == "-" || nx == "=") { tok = tok c; have = 1; i++; continue }
      if (have && tok ~ /^[0-9]+$/) { tok = ""; have = 0 } else if (have && tok ~ /^\{[A-Za-z_][A-Za-z0-9_]*\}$/) { tok = ""; have = 0 } else emit_word()
      i++
      if (substr(line, i, 1) == ">") i++
      if (substr(line, i, 1) == "|") i++
      if (substr(line, i, 1) == "&") {
        i++
        if (substr(line, i, 1) ~ /[0-9-]/) { i++; continue }
      }
      while (substr(line, i, 1) == " " || substr(line, i, 1) == "\t") i++
      if (substr(line, i, 1) == "(") { rd = 0; continue }
      rd = 1; continue
    }
    tok = tok c; have = 1; i++
  }
  if (esc && q != 1) { esc = 0; next }        # backslash-newline: the word continues on the next line
  if (insub) { tok = tok "\n"; next }                # (v7.1.7) a quoted substitution spans the line
  if (q != 0) { tok = tok "\n"; have = 1; next }   # (v7.1.5, audit pass #3) a quoted word spans the line: bash keeps reading it, so do we
  emit_word(); rd = 0
  emit("S", "NL")
  if (pending) { skip = 1; pending = 0 }
}
END { if (nsub) emit_n(substr(tok, nstart)); emit_word(); if (q != 0) emit("S", "OPENQ"); emit("S", "END") }   # unterminated quote: bash refuses the text; guard-git must not read it. END = the canary (v7.2, audit I5): an awk that died mid-parse leaves no END, and the consumer then fails closed
'

_flush_stmt() {
  if [ "$ST_HAS_HD" = true ] && [ "$DEF_SET" = false ]; then
    # this statement owns the heredoc: defer until its body has arrived
    DEF_ST=(${ST[@]+"${ST[@]}"}); DEF_RT=(${RT[@]+"${RT[@]}"}); DEF_SET=true
  else
    _process_stmt
  fi
  ST=(); RT=(); ST_HAS_HD=false
}
_flush_deferred() {
  if [ "$DEF_SET" = true ]; then
    ST=(${DEF_ST[@]+"${DEF_ST[@]}"}); RT=(${DEF_RT[@]+"${DEF_RT[@]}"})
    _process_stmt
    ST=(); RT=(); DEF_ST=(); DEF_RT=(); DEF_SET=false
  fi
  HB=""; HD_PENDING=false
}

N_CWDS=(); N_TXTS=()
while IFS= read -r _tline; do
  _ttype="${_tline%% *}"
  case "$_tline" in *" "*) _tval="${_tline#* }" ;; *) _tval="" ;; esac
  case "$_ttype" in
    W)  ST+=("$_tval") ;;
    R)  RT+=("$_tval") ;;
    N)  # v7.1.7: a substitution inside double quotes runs — judged like a nested shell, ONE nested
        # parse per working directory per command (audit I1: one spawn per substitution cost 6 s
        # on 120 of them). guard-git keeps its OPAQUE through the word itself.
        if [ "$EMIT_GIT" != true ]; then
          _k=0; _hit=-1
          while [ $_k -lt ${#N_CWDS[@]} ]; do [ "${N_CWDS[$_k]}" = "$CUR_CWD|$CWD_UNKNOWN" ] && { _hit=$_k; break; }; _k=$((_k + 1)); done
          if [ $_hit -ge 0 ]; then N_TXTS[$_hit]="${N_TXTS[$_hit]}"$'\x1e'"$_tval"; else N_CWDS+=("$CUR_CWD|$CWD_UNKNOWN"); N_TXTS+=("$_tval"); fi
        fi ;;
    HS) HD_PENDING=true; ST_HAS_HD=true ;;
    HB) HB="${HB}${_tval}"$'\n' ;;
    HE) _flush_deferred ;;
    S)
      case "$_tval" in
        NL) _flush_stmt
            [ "$HD_PENDING" = true ] || _flush_deferred ;;
        OPENQ) _emit_opaque; _flush_stmt ;;
        OPENTAG)   # v7.1.7: a heredoc tag spanning lines — the statement's real shape is unreadable here
             _add_unknown_target "heredoc tag spanning lines"
             if _names_fenced_dir; then TARGET_RAW+=("heredoc tag spanning lines"); TARGET_ABS+=(""); TARGET_NOTE+=("opaque shell body: heredoc tag spanning lines"); TARGET_APD+=("${STMT_APD:-false}"); fi ;;
        OPENARITH)   # v7.2 (audit I1): a `$((` whose close sits on a later line — arithmetic or a subshell substitution, unreadable here
             _emit_opaque
             _add_unknown_target "arithmetic or subshell substitution spanning lines"
             if _names_fenced_dir; then TARGET_RAW+=("substitution spanning lines"); TARGET_ABS+=(""); TARGET_NOTE+=("opaque shell body: arithmetic or subshell substitution spanning lines"); TARGET_APD+=("${STMT_APD:-false}"); fi ;;
        END) SAW_END=true ;;
        "(") _flush_stmt; CWD_STACK+=("$CUR_CWD|$CWD_UNKNOWN") ;;
        ")") _flush_stmt
             if [ ${#CWD_STACK[@]} -gt 0 ]; then
               _top="${CWD_STACK[$((${#CWD_STACK[@]} - 1))]}"
               CUR_CWD="${_top%|*}"; CWD_UNKNOWN="${_top##*|}"
               unset "CWD_STACK[$((${#CWD_STACK[@]} - 1))]"
             fi ;;
        *)  _flush_stmt ;;
      esac ;;
  esac
done < <(printf '%s\n' "$COMMAND" | LC_ALL=C awk "$_TOKENIZER")
_flush_stmt
# v7.2 (audit I5): the tokenizer's END record is the canary. macOS awk dies on a lone multibyte
# byte under a UTF-8 locale (LC_ALL=C above removes that trigger); whatever kills it, a
# tokenizer that stopped mid-command read only part of the command — fail closed: the
# scoped agent is refused, guard-git falls back to the raw scan, the orchestrator is refused
# when the command names a fence.
if [ "${SAW_END:-false}" != true ]; then
  _emit_opaque
  _add_unknown_target "command tokenizer stopped mid-command"
  if _names_fenced_dir; then TARGET_RAW+=("unreadable command"); TARGET_ABS+=(""); TARGET_NOTE+=("opaque shell body: the tokenizer stopped mid-command"); TARGET_APD+=("false"); fi
fi
_flush_deferred
if [ "$EMIT_GIT" != true ] && [ ${#N_CWDS[@]} -gt 0 ]; then   # (v7.1.7) the quoted substitutions, re-parsed once per working directory
  _k=0; _save_cwd="$CUR_CWD"; _save_unk="$CWD_UNKNOWN"
  while [ $_k -lt ${#N_CWDS[@]} ]; do
    CUR_CWD="${N_CWDS[$_k]%|*}"; CWD_UNKNOWN="${N_CWDS[$_k]##*|}"
    # v7.2.3: output is data — the inner command is judged, not refused for naming a fence. A
    # backtick record carries its INNER text, which is a command line in command position:
    # "`$(cat <fence>)`" runs the file's content (audit B2) — parsed with data mode OFF.
    case "${N_TXTS[$_k]}" in
      '$('*) APD_GBS_DATA=1 _recurse_shell "${N_TXTS[$_k]}" ;;
      '`'*)  _bt="${N_TXTS[$_k]#\`}"; _bt="${_bt%\`}"; APD_GBS_DATA= _recurse_shell "$_bt" ;;   # the INNER command line runs; a leading $( in it is command position (R1 applies)
      *)     APD_GBS_DATA= _recurse_shell "${N_TXTS[$_k]}" ;;
    esac
    _k=$((_k + 1))
  done
  CUR_CWD="$_save_cwd"; CWD_UNKNOWN="$_save_unk"
fi

# --- 2. Decide ------------------------------------------------------------------
[ "$EMIT_GIT" = true ] && exit 0   # (v7.1.5) the statements are printed; judging is guard-git's job
if [ "$EMIT_WORDS" = true ]; then [ "${APD_GBS_DEPTH:-0}" -gt 0 ] || printf 'END\n'; exit 0; fi   # v7.2.3: END is the consumer's canary (top level only)
if [ ${#TARGET_RAW[@]} -eq 0 ] && [ "$RUNTIME_WRITE" = false ]; then
  exit 0
fi

# v7.1.4: the plugin cache is read-only for EVERY caller, judged on canonical
# targets (redirects, write ops, a `cd` into it, the paths a writing program
# names). A read of a plugin file, an exec from the cache, or a copy OUT of it
# is nobody's business here.
_plugin_cache_block() {  # <detail>
  echo "BLOCKED: Bash write to plugin cache directory." >&2
  echo "  Target: $1" >&2
  echo "  Plugin files are read-only. Do not modify." >&2
  log_block "plugin-cache-write" "${COMMAND:0:200}"
  exit 2
}
_opaque_block() {  # <detail> — a shell body the guard cannot read (audit C2)
  echo "BLOCKED: a shell was fed text the guard cannot read ($1)." >&2
  echo "  Write the command out instead of passing it through a variable or a substitution." >&2
  log_block "opaque-shell-body" "${COMMAND:0:200}"
  exit 2
}
_raw_spelling() {  # <raw word> → the substituted spelling with ~ expanded (audit I3: a symlinked ~/.claude/plugins loses /plugins/cache/ in canonical form)
  local r; r=$(_subst "$1")
  case "$r" in "~") r="$HOME" ;; "~/"*) r="$HOME/${r#\~/}" ;; esac
  printf '%s' "$r"
}
_i=0
while [ $_i -lt ${#TARGET_RAW[@]} ]; do
  _raw="${TARGET_RAW[$_i]}"; _abs="${TARGET_ABS[$_i]}"; _note="${TARGET_NOTE[$_i]}"; _i=$((_i + 1))
  case "$_note" in "opaque shell body"*) _opaque_block "$_note" ;; esac
  if [ -z "$_abs" ]; then
    # a writer whose targets the guard cannot see (xargs, find -exec) or an
    # unresolved variable: when the command names the plugin cache anywhere,
    # fail closed here too — the raw scan used to catch this shape.
    case "$COMMAND" in *plugins/cache*) _plugin_cache_block "$_raw (${_note:-unresolved}; the command names the plugin cache)" ;; esac
    continue
  fi
  _is_plugin_cache "$_abs" && _plugin_cache_block "$_raw (resolves to $_abs)"
  _is_plugin_cache "$(_raw_spelling "$_raw")" && _plugin_cache_block "$_raw (the plugin cache by its own spelling)"
done
if [ "$RUNTIME_WRITE" = true ]; then
  # audit C3/N2: a bare file name inside a writing program lands in the cwd of the moment
  [ "$RT_CWD_CACHE" = true ] && _plugin_cache_block "a writing program run from inside the plugin cache"
  while IFS= read -r _p; do
    [ -z "$_p" ] && continue
    case "$_p" in
      \$*) if ! _known_var "$(_var_name "$_p")"; then _p=$(_var_tail "$_p"); case "$_p" in */*) ;; *) continue ;; esac; fi ;;   # audit C4/F1/R2
      */*|"~"*) ;; *) continue ;;
    esac
    _s=$(_subst "$_p")
    if _unresolved "$_s"; then
      case "$COMMAND" in *plugins/cache*) _plugin_cache_block "$_p (unresolved in the program; the command names the plugin cache)" ;; esac
      continue
    fi
    case "$_s" in */*|"~"*) ;; *) continue ;; esac
    _is_plugin_cache "$_s" && _plugin_cache_block "$_p (the plugin cache by its own spelling)"
    case "$_s" in /*|"~"|"~/"*) _abs=$(_canon_cached "$_s") ;; *) _abs=$(_canon_cached "$_s" "$CUR_CWD") ;; esac
    _is_plugin_cache "$_abs" && _plugin_cache_block "$_p (named in the program)"
  done < <(printf '%s' "$RUNTIME_TEXT" | grep -oE "[\$~./A-Za-z0-9_-][A-Za-z0-9_./~{}\$-]*" 2>/dev/null || true)
fi

# PROTECT_ONLY (no scope = the orchestrator): only the pipeline dir is fenced.
if [ "$PROTECT_ONLY" = true ]; then
  # (audit P1) a nested shell (bash -c, eval, a heredoc-fed shell) that the
  # nested guard refused — for a scope-less caller that means the pipeline
  # dir, the cache, or an opaque body — is a refusal here too. It used to be
  # skipped as "unresolved", so `bash -c "rm -rf .apd/pipeline"` reached the ledger.
  _i=0
  while [ $_i -lt ${#TARGET_RAW[@]} ]; do
    case "${TARGET_NOTE[$_i]}" in
      "nested shell text"*)
        echo "BLOCKED: a nested shell (bash -c / eval / heredoc) writes where this caller may not: ${TARGET_RAW[$_i]}" >&2
        echo "  The nested command was refused on its own — run it at top level to see why, or drop it." >&2
        _pipeline_block_guidance
        log_block "nested-shell-refusal" "${COMMAND:0:200}"
        exit 2 ;;
    esac
    _i=$((_i + 1))
  done
  _PIPE_CANON="$PROJ_CANON/.apd/pipeline"
  _under_pipeline() { case "$1/" in "$_PIPE_CANON/"*) return 0 ;; esac; [ "$1" = "$_PIPE_CANON" ] && return 0; return 1; }
  _i=0
  while [ $_i -lt ${#TARGET_RAW[@]} ]; do
    _raw="${TARGET_RAW[$_i]}"; _abs="${TARGET_ABS[$_i]}"; _i=$((_i + 1))
    [ "${TARGET_APD[$((_i - 1))]:-false}" = true ] && continue   # an APD tool's own statement owns the pipeline dir (audit M-a2)
    [ -n "$_abs" ] || continue                      # unresolved: the orchestrator is not scoped
    case "${_abs##*/}" in .guide-marker) continue ;; esac
    if _under_pipeline "$_abs"; then
      echo "BLOCKED: Bash write to protected pipeline state directory." >&2
      echo "  Target: $_raw (resolves to $_abs)" >&2
      _pipeline_block_guidance
      log_block "pipeline-state-write" "${COMMAND:0:200}"
      exit 2
    fi
  done
  if [ "$RUNTIME_WRITE" = true ]; then
    while IFS= read -r _p; do
      [ -z "$_p" ] && continue
      case "$_p" in */*|"~"*|.apd*) ;; *) continue ;; esac
      _s=$(_subst "$_p"); _unresolved "$_s" && continue
      case "$_s" in /*|"~"|"~/"*) _abs=$(_canon_cached "$_s") ;; *) _abs=$(_canon_cached "$_s" "$CUR_CWD") ;; esac
      if _under_pipeline "$_abs"; then
        echo "BLOCKED: Runtime write to protected pipeline state directory." >&2
        _pipeline_block_guidance
        log_block "pipeline-state-write" "${COMMAND:0:200}"
        exit 2
      fi
    done < <(printf '%s' "$RUNTIME_TEXT" | grep -oE "[~./A-Za-z0-9_-][A-Za-z0-9_./~-]*" 2>/dev/null || true)
  fi
  exit 0
fi

_block() {  # <detail line>
  echo "BLOCKED: Bash command writes outside the allowed scope." >&2
  [ -n "$1" ] && echo "  $1" >&2
  _scope_hint
  log_block "out-of-scope-bash-write" "${COMMAND:0:200}"
  exit 2
}

_i=0
while [ $_i -lt ${#TARGET_RAW[@]} ]; do
  _raw="${TARGET_RAW[$_i]}"; _abs="${TARGET_ABS[$_i]}"; _note="${TARGET_NOTE[$_i]}"
  _i=$((_i + 1))
  case "$_note" in "opaque shell body"*) _opaque_block "$_note" ;; esac
  if [ -n "$_note" ]; then
    # a write the guard cannot place is refused (for an agent with no scope
    # everything outside the scratchpad is refused anyway, below)
    _block "Out-of-scope target: $_raw ($_note — cannot be resolved, so it is refused)"
  fi
  if _has_traversal "$_abs"; then
    _block "Out-of-scope target: $_raw (unresolved path traversal in $_abs)"
  fi
  if [ "$DENY_ALL_WRITES" = true ] && [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
    # no writable scope at all: only the session scratchpad is sanctioned
    _is_session_scratchpad "$_abs" && continue
    echo "BLOCKED: Bash command writes, and this agent has no writable scope." >&2
    echo "  Target: $_raw" >&2
    _scope_hint
    log_block "out-of-scope-bash-write" "${COMMAND:0:200}"
    exit 2
  fi
  if ! _in_scope "$_abs"; then
    if [ "$_raw" = "$_abs" ]; then _block "Out-of-scope target: $_raw"
    else _block "Out-of-scope target: $_raw (resolves to $_abs)"; fi
  fi
done

# Runtime writes: the target lives inside a program. Every path-shaped token
# the program mentions must be in scope or in the scratchpad (a read of an
# out-of-scope file inside a WRITING program is refused too — fail-closed; the
# old "any in-scope token allows" rule let `shutil.copy('src/a','/tmp/a')`
# through, audit I4), and the program must run from a working directory that
# is itself in scope, because a bare file name resolves there (audit I6).
if [ "$RUNTIME_WRITE" = true ]; then
  # v7.2.3 (audit B1, pass 2): a NEW top-level name is reachable through any call that creates,
  # renames, copies a tree, extracts, installs, or shells out — not only mkdir. With none of
  # these in the program, a name whose first component does not exist cannot receive a write.
  RT_MKDIR=false; printf '%s' "$RUNTIME_TEXT" | grep -qE 'makedirs|mkdir|mkpath|MkdirAll|create_dir|ensureDir|ensure_dir|FileUtils|rename|move|copytree|copy2|copyfile|copy\(|copyFile|cpSync|extract|unpack|install|system\(|subprocess|spawn|exec|popen|shell_exec|passthru|(^|[^A-Za-z])(cp|mv|tar|rsync|unzip|install|ditto) ' && RT_MKDIR=true
  # v7.2.3: text that yields path-shaped tokens that are not paths is removed BEFORE the
  # token scan — HTML/XML tags (`</td>` → `/td`), URLs (`https://x/y` → `//x/y`), and
  # quoted regex literals that carry a regex metacharacter (`"/^ \[x/"`, `"/\n\];\n/s"`,
  # `"#^/users/(\d+)$#"`); `"/tmp/x"` has no metacharacter and stays a path.
  # (pass 2: a regex literal is recognised only by a BACKSLASH escape inside it, a `^` right after
  # the opening delimiter or a `$` right before the closing one — `"/tmp/$d/out"`, f"/tmp/{n}/out",
  # '/tmp/a+b/log' are paths and stay; `file://` is a path scheme Node and Python accept — not a URL here)
  _RT_SCAN=$(printf '%s' "$RUNTIME_TEXT" | LC_ALL=C sed -E 's#[Ff][Ii][Ll][Ee]://[A-Za-z0-9.-]*/#/#g; s#</?[A-Za-z][A-Za-z0-9:-]*># #g; s#(https?|ftps?|ssh|git|s3|gs|wss?|rsync|svn|smb|ldap|data)://[^[:space:]"'"'"']*# #g; s#"/(\^[^"]*|[^"]*\\[^"]*|[^"]*\$)/[a-zA-Z]{0,5}"# #g; s#'"'"'/(\^[^'"'"']*|[^'"'"']*\\[^'"'"']*|[^'"'"']*\$)/[a-zA-Z]{0,5}'"'"'# #g; s@"#(\^[^"#]*|[^"#]*\\[^"#]*|[^"#]*\$)#[a-zA-Z]{0,5}"@ @g' 2>/dev/null || printf '%s' "$RUNTIME_TEXT")
  # An agent with NO scope may not run a program that writes, even one that
  # writes into the scratchpad. v7.2.4 tried judging such a program by the
  # token rule (audit-724 F1: the scratchpad write was refused) and the second
  # audit pass showed what that rule does not see — bare names, string
  # concatenation, `.`, argv, library calls: `open('<sp>/x','w');
  # open('evil.py','w')` passed. Scoped agents carry that weakness (stated);
  # the agent with no scope stays the strict caller. Send a program's output
  # into the scratchpad with a redirect instead.
  if [ "$DENY_ALL_WRITES" = true ] && [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
    echo "BLOCKED: Runtime write (runtime) detected, and this agent has no writable scope." >&2
    echo "  A program that writes files is refused for an agent with no scope, even into the" >&2
    echo "  scratchpad — redirect its output there instead (python3 x.py > <scratchpad>/out)." >&2
    _scope_hint; log_block "out-of-scope-bash-write" "${COMMAND:0:200}"; exit 2
  fi
  # Where would a BARE file name land? In the working directory. A cwd outside
  # the project (or unknown) refuses the program outright; a cwd inside the
  # project but outside the scope refuses it only when the program names no
  # path at all (then every name is bare). Named paths are judged one by one.
  _cwd_ok="$RT_CWD_ALL_IN_SCOPE"; _cwd_in_proj="$RT_CWD_ALL_IN_PROJ"   # judged at mark time (audit N2)
  if [ "$RT_CWD_UNKNOWN" = true ] || { [ "$_cwd_ok" = false ] && [ "$_cwd_in_proj" = false ]; }; then
    echo "BLOCKED: Runtime write (runtime) detected from a working directory outside the project ($CUR_CWD)." >&2
    _scope_hint; log_block "out-of-scope-bash-write" "${COMMAND:0:200}"; exit 2
  fi
  _any=false
  while IFS= read -r _p; do
    [ -z "$_p" ] && continue
    _tail=false
    case "$_p" in
      \$*) if ! _known_var "$(_var_name "$_p")"; then _p=$(_var_tail "$_p"); _tail=true; case "$_p" in */*) ;; *) continue ;; esac; fi ;;   # audit C4/F1/R2
      */*|"~"*) ;;
      *) continue ;;
    esac
    _s=$(_subst "$_p")
    if _unresolved "$_s"; then
      echo "BLOCKED: Runtime write (runtime) detected with a path the guard cannot resolve ($_p)." >&2
      _scope_hint; log_block "out-of-scope-bash-write" "${COMMAND:0:200}"; exit 2
    fi
    case "$_s" in */*|"~"*) ;; *) continue ;; esac
    # v7.2.3 (live, efiskalizacija ×4): tokens a program text yields that are not
    # paths at all — regex delimiters (`"/^foo/"` → `/`, `"/x/s"` → `/x/`), the PHP
    # `//` comment, HTML closing tags (`</td>` → `/td`). A lone slash run is never a
    # write target, and nothing can be written under a TOP-LEVEL name that does not
    # exist on this machine (creating one needs root) — such a token is not judged.
    # Stated limit: a root container could `os.makedirs('/x')` first.
    # A RELATIVE fragment reads the same way (`\n\];\n/s` → `n/s`, `\[x/` → `x/`):
    # judged only when its first component exists under the program's cwd. The
    # exemption is OFF when the program also creates directories (`makedirs`,
    # `mkdir`, `mkpath`, `MkdirAll` …) — then a new top-level name is reachable.
    # (a tail after an UNKNOWN variable is a suffix, not a path from the root, and a
    # token with `..` can be normalised onto an existing directory — neither is exempt)
    _trav=false; _has_traversal "$_s" && _trav=true
    # (pass 4/5) `//x/y` is `/x/y` on POSIX AND a file-URL body whose host is `x` (`new URL('file:' +
    # '//localhost/etc/x')`): both readings are judged (audit pass 5: dropping the host alone let
    # `open('//etc/x')` through as `/x`)
    _cands=("$_s")
    case "$_s" in //[!/]*) _c2="${_s#//}"; _cands=("/$_c2"); case "$_c2" in */*) _cands+=("/${_c2#*/}") ;; esac ;; esac
    for _s in "${_cands[@]}"; do
    case "$_s" in
      /|//|///|/dev/null) continue ;;
      /*) if [ "$RT_MKDIR" != true ] && [ "$_tail" != true ] && [ "$_trav" != true ]; then _first="${_s#/}"; _first="${_first#/}"; _first="/${_first%%/*}"; [ "$_first" = / ] || [ -e "$_first" ] || continue; fi ;;
    esac
    # (audit B1, passes 2–4: a RELATIVE name is ALWAYS judged, as at HEAD. A creator-call list
    # missed 18 spellings in one pass and a "whole quoted argument" rule was escaped by any
    # indirection (`'build/' + n`, a variable, a template literal) while re-introducing the
    # MIME / date / template-name false blocks. The live shapes — regex delimiters, `//`,
    # `</td>` — are handled by _RT_SCAN and the lone-slash rule, not by an exemption. Stated
    # false blocks, = HEAD: `render('users/index')`, `'Content-Type: text/html'`, `date("Y/m/d")`
    # next to an in-scope write.)
    _any=true
    case "$_s" in /*|"~"|"~/"*) _abs=$(_canon_cached "$_s") ;; *) _abs=$(_canon_cached "$_s" "$CUR_CWD") ;; esac
    # v7.2.3: a `..` that survives canonicalisation (a non-existent segment before it) would
    # be compared as a PREFIX of the scope while landing elsewhere — refuse it, as the
    # Write guard does for its targets.
    if _has_traversal "$_abs"; then
      echo "BLOCKED: Runtime write (runtime) detected with an unresolved traversal in the program ($_p)." >&2
      _scope_hint; log_block "out-of-scope-bash-write" "${COMMAND:0:200}"; exit 2
    fi
    if ! _in_scope "$_abs"; then
      echo "BLOCKED: Runtime write (runtime) detected outside the allowed scope." >&2
      echo "  Out-of-scope path in the program: $_p" >&2
      _scope_hint; log_block "out-of-scope-bash-write" "${COMMAND:0:200}"; exit 2
    fi
    done   # candidates of one token
  done < <(printf '%s' "$_RT_SCAN" | grep -oE "[\$~./A-Za-z0-9_-][A-Za-z0-9_./~{}\$-]*" 2>/dev/null || true)
  if [ "$_any" = false ] && [ "$_cwd_ok" = false ]; then
    echo "BLOCKED: Runtime write (runtime) with bare file names, from a working directory outside the allowed scope ($CUR_CWD)." >&2
    _scope_hint; log_block "out-of-scope-bash-write" "${COMMAND:0:200}"; exit 2
  fi
  exit 0
fi

exit 0
