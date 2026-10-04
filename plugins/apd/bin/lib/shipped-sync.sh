#!/bin/bash
# APD shipped-copy sync — one mechanism for every file the framework COPIES
# into a project and later changes.
#
# WHY THIS EXISTS
# A file copied into a project at setup stops following the framework the
# moment it lands. v7.1.6 solved that for `.claude/rules/workflow.md` alone: the
# shipped copy the project took is RECORDED, and whenever the framework's file
# changes init merges the change into the project's copy with `git merge-file`
# (base = the record, ours = the project's copy, theirs = the new shipped
# text). Every other copied file kept its older rule — "written once", or
# "refreshed when a marker is missing" — and v7.2.4 showed what that costs: it
# changed the three review-agent templates and no installed project received
# the text, while init raised APD_VERSION and `apd audit-drift` (which compares
# the version, not the content) said CLEAN. Measured on PLAZMA 2026-10-03.
#
# This file is that v7.1.6 state machine, parameterised, so that workflow.md,
# the review agents, the builder charter and the Codex-side copies all go
# through ONE implementation (init) and are read by ONE registry
# (init + audit-drift) — the two cannot disagree about what is tracked.
#
# CALLER CONTRACT (`_shipped_sync`)
# The caller provides `ok`, `warn`, `fix` (style.sh), `FIXES`, `APD_VER`, and
# sets these before the call (all reset by `_ss_reset`):
#   SS_LABEL          name used in every message            ("workflow.md")
#   SS_SHIPPED        the framework's text for THIS project (a rendered file)
#   SS_PROJECT        the project's copy
#   SS_RECORD         the shipped-copy record
#   SS_LOCK           lock directory (one merge at a time)
#   SS_DISP_PROJECT   the copy's path as shown to the user
#   SS_DISP_RECORD    the record's path as shown to the user
#   SS_HANDMERGE      the by-hand merge recipe (conflict / merge error)
#   SS_MSG_CONFLICT   text after "copy left untouched. Resolve by hand: <recipe>"
#   SS_MSG_NOGIT      text after "git is not available to merge it"
#   SS_MSG_NORECORD   text after "…no shipped-copy record to merge from. "
#   SS_STALE_FN       optional: prints a reason when the copy is damaged/stale
#   SS_HISTORY_KEY    optional: key into templates/shipped-history (see below)
#   SS_CANON_NAME     optional: the project name the render substituted
#   SS_KIND           optional: the render kind (agent|plain|cdxname) — with
#                     SS_HISTORY_KEY it enables the nearest-ancestor merge
#   SS_BACKUP_SRC     optional: the file to back up instead of SS_PROJECT
#   SS_PINS_FROM      optional: the project copy whose model:/effort: lines are
#                     carried onto the record before it is compared and merged
#                     (done AFTER the lock is taken — audit-730 F7); the record
#                     itself is still written at SS_RECORD
#   SS_PIN_DEFAULTS   optional: the CURRENT template — the source of a pin line
#                     the project's copy does not have
#   SS_DEFER_RECORD   "true" → the record is written as <record>.pending; the
#                     caller commits it after it has applied SS_PROJECT elsewhere
#   SS_CREATE         "true" → a missing copy is created from SS_SHIPPED
# Result in SS_RESULT: ok | held | refreshed | merged | conflict | error |
# norecord | foreign | created | skipped.
#
# NO RECORD (every project set up before this mechanism): the copy is compared
# with the texts the framework shipped in EARLIER versions, by hash
# (`templates/shipped-history`, one `key sha256` per line, written from the git
# tags by `bin/core/shipped-history`). A copy that equals an earlier shipped
# text carries no local edit, so it is refreshed (with a backup) and the record
# starts. A copy that matches none carries local edits: the plugin also ships
# the earlier TEXTS (`templates/shipped-history.d/<key>/<sha>.md`, canonical
# form), the nearest one is taken as the merge base, and the framework's changes
# since it are merged in around the edits. Only a copy with no usable ancestor
# (or a conflicting merge) is left alone and reported.

_ss_reset() {
    SS_LABEL=""; SS_SHIPPED=""; SS_PROJECT=""; SS_RECORD=""; SS_LOCK=""
    SS_DISP_PROJECT=""; SS_DISP_RECORD=""; SS_HANDMERGE=""
    SS_MSG_CONFLICT=""; SS_MSG_NOGIT=""; SS_MSG_NORECORD=""
    SS_STALE_FN=""; SS_HISTORY_KEY=""; SS_CANON_NAME=""; SS_BACKUP_SRC=""; SS_PINS_FROM=""; SS_PIN_DEFAULTS=""; SS_KIND=""; SS_DEFER_RECORD=false; SS_CREATE=false
    SS_RESULT=""
}

# _ss_sha256 — hash of stdin (shasum on macOS, sha256sum on a bare Linux)
_ss_sha256() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
    else sha256sum | cut -d' ' -f1; fi
}

# _ss_canon <file> [<project-name>] — the text as the framework shipped it:
#   * the project's name put back to `{{PROJECT_NAME}}` (a literal replace);
#   * the frontmatter `model:` / `effort:` VALUES blanked — `apd profile` and
#     init's pin repair own those two lines, so they are not part of the text;
#   * CRLF read as LF, a UTF-8 BOM dropped.
# The same function canonicalises a template (no name given) and a project's
# copy, so equal canonical text means "this copy is that shipped text".
_ss_canon() {
    APD_SS_NAME="${2:-}" LC_ALL=C awk '
        BEGIN { name = ENVIRON["APD_SS_NAME"]; ph = "{{PROJECT_NAME}}" }
        { sub(/\r$/, "") }
        NR == 1 { sub(/^\357\273\277/, "") }
        NR == 1 && $0 ~ /^---[ \t]*$/ { fm = 1; print; next }
        fm && $0 ~ /^---[ \t]*$/ { fm = 0; print; next }
        fm && $0 ~ /^model:/  { print "model:";  next }
        fm && $0 ~ /^effort:/ { print "effort:"; next }
        {
            if (name != "") {
                out = ""; s = $0
                while ((i = index(s, name)) > 0) { out = out substr(s, 1, i - 1) ph; s = substr(s, i + length(name)) }
                $0 = out s
            }
            print
        }
    ' "$1" 2>/dev/null
}

# _ss_history_has <key> <file> [<project-name>] [<kind>] — 0 when the copy equals
# a text the framework shipped under <key> in some earlier version: by canonical
# hash, or (with <kind>) by comparing it with each stored text rendered for the
# project.
_ss_history_has() {
    local hist="$APD_PLUGIN_ROOT/templates/shipped-history" h kind="${4:-}" dir f tmp
    if [ -f "$hist" ]; then
        h=$(_ss_canon "$2" "${3:-}" | _ss_sha256)
        [ -n "$h" ] && grep -qxF "$1 $h" "$hist" 2>/dev/null && return 0
    fi
    # v7.3.1: the canonical form puts the project's name back to the placeholder
    # WHEREVER it occurs, so a short name that is also a piece of ordinary text
    # ("ro", "api", "app") never hashes to a shipped text. Where the earlier
    # texts themselves are shipped, compare the copy with each one rendered for
    # this project — the render substitutes only the placeholder.
    dir="$APD_PLUGIN_ROOT/templates/shipped-history.d/$1"
    [ -n "$kind" ] && [ -d "$dir" ] || return 1
    tmp=$(mktemp -t apd-sshist.XXXXXX 2>/dev/null) || return 1
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        _ss_render "$kind" "$f" "$2" "$tmp" || continue
        if cmp -s "$tmp" "$2"; then rm -f "$tmp" "$tmp.pins" "$tmp.like"; return 0; fi
    done
    rm -f "$tmp" "$tmp.pins" "$tmp.like"
    return 1
}

# _ss_carry_pins <rendered-file> <project-copy> [<current template>] — rewrite
# the rendered text so its frontmatter `model:` / `effort:` lines are the
# PROJECT's; a line the project does not have takes the current template's. Those lines belong to `apd profile` and init's pin repair; without
# this every profile switch would read as a framework change and every repin as
# a conflict with the profile's line.
_ss_carry_pins() {
    local rendered="$1" proj="$2" defaults="${3:-${SS_PIN_DEFAULTS:-}}" m="" e="" dm="" de="" tmp
    _ss_pin() {   # <file> <key> → that frontmatter line, CR stripped
        [ -f "$1" ] || return 0
        LC_ALL=C awk -v k="^$2:" 'NR==1 { sub(/^\357\273\277/, "") } { sub(/\r$/, "") } NR==1 && /^---[ \t]*$/ {fm=1; next} fm && /^---[ \t]*$/ {exit} fm && $0 ~ k {print; exit}' "$1" 2>/dev/null
    }
    m=$(_ss_pin "$proj" model); e=$(_ss_pin "$proj" effort)
    dm=$(_ss_pin "$defaults" model); de=$(_ss_pin "$defaults" effort)
    # a pin the project does not carry falls back to the current template's —
    # never to a stored text's blank `model:` (audit-730 F4: base blank / ours no
    # line / theirs a value was a conflict on the pin alone)
    [ -n "$m" ] || m="$dm"; [ -n "$e" ] || e="$de"
    unset -f _ss_pin
    [ -n "$m$e" ] || return 0
    tmp="$rendered.pins"
    APD_SS_M="$m" APD_SS_E="$e" LC_ALL=C awk '
        BEGIN { m = ENVIRON["APD_SS_M"]; e = ENVIRON["APD_SS_E"] }
        NR == 1 && $0 ~ /^---[ \t]*$/ { fm = 1; print; next }
        fm && $0 ~ /^---[ \t]*$/ { fm = 0; print; next }
        fm && m != "" && $0 ~ /^model:/  { print m; next }
        fm && e != "" && $0 ~ /^effort:/ { print e; next }
        { print }
    ' "$rendered" > "$tmp" 2>/dev/null && mv "$tmp" "$rendered"
}

# _ss_record_state <record> → prints ok | none | dir  (one reading for init and
# audit-drift: a regular non-empty file is a record, a directory is a broken one)
_ss_record_state() {
    if [ -d "$1" ]; then printf 'dir'
    elif [ -f "$1" ] && [ -s "$1" ]; then printf 'ok'
    else printf 'none'; fi
}

_shipped_sync() {
    SS_RESULT=""
    local _ss_bsrc="${SS_BACKUP_SRC:-$SS_PROJECT}"
    local _ss_base="$SS_RECORD" _ss_basetmp="" _ss_arc=1
    local _ss_rec _ss_norec=false _ss_held=false _ss_done=false _ss_lock_stale=false
    local _ss_stale="" _ss_bakname="" _ss_merged="" _ss_mrc=0 _ss_bak _ss_delta _ss_recdir _ss_anc=""
    _ss_rec=$(_ss_record_state "$SS_RECORD")
    _ss_recdir=$(dirname "$SS_RECORD")

    # SS_DEFER_RECORD (the charter): the record is written as <record>.pending and
    # the CALLER moves it into place once the block is back in the agent. Written
    # here directly, an init killed between this write and the splice left the
    # record on the new text and the agent on the old one, and every later init
    # read that as "current, with local edits" (audit-730 pass 5, K1).
    _ss_write_record() {
        [ "$_ss_rec" = dir ] && return 1; [ "$_ss_norec" = true ] && return 1
        mkdir -p "$_ss_recdir" 2>/dev/null
        if [ "$SS_DEFER_RECORD" = true ]; then cp "$SS_SHIPPED" "$SS_RECORD.pending" 2>/dev/null
        else cp "$SS_SHIPPED" "$SS_RECORD" 2>/dev/null; fi
    }
    # (v7.1.6 audit F1 residual) never skip a backup — number the next one
    _ss_backup() {  # → _ss_bakname
        local b="$_ss_bsrc.bak.preaudit"; [ -e "$b" ] && b="$b.$(date +%s).$$"
        cp "$_ss_bsrc" "$b" 2>/dev/null && _ss_bakname=$(basename "$b")
    }
    # the per-version backup: the slot is first-wins, but only for the SAME
    # content — a slot already holding another text (an earlier refresh under
    # this version) would leave the copy replaced now in no file at all
    # (audit-730 pass 3). → _ss_bak names the file that holds the current copy.
    _ss_backup_ver() {
        _ss_bak="$_ss_bsrc.bak.pre-v$APD_VER"
        if [ -f "$_ss_bak" ]; then
            cmp -s "$_ss_bak" "$_ss_bsrc" && return 0
            _ss_bak="$_ss_bak.$(date +%s).$$"
        fi
        cp "$_ss_bsrc" "$_ss_bak" 2>/dev/null
    }
    _ss_copy_writable() { [ -w "$SS_PROJECT" ] && [ -w "$(dirname "$_ss_bsrc")" ]; }
    _ss_writable() {  # the copy, the backup directory AND the record
        _ss_copy_writable || return 1
        [ "$_ss_norec" = true ] && return 1
        if [ "$_ss_rec" = ok ]; then [ -w "$SS_RECORD" ]
        else [ "$_ss_rec" != dir ] && { [ -w "$_ss_recdir" ] || { [ ! -e "$_ss_recdir" ] && [ -w "$(dirname "$_ss_recdir")" ]; }; }; fi
    }

    # _ss_merge_from <base> <note> — three-way merge of the framework's change into
    # the copy (base → SS_SHIPPED applied onto SS_PROJECT). Never without a backup;
    # a conflict leaves the copy untouched. Used with the record as the base, and
    # (v7.3) with the nearest earlier shipped text when there is no record.
    _ss_merge_from() {
        local _mb="$1" _note="$2"
        if ! command -v git >/dev/null 2>&1; then
            warn "$SS_LABEL: the framework's text changed and git is not available to merge it$SS_MSG_NOGIT"
            SS_RESULT=error; return 0
        fi
        _ss_merged=$(mktemp -t apd-wfmerge.XXXXXX 2>/dev/null || echo "")
        if [ -z "$_ss_merged" ] || ! cp "$SS_PROJECT" "$_ss_merged" 2>/dev/null; then
            warn "$SS_LABEL: the framework's text changed but no temp file could be created for the merge (TMPDIR?) — copy left untouched"
            SS_RESULT=error
        else
            _ss_mrc=0
            git merge-file -L "project copy" -L "shipped when recorded" -L "shipped now" "$_ss_merged" "$_mb" "$SS_SHIPPED" >/dev/null 2>&1 || _ss_mrc=$?
            if [ "$_ss_mrc" -eq 0 ]; then
                if ! _ss_backup_ver; then
                    warn "$SS_LABEL: could not write the backup $(basename "$_ss_bak") — merge NOT applied (never without a backup)"
                    SS_RESULT=error
                elif ! cp "$_ss_merged" "$SS_PROJECT" 2>/dev/null; then
                    warn "$SS_LABEL: could not write $SS_DISP_PROJECT — merge NOT applied (backup kept)"
                    SS_RESULT=error
                elif ! _ss_write_record; then
                    warn "$SS_LABEL: merged, but $SS_DISP_RECORD could not be updated — it will be merged again until that file is writable"
                    SS_RESULT=error
                else
                    fix "$SS_LABEL: merged the framework's changes, local edits kept (backup: $(basename "$_ss_bak"))$_note"
                    FIXES=$((FIXES + 1)); SS_RESULT=merged
                fi
            elif [ "$_ss_mrc" -lt 128 ]; then
                # git merge-file returns the NUMBER of conflicts (1..127); anything higher is an error
                warn "$SS_LABEL: the framework's changes CONFLICT with local edits ($_ss_mrc hunk(s)) — copy left untouched. Resolve by hand: $SS_HANDMERGE$SS_MSG_CONFLICT"
                SS_RESULT=conflict
            else
                warn "$SS_LABEL: git merge-file failed (exit $_ss_mrc) — copy left untouched; by hand: $SS_HANDMERGE"
                SS_RESULT=error
            fi
        fi
        [ -n "$_ss_merged" ] && rm -f "$_ss_merged"
        return 0
    }

    if [ -f "$SS_PROJECT" ] && [ -f "$SS_SHIPPED" ]; then
        mkdir -p "$(dirname "$SS_LOCK")" 2>/dev/null || true
        [ "$_ss_rec" = dir ] && warn "$SS_LABEL: $SS_DISP_RECORD is a DIRECTORY — remove it (rmdir $SS_DISP_RECORD) so init can record the shipped copy; merges are off until then"
        # (v7.1.6 audit F4/F11) one holder at a time; a lock older than two
        # minutes is a dead run and is reclaimed, directory or stray file
        if { [ -e "$SS_LOCK" ] || [ -L "$SS_LOCK" ]; } && [ -n "$(find "$SS_LOCK" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
            _ss_lock_stale=true
            if [ -L "$SS_LOCK" ] || [ ! -d "$SS_LOCK" ]; then rm -f "$SS_LOCK" 2>/dev/null || true; else rmdir "$SS_LOCK" 2>/dev/null || true; fi
        fi
        if ! mkdir "$SS_LOCK" 2>/dev/null; then
            if [ -e "$SS_LOCK" ] || [ -L "$SS_LOCK" ]; then
                if [ "$_ss_lock_stale" = true ]; then
                    _ss_norec=true
                    warn "$SS_LABEL: a stale merge lock $SS_LOCK could not be removed (.apd/ not writable?) — the shipped-copy record and merges are off until that is fixed; stale-copy refresh still runs"
                else
                    _ss_held=true
                    ok "$SS_LABEL (another init holds the merge lock $SS_LOCK — left for that run; a lock older than 2 min is reclaimed)"
                    SS_RESULT=held
                fi
            else
                # (v7.1.6 audit F10) .apd/ itself is not writable (or is a file)
                _ss_norec=true
                warn "$SS_LABEL: cannot write under .apd/ ($PROJECT_DIR/.apd not writable, or not a directory) — the shipped-copy record and merges are off until that is fixed; stale-copy refresh still runs"
            fi
        fi
        if [ "$_ss_held" = false ]; then
            # the record, read AFTER the lock is ours (audit-730 F7: read before
            # it, a second init merged against the record the first had just
            # replaced). For an agent the record is compared with the project's
            # pins carried onto it.
            _ss_rec=$(_ss_record_state "$SS_RECORD")
            if [ -n "$SS_PINS_FROM" ] && [ "$_ss_rec" = ok ]; then
                _ss_basetmp=$(mktemp -t apd-ssbase.XXXXXX 2>/dev/null || echo "")
                if [ -n "$_ss_basetmp" ] && cp "$SS_RECORD" "$_ss_basetmp" 2>/dev/null; then
                    _ss_carry_pins "$_ss_basetmp" "$SS_PINS_FROM"; _ss_like "$_ss_basetmp" "$SS_PINS_FROM"; _ss_base="$_ss_basetmp"
                fi
            fi
            # 1. a damaged or stale copy is refreshed in EVERY state (v7.1.6 audit F1)
            [ -n "$SS_STALE_FN" ] && _ss_stale=$("$SS_STALE_FN")
            if [ -n "$_ss_stale" ]; then
                if ! _ss_copy_writable; then
                    warn "$SS_LABEL: $_ss_stale, but $SS_DISP_PROJECT or its directory is not writable — nothing changed"
                    SS_RESULT=error
                elif _ss_backup && cp "$SS_SHIPPED" "$SS_PROJECT" 2>/dev/null; then
                    fix "$SS_LABEL: refreshed ($_ss_stale; backup: $_ss_bakname)"
                    FIXES=$((FIXES + 1)); SS_RESULT=refreshed
                    if ! _ss_write_record && [ "$_ss_norec" = false ] && [ "$_ss_rec" != dir ]; then
                        warn "$SS_LABEL: the shipped-copy record $SS_DISP_RECORD could not be written — check permissions on .apd/"
                    fi
                else
                    warn "$SS_LABEL: $_ss_stale, but the backup or the copy could not be written${_ss_bakname:+ (backup made: $_ss_bakname)} — check permissions; it will be retried"
                    SS_RESULT=error
                fi
                _ss_done=true
            fi
            # 2. the record: merge the framework's changes forward
            if [ "$_ss_done" = true ] || [ "$_ss_rec" = dir ] || [ "$_ss_norec" = true ]; then
                :
            elif [ "$_ss_rec" = ok ] && ! cmp -s "$_ss_base" "$SS_SHIPPED"; then
                # the framework's text changed since this project last took it
                if ! _ss_writable; then
                    warn "$SS_LABEL: the framework's text changed, but $SS_DISP_PROJECT, its directory or $SS_DISP_RECORD is not writable — nothing changed"
                    SS_RESULT=error
                elif cmp -s "$SS_PROJECT" "$_ss_base"; then
                    # no local edits: a plain refresh; the record IS the backup
                    if cp "$SS_SHIPPED" "$SS_PROJECT" 2>/dev/null && _ss_write_record; then
                        fix "$SS_LABEL: refreshed from the shipped copy (framework text changed; no local edits)"
                        FIXES=$((FIXES + 1)); SS_RESULT=refreshed
                    else
                        warn "$SS_LABEL: refresh from the shipped copy FAILED (copy or $SS_DISP_RECORD not written) — check permissions; it will be retried"
                        SS_RESULT=error
                    fi
                else
                    _ss_merge_from "$_ss_base" ""
                fi
            elif [ "$_ss_rec" = ok ]; then
                ok "$SS_LABEL"   # framework unchanged since recorded; local edits, if any, are the project's (audit-drift reports them)
                SS_RESULT=ok
            elif cmp -s "$SS_PROJECT" "$SS_SHIPPED"; then
                if _ss_write_record; then ok "$SS_LABEL (shipped-copy record started: $SS_DISP_RECORD)"; SS_RESULT=ok
                else warn "$SS_LABEL: could not write the shipped-copy record $SS_DISP_RECORD (permissions?)"; SS_RESULT=error; fi
            elif [ -n "$SS_HISTORY_KEY" ] && _ss_history_has "$SS_HISTORY_KEY" "$SS_PROJECT" "$SS_CANON_NAME" "$SS_KIND"; then
                # No record, and the copy is a text the framework shipped in an
                # EARLIER version, unedited: there is nothing local to keep.
                _ss_bak="$_ss_bsrc.bak.pre-v$APD_VER"
                if ! _ss_writable; then
                    warn "$SS_LABEL: carries an older shipped text, but $SS_DISP_PROJECT, its directory or .apd/ is not writable — nothing changed"
                    SS_RESULT=error
                elif ! _ss_backup_ver; then
                    warn "$SS_LABEL: could not write the backup $(basename "$_ss_bak") — refresh NOT applied (never without a backup)"
                    SS_RESULT=error
                elif cp "$SS_SHIPPED" "$SS_PROJECT" 2>/dev/null && _ss_write_record; then
                    fix "$SS_LABEL: refreshed from the shipped copy (it carried an older shipped text with no local edits; backup: $(basename "$_ss_bak"))"
                    FIXES=$((FIXES + 1)); SS_RESULT=refreshed
                else
                    warn "$SS_LABEL: refresh from the shipped copy FAILED (copy or $SS_DISP_RECORD not written) — check permissions; it will be retried"
                    SS_RESULT=error
                fi
            else
                # No record and not an unedited shipped text. Three readings, told
                # apart by the texts the plugin ships for this key:
                #   0  made from a shipped text and edited → merge from the nearest
                #   2  nothing like any shipped text → the project's own file
                #   1  no texts stored for the key → reported
                _ss_arc=1
                if [ -n "$SS_HISTORY_KEY" ] && [ -n "$SS_KIND" ]; then
                    _ss_anc=$(mktemp -t apd-ssanc.XXXXXX 2>/dev/null || echo "")
                    if [ -n "$_ss_anc" ]; then _ss_ancestor "$SS_HISTORY_KEY" "$SS_KIND" "$SS_PROJECT" "$_ss_anc" "$SS_SHIPPED"; _ss_arc=$?; fi
                fi
                if [ "$_ss_arc" -eq 0 ]; then
                    if cmp -s "$_ss_anc" "$SS_SHIPPED"; then
                        # the edits were made on the CURRENT text: nothing to merge
                        if _ss_write_record; then ok "$SS_LABEL (local edits kept; shipped-copy record started: $SS_DISP_RECORD)"; SS_RESULT=ok
                        else warn "$SS_LABEL: could not write the shipped-copy record $SS_DISP_RECORD (permissions?)"; SS_RESULT=error; fi
                    elif ! _ss_writable; then
                        warn "$SS_LABEL: the framework's text changed since the text this copy was made from, but $SS_DISP_PROJECT, its directory or .apd/ is not writable — nothing changed"
                        SS_RESULT=error
                    else
                        _ss_merge_from "$_ss_anc" " — there was no record; merged from the nearest earlier shipped text"
                        # a conflict: keep the base it was merged against AS the record, so
                        # the by-hand recipe has all three files and the next run is the
                        # ordinary record path
                        if [ "$SS_RESULT" = conflict ]; then mkdir -p "$_ss_recdir" 2>/dev/null; cp "$_ss_anc" "$SS_RECORD" 2>/dev/null || true; fi
                    fi
                elif [ "$_ss_arc" -eq 2 ]; then
                    # (audit-730 F2) a file the framework never wrote — a hand-written
                    # AGENTS.md, a project's own reviewer. It is not a copy: no record,
                    # no merge, no warning on every init. Drift says so once, as INFO.
                    ok "$SS_LABEL (the project's own text — not derived from any text the framework shipped; left alone)"
                    SS_RESULT=foreign
                else
                    # No record and no stored text to merge from: REPORTED here — init
                    # runs at session start, audit-drift does not.
                    _ss_delta=$(diff "$SS_SHIPPED" "$SS_PROJECT" 2>/dev/null | grep -c '^[<>]') || true
                    warn "$SS_LABEL: differs from the shipped copy (${_ss_delta:-?} line(s)) and there is no shipped-copy record to merge from. $SS_MSG_NORECORD"
                    SS_RESULT=norecord
                fi
                [ -n "$_ss_anc" ] && rm -f "$_ss_anc" "$_ss_anc.try" "$_ss_anc.try.pins"
            fi
            [ -n "$_ss_basetmp" ] && rm -f "$_ss_basetmp" "$_ss_basetmp.pins"
            [ -d "$SS_LOCK" ] && { rmdir "$SS_LOCK" 2>/dev/null || true; }
        fi
    elif [ -f "$SS_SHIPPED" ] && [ "$SS_CREATE" = true ]; then
        mkdir -p "$(dirname "$SS_PROJECT")" "$_ss_recdir" 2>/dev/null
        if cp "$SS_SHIPPED" "$SS_PROJECT" 2>/dev/null && _ss_write_record; then
            fix "Copied $SS_LABEL"
            FIXES=$((FIXES + 1)); SS_RESULT=created
        else
            warn "$SS_LABEL: could not copy the shipped file or write $SS_DISP_RECORD — check permissions"
            SS_RESULT=error
        fi
    else
        SS_RESULT=skipped
    fi
    unset -f _ss_write_record _ss_backup _ss_backup_ver _ss_copy_writable _ss_writable _ss_merge_from
}

# ---------------------------------------------------------------------------
# GIT VISIBILITY (v7.3.1)
# A backup written next to a copy that git ignores is not itself ignored: after
# v7.3.0 refreshed an ignored AGENTS.md, `AGENTS.md.bak.pre-v7.3.0` sat in the
# repo root as an untracked file — in `git status`, and one `git add -A` from a
# commit (reported from PLAZMA, the same in all five projects checked). The
# backups under .claude/ and .apd/ were hidden only because those directories
# usually are.
#
# The pattern goes into `.git/info/exclude`, not `.gitignore`: exclude is local
# to the clone and outside history, so init changes no tracked file of the
# project for the sake of its own backups. Append-only, one line per pattern,
# only when git does not already ignore the path. Not a git repository, no git,
# an unwritable exclude file → nothing happens (the backup is merely visible).
# ---------------------------------------------------------------------------

# _ss_git_exclude <dir inside the repo> <literal path relative to that dir> <probe path> <glob suffix>
# Adds `/<repo-relative literal path><glob suffix>`, unless git already ignores <probe>.
_ss_git_exclude() {
    local dir="$1" pat="$2" probe="$3" prefix ex line
    command -v git >/dev/null 2>&1 || return 0
    [ -d "$dir" ] || return 0
    prefix=$(cd "$dir" 2>/dev/null && git rev-parse --show-prefix 2>/dev/null) || return 0
    ( cd "$dir" && git check-ignore -q "$probe" 2>/dev/null ) && return 0
    ex=$(cd "$dir" && git rev-parse --git-path info/exclude 2>/dev/null) || return 0
    [ -n "$ex" ] || return 0
    case "$ex" in /*) : ;; *) ex="$dir/$ex" ;; esac
    # the path is a LITERAL in a pattern file: `[`, `*`, `?` and `\` in a directory
    # or a file name are escaped, so the line matches that one copy's backups and
    # nothing else (audit-731 F3: `[` made the line match nothing, `*` a sibling's)
    line="/$(printf '%s' "$prefix$pat" | sed 's/[][\\*?]/\\&/g')$4"
    grep -qxF "$line" "$ex" 2>/dev/null && return 0
    mkdir -p "$(dirname "$ex")" 2>/dev/null || return 0
    # A file that cannot be written is left alone in silence (the redirection sits
    # inside the group, or the shell prints its own "Permission denied" at every
    # session start — audit-731 F1). A missing final newline in an existing file
    # must not glue the pattern to the last line.
    if [ -s "$ex" ] && [ -n "$(tail -c 1 "$ex" 2>/dev/null)" ]; then { printf '\n' >> "$ex"; } 2>/dev/null || return 0; fi
    { printf '%s\n' "$line" >> "$ex"; } 2>/dev/null || return 0
}

# _ss_exclude_backups <copy> — hide `<copy>.bak.*` from git status when a backup
# exists and git shows it. Covers a backup written by this run and one left by
# an earlier version.
_ss_exclude_backups() {
    local f="$1" b
    for b in "$f".bak.*; do
        [ -e "$b" ] || continue
        _ss_git_exclude "$(dirname "$f")" "$(basename "$f")" "$b" ".bak.*"
        return 0
    done
    return 0
}

# _ss_exclude_transients — the sync's own short-lived files under .apd/: the
# framework text left beside a conflict and a deferred record. (The merge locks
# need no line: they are empty directories, which git never lists.)
# The RECORDS are not excluded: whether a project commits `.apd/.shipped/*.md`
# is its choice (committed, a team shares one merge base).
_ss_exclude_transients() {
    local d="$PROJECT_DIR/.apd"
    [ -d "$d/.shipped" ] || return 0
    _ss_git_exclude "$d" ".shipped/" ".shipped/x.new.md"     "*.new.md"
    _ss_git_exclude "$d" ".shipped/" ".shipped/x.md.pending" "*.pending"
    return 0
}

# ---------------------------------------------------------------------------
# THE REGISTRY — every tracked copy, one row each. Read by init (to sync) and
# by audit-drift (to report), so the two agree on what is tracked.
#
# _ss_registry prints rows `key|kind|template (relative to the plugin)|project
# copy (relative to the project)`, only for copies that EXIST in this project.
#   kind: agent    → {{PROJECT_NAME}} substituted, model:/effort: are the project's
#         plain    → a byte copy
#         cdxname  → {{PROJECT_NAME}} substituted with the directory's name
#         cdxwf    → workflow.md with shortcut paths rewritten to .codex/
# workflow.md on CC keeps its own record path and messages (v7.1.6) and is
# synced by init directly; the builder charter is a BLOCK inside project-owned
# agents and has its own extraction (see `_ss_charter_*`).
# ---------------------------------------------------------------------------
_ss_registry() {
    local c="$PROJECT_DIR/.claude" a="$PROJECT_DIR/.apd" r
    [ -f "$c/agents/code-reviewer.md" ]        && printf '%s\n' "cc-code-reviewer|agent|templates/reviewer-template.md|.claude/agents/code-reviewer.md"
    [ -f "$c/agents/adversarial-reviewer.md" ] && printf '%s\n' "cc-adversarial-reviewer|agent|templates/adversarial-reviewer-template.md|.claude/agents/adversarial-reviewer.md"
    [ -f "$c/agents/supervisor.md" ]           && printf '%s\n' "cc-supervisor|agent|templates/supervisor-template.md|.claude/agents/supervisor.md"
    # principles.md is NOT here on purpose: init seeds it and /apd-setup rewrites
    # it for the project (language, git rules). A trial on copies of eight real
    # projects found it edited line by line in seven — tracked, it would report a
    # conflict on every init. It is the project's file, like verify-all.sh.
    [ -f "$PROJECT_DIR/AGENTS.md" ] && [ -d "$PROJECT_DIR/.codex" ] && printf '%s\n' "cdx-agents-md|cdxname|templates/codex/AGENTS.md|AGENTS.md"
    for r in brainstorm tdd debug finish; do
        [ -f "$a/rules/$r.md" ] && printf '%s\n' "cdx-rule-$r|plain|templates/codex/rules/$r.md|.apd/rules/$r.md"
    done
    [ -f "$a/rules/workflow.md" ] && [ ! -d "$c" ] && printf '%s\n' "cdx-workflow|cdxwf|rules/workflow.md|.apd/rules/workflow.md"
    for r in code-reviewer adversarial-reviewer; do
        [ -f "$a/agents/$r.md" ] && printf '%s\n' "cdx-agent-$r|agent|templates/codex/agents/$r.md|.apd/agents/$r.md"
    done
    return 0
}

# _ss_project_name <kind> — the name a render substitutes for {{PROJECT_NAME}}
_ss_project_name() {
    case "$1" in
        cdxname) basename "$PROJECT_DIR" ;;
        agent|agentraw)
            local n=""
            [ -n "${APD_CONFIG_FILE:-}" ] && n=$(grep '^PROJECT_NAME=' "$APD_CONFIG_FILE" 2>/dev/null | head -1 | cut -d= -f2-)
            [ -n "$n" ] || n="${PROJECT_NAME:-}"
            printf '%s' "$n" ;;
        *) : ;;
    esac
}

# _ss_render <kind> <template-file> <project-copy> <out-file> — the framework's
# text for THIS project. Returns 1 when it cannot be rendered.
_ss_render() {
    local kind="$1" tmpl="$2" proj="$3" out="$4" name
    [ -f "$tmpl" ] || return 1
    case "$kind" in
        plain) cp "$tmpl" "$out" 2>/dev/null || return 1 ;;
        cdxwf) sed 's|\.claude/bin/apd|.codex/bin/apd|g' "$tmpl" > "$out" 2>/dev/null || return 1 ;;
        agent|agentraw|cdxname)
            name=$(_ss_project_name "$kind")
            # a literal substitution: a name with `&`, `/` or `\` must not be read by sed
            APD_SS_NAME="$name" LC_ALL=C awk '
                BEGIN { name = ENVIRON["APD_SS_NAME"]; ph = "{{PROJECT_NAME}}" }
                {
                    out = ""; s = $0
                    while ((i = index(s, ph)) > 0) { out = out substr(s, 1, i - 1) name; s = substr(s, i + length(ph)) }
                    print out s
                }
            ' "$tmpl" > "$out" 2>/dev/null || return 1
            # `agent`: model:/effort: are the project's. `agentraw` (init writing an
            # agent from the template — a creation or a marker refresh) keeps the
            # TEMPLATE's pins, as it always did; init's own pin logic follows it.
            [ "$kind" = agent ] && _ss_carry_pins "$out" "$proj"
            ;;
        *) return 1 ;;
    esac
    [ "$kind" = agentraw ] || _ss_like "$out" "$proj"
    return 0
}

# _ss_like <rendered-file> <project-copy> — give the rendered text the project
# copy's line endings and BOM (audit-730 F5: a CRLF agent compared as "every line
# differs", so each framework change was a permanent conflict, and with no record
# it was "refreshed" to LF as if it were an older text).
_ss_like() {
    local f="$1" proj="$2" tmp
    [ -f "$proj" ] && [ -f "$f" ] || return 0
    tmp="$f.like"
    if LC_ALL=C grep -q "$(printf '\r')\$" "$proj" 2>/dev/null; then
        LC_ALL=C awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f"
    fi
    if [ "$(LC_ALL=C head -c 3 "$proj" 2>/dev/null)" = "$(printf '\357\273\277')" ] && [ "$(LC_ALL=C head -c 3 "$f" 2>/dev/null)" != "$(printf '\357\273\277')" ]; then
        { printf '\357\273\277'; cat "$f"; } > "$tmp" 2>/dev/null && mv "$tmp" "$f"
    fi
    return 0
}

_ss_record_path() { printf '%s' "$PROJECT_DIR/.apd/.shipped/$1.md"; }

# _ss_ancestor <key> <kind> <project-copy> <out-file> [<current render>] — the
# shipped text NEAREST to the copy (fewest differing lines), rendered for this
# project; the current render is a candidate too. The earlier texts are the
# canonical ones in templates/shipped-history.d/<key>/. Returns 0 with the text
# in <out-file>, 1 when the key has no stored texts, 2 when the nearest text is
# unrelated to the copy (the project's own file).
_ss_ancestor() {
    local key="$1" kind="$2" copy="$3" out="$4" shipped="${5:-}" dir f n best=-1 cl bl list
    dir="$APD_PLUGIN_ROOT/templates/shipped-history.d/$key"
    [ -d "$dir" ] || return 1
    # oldest → newest when the generator wrote the order; a tie goes to the OLDER
    # text, and the current text is chosen only when it is STRICTLY nearest. A
    # The distance is a MINIMAL diff (`-d`): plain diff is a heuristic on both BSD
    # and GNU, and a non-minimal script made a NEWER text look nearer than the
    # text the copy was made from (audit-730 pass 3, N3: 14 vs 13 plain, 12 vs 13
    # minimal — the newer base hid one framework line as a "local deletion").
    # too-old base costs a merge that re-applies changes the copy already has, or
    # an honest CONFLICT; a too-new base makes a pending framework change read as
    # a local edit and never delivers it (audit-730 pass 2, N1 — the first cut
    # sent ties to the newer text and did exactly that).
    if [ -f "$dir/ORDER" ]; then list=$(sed "s|^|$dir/|; s|\$|.md|" "$dir/ORDER" 2>/dev/null); else list=$(ls "$dir"/*.md 2>/dev/null); fi
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        _ss_render "$kind" "$f" "$copy" "$out.try" || continue
        n=$(diff -d "$out.try" "$copy" 2>/dev/null | grep -c '^[<>]') || true
        case "$n" in ''|*[!0-9]*) continue ;; esac
        if [ "$best" -lt 0 ] || [ "$n" -lt "$best" ]; then cp "$out.try" "$out" 2>/dev/null && best="$n"; fi
    done <<SS_EOF
$list
SS_EOF
    if [ -n "$shipped" ] && [ -f "$shipped" ]; then
        n=$(diff -d "$shipped" "$copy" 2>/dev/null | grep -c '^[<>]') || true
        case "$n" in ''|*[!0-9]*) n=-1 ;; esac
        if [ "$n" -ge 0 ] && { [ "$best" -lt 0 ] || [ "$n" -lt "$best" ]; }; then cp "$shipped" "$out" 2>/dev/null && best="$n"; fi
    fi
    rm -f "$out.try" "$out.try.pins" "$out.try.like"
    [ "$best" -ge 0 ] || return 1
    # (audit-730 F2) a copy that shares less than half its lines with the nearest
    # shipped text was not made from one: `diff` counts every differing line on
    # both sides, so more than half of (copy + text) differing means "unrelated".
    cl=$(wc -l < "$copy" 2>/dev/null | tr -d ' '); bl=$(wc -l < "$out" 2>/dev/null | tr -d ' ')
    if [ $((best * 2)) -gt $(( ${cl:-0} + ${bl:-0} )) ]; then return 2; fi
    return 0
}

# ---------------------------------------------------------------------------
# THE BUILDER CHARTER — a block inside project-owned builder agents.
# The block starts at the marker line and runs to the line before the next
# top-level `## ` heading that is not the charter's own (code fences skipped),
# or to the end of the file.
# ---------------------------------------------------------------------------
SS_CHARTER_MARK='<!-- apd:builder-charter -->'

# _ss_charter_shipped <out-file> — the block as the template carries it now
_ss_charter_shipped() {
    LC_ALL=C awk -v mark="$SS_CHARTER_MARK" '
        index($0, mark) { f = 1 }
        f && /^## Stack/ { exit }
        f { print }
    ' "$APD_PLUGIN_ROOT/templates/agent-template.md" 2>/dev/null | _ss_trim_tail > "$1"
    [ -s "$1" ]
}

# _ss_trim_tail — drop trailing blank lines (the block is compared without them)
_ss_trim_tail() {
    LC_ALL=C awk '{ sub(/\r$/, ""); l[NR] = $0 } END { n = NR; while (n > 0 && l[n] ~ /^[ \t]*$/) n--; for (i = 1; i <= n; i++) print l[i] }'
}

# _ss_charter_bounds <agent-file> → prints "<first-line> <last-line>" of the
# block, or nothing when the agent carries no charter — or more than one, or
# only a marker quoted inside a code fence (audit-730 F8): neither is synced.
_ss_charter_bounds() {
    LC_ALL=C awk -v mark="$SS_CHARTER_MARK" '
        { sub(/\r$/, ""); t = $0; sub(/^[ \t]+/, "", t) }
        fence == "" && (substr(t, 1, 3) == "```" || substr(t, 1, 3) == "~~~") { fence = substr(t, 1, 3); next }
        fence != "" { if (substr(t, 1, 3) == fence) fence = ""; next }
        index($0, mark) { n++; if (!s) { s = NR; next } }
        s && !e && $0 ~ /^## / && $0 !~ /^## Charter/ { e = NR - 1 }
        END { if (s && n == 1) { if (!e) e = NR; print s, e } }
    ' "$1" 2>/dev/null
}

# _ss_charter_extract <agent-file> <out-file> — the agent's block, trimmed
_ss_charter_extract() {
    local b s e
    b=$(_ss_charter_bounds "$1"); [ -n "$b" ] || return 1
    s="${b%% *}"; e="${b##* }"
    sed -n "${s},${e}p" "$1" 2>/dev/null | _ss_trim_tail > "$2"
    [ -s "$2" ]
}

# _ss_charter_splice <agent-file> <new-block-file> — replace the agent's block
# with the new text, keeping the agent's line endings and everything around it.
_ss_charter_splice() {
    local agent="$1" blk="$2" b s e tmp crlf=false
    b=$(_ss_charter_bounds "$agent"); [ -n "$b" ] || return 1
    s="${b%% *}"; e="${b##* }"
    LC_ALL=C grep -q $'\r$' "$agent" 2>/dev/null && crlf=true
    tmp="$agent.charter.$$"
    {
        [ "$s" -gt 1 ] && sed -n "1,$((s - 1))p" "$agent"
        if [ "$crlf" = true ]; then LC_ALL=C awk '{ printf "%s\r\n", $0 }' "$blk"; printf '\r\n'
        else cat "$blk"; printf '\n'; fi
        sed -n "$((e + 1)),\$p" "$agent"
    } > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
    # The new file replaces the agent in ONE step (rename): a process killed
    # during `cat tmp > agent` left a 0-byte builder (audit-730 pass 5). The
    # temp file first takes the agent's mode. A symlinked agent is written
    # through instead — a rename would replace the link with a regular file.
    if [ -L "$agent" ]; then
        cat "$tmp" > "$agent" 2>/dev/null || { rm -f "$tmp"; return 1; }
        rm -f "$tmp"
    else
        cp -p "$agent" "$tmp.m" 2>/dev/null && cat "$tmp" > "$tmp.m" 2>/dev/null && mv -f "$tmp.m" "$agent" 2>/dev/null \
            || { rm -f "$tmp" "$tmp.m"; return 1; }
        rm -f "$tmp"
    fi
}
