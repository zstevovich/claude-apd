// Package gitguard judges the git statements in a Bash command: a pipeline
// agent may not commit, push or destroy work, and the orchestrator commits only
// through the signed form that runs the pipeline gate.
//
// It judges STATEMENTS, not text: `grep -rn "git commit" src/` and a commit
// message that mentions --force are data; `sh -c "git commit"`, `sudo git push`
// and `git -C dir commit` are the statements they are. Ported from
// plugins/apd/bin/core/guard-git.
package gitguard

import (
	"regexp"
	"strings"

	"github.com/zstevovich/claude-apd/guard/internal/shell"
	"github.com/zstevovich/claude-apd/guard/internal/tools"
)

// Marker is the assignment that signs a statement as the orchestrator's own.
const Marker = "APD_ORCHESTRATOR_COMMIT"

// The reasons a command is refused — the audit log's names.
const (
	NoVerify        = "--no-verify"
	MassStaging     = "mass-staging"
	CommitAll       = "commit-all"
	AISignature     = "ai-signature"
	CommitNoPrefix  = "commit-no-prefix"
	ForcePush       = "force-push"
	PushNoPrefix    = "push-no-prefix"
	Destructive     = "destructive-git"
	StashFromAgent  = "stash-from-agent"
	ForceDelete     = "force-delete-branch"
	ClaudeDirPrefix = "claude-dir-no-prefix"
	ConfigOverride  = "git-config-override"
	Unreadable      = "git-unreadable"
)

var messages = map[string]string{
	NoVerify:        "--no-verify is not allowed. Hooks must pass.",
	MassStaging:     "git add . / git add -A / git add --all is not allowed.\nUse: git add <file1> <file2> ...",
	CommitAll:       "git commit -a / --all is not allowed. Stage files explicitly.",
	AISignature:     "AI signature (Co-Authored-By) is not allowed.",
	CommitNoPrefix:  "git commit is only allowed with " + Marker + "=1 prefix.",
	ForcePush:       "git push --force is not allowed.",
	PushNoPrefix:    "git push is only allowed with " + Marker + "=1 prefix.",
	Destructive:     "Destructive git operation is not allowed.",
	StashFromAgent:  "git stash is not allowed from a pipeline agent.\n  It moves uncommitted work — yours and every other agent's — out of the working tree; the orchestrator owns the tree. Leave your changes in place and report; git stash list / git stash show are allowed.",
	ForceDelete:     "git branch -D (force delete) is not allowed. Use -d for safe delete.",
	ClaudeDirPrefix: "git add .claude/ is only allowed with " + Marker + "=1 prefix.",
	Unreadable:      "a git statement whose subcommand is not written out (a variable, a substitution, xargs) is not allowed: what it runs cannot be read.",
	ConfigOverride:  "git with an alias or configuration supplied by the command itself is not allowed: what it runs cannot be read.",
}

// Options is one call of the guard.
type Options struct {
	Command   string
	AgentType string // "" = the orchestrator
}

// Verdict is the guard's answer. The zero value allows.
type Verdict struct {
	Code    string // "" = allowed
	Message string
	// Commit: the command holds a signed commit that passed every check here.
	// The caller still has to run the pipeline gate and the project's verification.
	Commit bool
}

func (v Verdict) Blocked() bool { return v.Code != "" }

func refuse(code string) *Verdict { return &Verdict{Code: code, Message: messages[code]} }

type judge struct {
	o         Options
	rd        *shell.Reader
	prefixed  bool // the whole command starts with the marker
	verdict   *Verdict
	commit    bool
	addClaude bool
	depth     int
	gitEnv    bool // git configuration reaches git through the environment this command set
	// opaque: a command whose name is not written out (`$G push`), an expansion
	// among a git statement's arguments, or shell state the reader lost. The text
	// scan then judges the whole command as well.
	opaque bool
	// a commit or push statement read here carried the marker as its own prefix
	signedSeen bool
	// vars: the values the command itself gave its variables (`X=git; $X push`)
	vars map[string][]string
}

func (j *judge) setvar(name, value string) {
	if name == "" {
		return
	}
	if j.vars == nil {
		j.vars = map[string][]string{}
	}
	// a value built from other variables is stored with them filled in
	for _, v := range j.fill(value) {
		if unresolved(v) || in(v, j.vars[name]...) {
			continue
		}
		if len(j.vars[name]) >= 512 {
			j.block(Unreadable) // more values than are followed: one of them may name git
			return
		}
		j.vars[name] = append(j.vars[name], v)
	}
}

var varRef = regexp.MustCompile(`\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)`)

// fill returns s with the variables the command assigned filled in: every
// combination of their values. A reference is replaced as a whole name —
// `$Xa` is the variable Xa, never `$X` followed by `a`.
func (j *judge) fill(s string) []string {
	out := []string{""}
	last := 0
	for _, loc := range varRef.FindAllStringSubmatchIndex(s, -1) {
		var name string
		if loc[2] >= 0 {
			name = s[loc[2]:loc[3]] // ${NAME}
		} else {
			name = s[loc[4]:loc[5]] // $NAME
		}
		vals := j.vars[name]
		if len(vals) == 0 {
			vals = []string{s[loc[0]:loc[1]]} // not assigned here: stays as written
		}
		lit := s[last:loc[0]]
		var next []string
		for _, o := range out {
			for _, v := range vals {
				if len(next) >= 256 {
					j.block(Unreadable)
					return nil
				}
				next = append(next, o+lit+v)
			}
		}
		out, last = next, loc[1]
	}
	for i := range out {
		out[i] += s[last:]
	}
	return out
}

func shq(w string) string { return "'" + strings.ReplaceAll(w, "'", `'\''`) + "'" }

// filled returns the statement's text with the variables the command assigned
// filled in, to be read again as a statement. Every word is quoted, so a `#`,
// a `;` or a backslash in it stays that character. A value that holds several
// words is given both ways the shell may use it: split into words (`$X`), and
// whole (`"$X"`, the string after `sh -c`).
func (j *judge) filled(words []string) []string {
	var names []string
	for _, w := range words {
		for _, m := range varRef.FindAllStringSubmatch(w, -1) {
			if n := m[1] + m[2]; len(j.vars[n]) > 0 && !in(n, names...) {
				names = append(names, n)
			}
		}
	}
	if len(names) == 0 {
		return nil
	}
	// One value per variable for the whole statement, every combination. A loop
	// over forty files gives forty readings, not forty to the power of the words
	// that name the variable. When there are still too many, values that are
	// paths or file names (they hold a `/` or a `.`) are left as written: they
	// cannot be the word `git` or a subcommand.
	envs := j.combos(names, false)
	if envs == nil {
		if envs = j.combos(names, true); envs == nil {
			j.block(Unreadable)
			return nil
		}
	}
	var out []string
	for _, env := range envs {
		if len(env) == 0 {
			continue // nothing filled in: the statement as written has been judged already
		}
		var split, whole []string
		for _, w := range words {
			a := varRef.ReplaceAllStringFunc(w, func(ref string) string {
				if v, ok := env[strings.Trim(ref, "${}")]; ok {
					return v
				}
				return ref
			})
			whole = append(whole, shq(a))
			if a == w {
				split = append(split, shq(a))
				continue
			}
			for _, piece := range strings.Fields(a) {
				split = append(split, shq(piece))
			}
		}
		s, wh := strings.Join(split, " "), strings.Join(whole, " ")
		out = append(out, s)
		if wh != s {
			out = append(out, wh)
		}
	}
	return out
}

// combos returns every assignment of one value to each name, or nil when there
// are more than are followed. plain leaves out values that hold a `/` or a `.`
// and are neither git by a path nor an option.
func (j *judge) combos(names []string, plain bool) []map[string]string {
	envs := []map[string]string{{}}
	for _, n := range names {
		var vals []string
		for _, v := range j.vars[n] {
			// a path or a file name cannot be a subcommand — but it can be git itself
			// (`/usr/bin/git`), and a word that starts with a dash is an option
			if !plain || !strings.ContainsAny(v, "/.") || strings.HasPrefix(v, "-") || isGit(v) {
				vals = append(vals, v)
			}
		}
		if len(vals) == 0 {
			continue // left as written
		}
		var next []map[string]string
		for _, e := range envs {
			for _, v := range vals {
				if len(next) >= 256 {
					return nil
				}
				c := map[string]string{n: v}
				for k, x := range e {
					c[k] = x
				}
				next = append(next, c)
			}
		}
		envs = next
	}
	return envs
}

var spaces = regexp.MustCompile(` +`)

// Judge reads the command and judges every git statement in it, in order.
func Judge(o Options) Verdict {
	if o.Command == "" {
		return Verdict{}
	}
	norm := strings.TrimPrefix(spaces.ReplaceAllString(o.Command, " "), " ")
	j := &judge{o: o, rd: shell.NewReader(), prefixed: strings.HasPrefix(norm, Marker+"=1 ")}
	if err := j.rd.Walk(o.Command, j); err != nil {
		// unreadable: the text scan over-blocks on anything that mentions git, never under-blocks
		return rawScan(o, norm, j.prefixed)
	}
	switch {
	case j.verdict != nil:
		return *j.verdict
	case j.addClaude:
		return *refuse(ClaudeDirPrefix)
	}
	if j.opaque {
		// the text scan cannot see a marker in the middle of a command; a statement
		// read here that carried one signs the command for it (an unsigned commit or
		// push statement has already been refused by then)
		if v := rawScan(o, norm, j.prefixed || j.signedSeen); v.Blocked() {
			return v
		}
	}
	return Verdict{Commit: j.commit}
}

func (j *judge) Enter(shell.Scope) {}
func (j *judge) Leave(shell.Scope) {}
func (j *judge) For(name string, items []string) {
	j.gitEnv = j.gitEnv || configEnv(name)
	for _, it := range items {
		j.setvar(name, it)
	}
}
func (j *judge) Call([]shell.Assign)      {}
func (j *judge) Return()                  {}
func (j *judge) Lost(string)              { j.opaque = true }
func (j *judge) QuotedSubst(text string)  { j.nested(text) }
func (j *judge) block(code string)        { j.verdict = refuse(code) }
func isGit(w string) bool                 { return w == "git" || strings.HasSuffix(w, "/git") }
func has(args []string, want string) bool { return indexOf(args, want) >= 0 }
func lower(s string) string               { return strings.ToLower(s) }
func (j *judge) signed(marked bool) bool  { return j.prefixed || marked }
func isMarker(name, value string) bool    { return name == Marker && value == "1" }
func hooksPath(s, prefix string) bool     { return strings.HasPrefix(lower(s), prefix) }
func at(a []string, i int) string {
	if i >= 0 && i < len(a) {
		return a[i]
	}
	return ""
}
func indexOf(a []string, want string) int {
	for i, x := range a {
		if x == want {
			return i
		}
	}
	return -1
}

// nested reads text another shell will run, with the same rules.
func (j *judge) nested(text string) {
	if j.verdict != nil {
		return
	}
	if j.depth >= 8 {
		j.block(Unreadable) // shells nested deeper than the guard reads
		return
	}
	j.depth++
	if err := j.rd.Walk(text, j); err != nil && j.verdict == nil {
		if v := rawScan(j.o, text, j.prefixed); v.Blocked() {
			j.verdict = &v
		} else if v.Commit {
			j.commit = true
		}
	}
	j.depth--
}

// configEnv: variables through which a command hands git configuration of its own.
func configEnv(name string) bool {
	return strings.HasPrefix(name, "GIT_CONFIG") || in(name, "GIT_EXEC_PATH", "GIT_DIR", "GIT_COMMON_DIR", "HOME", "XDG_CONFIG_HOME")
}

// setters: builtins that give a variable a value or export it, by name.
var setters = map[string]bool{"export": true, "declare": true, "typeset": true, "local": true, "readonly": true,
	"read": true, "printf": true, "mapfile": true, "readarray": true, "getopts": true}

func (j *judge) Command(c shell.Command) {
	if j.verdict != nil {
		return
	}
	// the statement's own `APD_ORCHESTRATOR_COMMIT=1 git …` prefix signs it
	marked := false
	for _, a := range c.Assigns {
		marked = marked || isMarker(a.Name, a.Value)
		j.gitEnv = j.gitEnv || (configEnv(a.Name) && (len(c.Words) == 0 || c.Decl != ""))
		if configEnv(a.Name) && len(c.Words) > 0 {
			defer func(was bool) { j.gitEnv = was }(j.gitEnv)
			j.gitEnv = true
		}
	}
	for _, a := range c.Assigns {
		if !a.Opaque {
			j.setvar(a.Name, a.Value)
		}
	}
	if len(c.Words) == 0 {
		return
	}
	// `X=git; $X push --force`, `X="git push --force"; $X`: the statement is read
	// again with the values filled in
	for _, text := range j.filled(c.Words) {
		if marked {
			text = Marker + "=1 " + text // the statement's own signature goes with it
		}
		j.nested(text)
	}
	u := tools.Unwrap(c.Words)
	if tools.FedShell(c.Words, c.Heredoc != "" && len(c.Feeds) == 0) {
		// a shell reading its commands from a pipe or a file descriptor: what it
		// runs is another command's output — the text scan reads the whole command
		j.opaque = true
	}
	for _, e := range u.Env {
		k := strings.Index(e, "=")
		marked = marked || isMarker(e[:k], e[k+1:])
		if configEnv(e[:k]) {
			defer func(was bool) { j.gitEnv = was }(j.gitEnv)
			j.gitEnv = true
		}
	}
	if text, ok := tools.ShellText(u.Cmd, u.Args, c.Heredoc); ok {
		j.nested(text)
	}
	if setters[u.Cmd] || c.Decl != "" {
		// `export GIT_CONFIG_PARAMETERS`, `read HOME`: the variable is named, its value comes from elsewhere
		named := c.Words
		if u.Cmd == "printf" {
			// printf names a variable only after -v; the rest is what it prints
			named = nil
			if k := indexOf(u.Args, "-v"); k >= 0 {
				named = []string{at(u.Args, k+1)}
			}
		}
		for _, w := range named {
			j.gitEnv = j.gitEnv || configEnv(w) || unresolved(w) // a name that is not written out may be one of them
		}
	}
	if c.Decl != "" || in(u.Cmd, "declare", "typeset", "local") {
		// a nameref (-n) makes one name stand for another, chosen now or by a later
		// plain assignment: which variable a write lands in is no longer readable,
		// and it may be one git takes its configuration from
		for _, w := range append(append([]string{}, c.Words...), u.Args...) {
			if len(w) > 1 && w[0] == '-' && w[1] != '-' && strings.Contains(w, "n") {
				j.gitEnv = true
			}
		}
	}
	// the arguments find, xargs and parallel hand a command are not written here
	fed := u.Xargs || in(u.Cmd, "find", "parallel")
	// git by any spelling and behind any wrapper: every word that is `git` or
	// ends in `/git` starts a statement (xcrun git, /usr/bin/git, find -exec git …)
	words := append([]string{u.Cmd}, u.Args...)
	if unresolved(u.Cmd) {
		j.opaque = true // `$G push`: what runs is not written here
	}
	for k, w := range words {
		if isGit(w) && j.verdict == nil {
			j.statement(words[k+1:], marked, fed)
		}
	}
}

// clusterHas reports whether a single-dash option cluster carries one of
// letters before any letter that takes a stuck value (`-mfinal`: the rest of
// the word is the message).
func clusterHas(w, letters, valued string) bool {
	if len(w) < 2 || w[0] != '-' || w[1] == '-' {
		return false
	}
	for _, c := range w[1:] {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z') {
			return false
		}
		if strings.ContainsRune(letters, c) {
			return true
		}
		if strings.ContainsRune(valued, c) {
			return false
		}
	}
	return false
}

// long reports a long option by its full spelling or by an abbreviation: git
// accepts any unambiguous prefix (`--no-verif`, `--forc`), with or without `=value`.
func long(arg, full string) bool {
	arg, _, _ = strings.Cut(arg, "=")
	return len(arg) > 3 && strings.HasPrefix(arg, "--") && strings.HasPrefix(full, arg)
}

func anyLong(args []string, full ...string) bool {
	for _, a := range args {
		for _, f := range full {
			if long(a, f) {
				return true
			}
		}
	}
	return false
}

// flags whose next word is a value — never a flag, never a path
var valueFlags = map[string][]string{
	"commit": {"-m", "-F", "-C", "-c", "-t", "--message", "--file", "--author", "--date", "--template", "--fixup",
		"--squash", "--reuse-message", "--reedit-message", "--trailer", "--cleanup", "--pathspec-from-file"},
	"push":  {"-o", "--push-option", "--receive-pack", "--exec", "--repo"},
	"add":   {"--chmod", "--pathspec-from-file"},
	"clean": {"-e", "--exclude"},
}

func unresolved(w string) bool { return strings.ContainsAny(w, "$`") }

// fedReadOnly: subcommands that only read whatever arguments xargs, find or
// parallel append — `git ls-files | xargs git diff --stat`. `grep` is not among
// them: an appended `-O<cmd>` makes it run a program.
var fedReadOnly = map[string]bool{"diff": true, "log": true, "show": true, "status": true, "blame": true, "annotate": true,
	"ls-files": true, "ls-tree": true, "cat-file": true, "rev-parse": true, "rev-list": true, "hash-object": true,
	"check-ignore": true, "check-attr": true, "describe": true, "shortlog": true, "name-rev": true, "merge-base": true,
	"diff-tree": true, "diff-index": true, "diff-files": true, "for-each-ref": true, "show-ref": true, "whatchanged": true,
	"count-objects": true}

func (j *judge) statement(words []string, marked, xargs bool) {
	// git's own options come before the subcommand
	sub, hooksOff, i := "", false, 0
	if j.gitEnv {
		j.block(ConfigOverride)
		return
	}
	for i < len(words) && sub == "" {
		w := words[i]
		switch {
		case w == "-c" || w == "--config-env":
			hooksOff = hooksOff || hooksPath(at(words, i+1), "core.hookspath=")
			if strings.HasPrefix(lower(at(words, i+1)), "alias.") {
				j.block(ConfigOverride) // an alias defined on the command line: what `git x` runs is its value
				return
			}
			i += 2
		case in(w, "-C", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix"):
			i += 2
		case strings.HasPrefix(w, "--config-env="):
			hooksOff = hooksOff || hooksPath(w, "--config-env=core.hookspath=")
			i++
		case strings.HasPrefix(w, "-c"):
			hooksOff = hooksOff || hooksPath(w, "-ccore.hookspath=")
			if strings.HasPrefix(lower(w), "-calias.") {
				j.block(ConfigOverride)
				return
			}
			i++
		case strings.HasPrefix(w, "-"):
			i++
		default:
			sub = w
			i++
		}
	}
	switch {
	case unresolved(sub), strings.Contains(sub, "{}"), xargs && !fedReadOnly[sub]:
		// the subcommand, or arguments another program appends (an option may be among them), are not written here
		j.block(Unreadable)
		return
	case sub == "":
		return
	}
	var args []string
	for k := i; k < len(words); k++ {
		if in(words[k], valueFlags[sub]...) {
			k++
			continue
		}
		args = append(args, words[k])
		// an argument that is an expansion: what it becomes is not written here, but
		// the text it is made from is — the text scan reads that too
		j.opaque = j.opaque || unresolved(words[k])
	}
	signed := j.signed(marked)
	if signed && in(sub, "commit", "push") {
		j.signedSeen = true // an unsigned one is refused below, on its own
	}

	// --no-verify on any statement, and its equivalents: commit -n, -c core.hooksPath=…
	nv := anyLong(args, "--no-verify") || hooksOff
	if sub == "commit" {
		for _, a := range args {
			nv = nv || clusterHas(a, "n", "mFCctSu")
		}
	}
	if nv {
		j.block(NoVerify)
		return
	}
	switch sub {
	case "add":
		for _, a := range args {
			if in(a, ".", "./", ":/", "-A", "-u", "-U") || long(a, "--all") || long(a, "--update") ||
				strings.HasPrefix(a, "*") || clusterHas(a, "AuU", "") {
				j.block(MassStaging) // `*`-leading is the whole tree; src/*.cs is targeted
				return
			}
			if strings.Contains(a, ".claude") && !signed {
				j.addClaude = true
			}
		}
	case "commit":
		if !signed {
			j.block(CommitNoPrefix)
			return
		}
		j.commit = true
		for _, a := range args {
			if long(a, "--all") || clusterHas(a, "a", "mFCctSu") {
				j.block(CommitAll)
				return
			}
		}
		if strings.Contains(lower(j.o.Command), "co-authored-by") {
			j.block(AISignature)
		}
	case "push":
		for _, a := range args {
			if long(a, "--force") || long(a, "--force-with-lease") || long(a, "--force-if-includes") || long(a, "--mirror") ||
				long(a, "--delete") || long(a, "--prune") ||
				(strings.HasPrefix(a, "+") && len(a) > 1) || clusterHas(a, "fd", "o") {
				j.block(ForcePush) // `+refspec` is a force push by refspec
				return
			}
		}
		if !signed {
			j.block(PushNoPrefix)
		}
	case "reset":
		if anyLong(args, "--hard", "--merge", "--keep") {
			j.block(Destructive)
		}
	case "clean":
		dry, force := false, false
		for _, a := range args {
			dry = dry || a == "--dry-run" || clusterHas(a, "n", "e") // by its full spelling only: an abbreviation is not taken on trust
			force = force || long(a, "--force") || clusterHas(a, "fdxX", "e")
		}
		if force && !dry {
			j.block(Destructive)
		}
	case "checkout":
		forced := anyLong(args, "--force", "--discard-changes")
		for _, a := range args {
			forced = forced || clusterHas(a, "f", "bBt")
		}
		if has(args, "--") || has(args, ".") || forced {
			j.block(Destructive)
		}
	case "switch":
		forced := anyLong(args, "--force", "--discard-changes")
		for _, a := range args {
			forced = forced || clusterHas(a, "fC", "ct")
		}
		if forced {
			j.block(Destructive)
		}
	case "commit-tree", "update-ref", "fast-import", "replace":
		// the plumbing under a commit: the same act, the same signature
		if !signed {
			j.block(CommitNoPrefix)
		}
	case "send-pack":
		if !signed {
			j.block(PushNoPrefix)
		}
	case "merge", "cherry-pick", "revert", "am", "rebase", "pull":
		// these write commits; a pipeline agent commits nothing
		if j.o.AgentType != "" {
			j.block(CommitNoPrefix)
		}
	case "grep":
		for _, a := range args {
			if long(a, "--open-files-in-pager") || clusterHas(a, "O", "ABCefm") {
				j.block(Unreadable) // runs a program of the command's choosing on the matches
				return
			}
		}
	case "config":
		// a setting that turns hooks off or renames a command, written by the command being judged
		// git reads its action from the options before the first operand
		lead := args
		for k, a := range args {
			if !strings.HasPrefix(a, "-") {
				lead = args[:k]
				break
			}
		}
		operands := len(tools.Positionals(args, `^(--file|-f|--blob|--type|--default)$`))
		read := (anyLong(lead, "--get", "--list", "--get-all", "--get-regexp", "--get-urlmatch") || has(lead, "-l")) && operands <= 1
		write := anyLong(args, "--unset", "--unset-all", "--add", "--replace-all") || operands != 1 // `git config key` alone prints it
		if j.o.AgentType != "" && !read && write {
			j.block(ConfigOverride) // a pipeline agent reads configuration, it does not write it
			return
		}
		if anyLong(args, "--rename-section", "--remove-section", "--edit") || has(args, "-e") {
			j.block(ConfigOverride)
			return
		}
		for _, a := range args {
			if l := lower(a); strings.HasPrefix(l, "include.") || strings.HasPrefix(l, "includeif.") {
				j.block(ConfigOverride) // pulls in a file of settings
				return
			}
		}
		for _, a := range args {
			l := lower(a)
			if strings.HasPrefix(l, "core.hookspath") {
				j.block(NoVerify)
				return
			}
			if strings.HasPrefix(l, "alias.") && !read {
				j.block(ConfigOverride)
				return
			}
		}
	case "restore":
		// `git restore --staged <path>` only unstages. Destructive when it touches
		// the working tree: no --staged at all, or --staged with -W/--worktree.
		staged, tree := false, false
		for _, a := range args {
			if a == "--" {
				break
			}
			staged = staged || a == "--staged" || (!strings.HasPrefix(a, "--") && clusterHas(a, "S", "s"))
			tree = tree || long(a, "--worktree") || (!strings.HasPrefix(a, "--") && clusterHas(a, "W", "s"))
		}
		if !staged || tree {
			j.block(Destructive)
		}
	case "stash":
		// drop/clear destroy for everyone; list/show are reads for everyone; anything
		// else moves the tree's uncommitted state, which the orchestrator owns
		switch at(args, 0) {
		case "drop", "clear":
			j.block(Destructive)
		case "list", "show", "--help", "-h":
		default:
			if j.o.AgentType != "" {
				j.block(StashFromAgent)
			}
		}
	case "tag":
		if has(args, "-d") || anyLong(args, "--delete") {
			j.block(Destructive)
		}
	case "branch":
		del, force := false, false
		for _, a := range args {
			del = del || long(a, "--delete") || clusterHas(a, "d", "")
			force = force || long(a, "--force") || clusterHas(a, "f", "")
		}
		if has(args, "-D") || (del && force) {
			j.block(ForceDelete)
		}
	}
}

func in(s string, l ...string) bool { return indexOf(l, s) >= 0 }

// ---------- the text scan, for a command the parser could not read ----------

var (
	leadAssign  = regexp.MustCompile(`^([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*`)
	gitOpts     = regexp.MustCompile(`git[[:space:]]+(-[A-Za-z][[:space:]]+[^ ]+[[:space:]]+)*`)
	rawNoVerify = regexp.MustCompile(`(^| )--no-verify( |$)`)
	rawAdd      = regexp.MustCompile(`git add[[:space:]]+(\.([[:space:]]|$)|-[AuU]([[:space:]=]|$)|--all([[:space:]=]|$)|\*)`)
	rawCommit   = regexp.MustCompile(`(?i)git commit`)
	rawCommitA  = regexp.MustCompile(`git commit[[:space:]]+.*(-a([[:space:]]|$)|--all([[:space:]]|$))`)
	rawPush     = regexp.MustCompile(`(?i)git push`)
	rawForce    = regexp.MustCompile(`git push.*(-f([[:space:]]|$)|--force([[:space:]]|$)|--force-with-lease([[:space:]]|$))`)
	rawClaude   = regexp.MustCompile(`(?i)git add.*\.claude`)
	rawDestroy  = regexp.MustCompile(`(?i)git (reset[[:space:]]+--hard|clean[[:space:]]+-[fdx]|checkout[[:space:]]+--[[:space:]]|checkout[[:space:]]+\.([[:space:]]|$)|stash[[:space:]]+(drop|clear)|tag[[:space:]]+-d([[:space:]]|$))`)
	rawRestore  = regexp.MustCompile(`git restore[^;&|)]*`)
	rawStaged   = regexp.MustCompile(`(^|[[:space:]])(--staged|-[a-zA-RT-Z]*S[a-zA-Z]*)([[:space:]]|$)`)
	rawTree     = regexp.MustCompile(`(^|[[:space:]])(--worktree|-[a-zA-VX-Z]*W[a-zA-Z]*)([[:space:]]|$)`)
	rawStashRd  = regexp.MustCompile(`git stash[[:space:]]+(list|show|--help|-h)([^A-Za-z0-9_-]|$)`)
	rawStash    = regexp.MustCompile(`git stash([^A-Za-z0-9_-]|$)`)
	rawBranchD  = regexp.MustCompile(`git branch[[:space:]]+-D([[:space:]]|$)`)
)

func anyLine(re *regexp.Regexp, text string) bool {
	for _, l := range strings.Split(text, "\n") {
		if re.MatchString(l) {
			return true
		}
	}
	return false
}

func rawScan(o Options, norm string, prefixed bool) Verdict {
	raw := o.Command
	git := gitOpts.ReplaceAllString(leadAssign.ReplaceAllString(norm, ""), "git ")
	coauthor := strings.Contains(lower(raw), "co-authored-by")
	switch {
	case anyLine(rawNoVerify, raw):
		return *refuse(NoVerify)
	case anyLine(rawAdd, git):
		return *refuse(MassStaging)
	}
	if anyLine(rawCommit, git) {
		switch {
		case !prefixed:
			return *refuse(CommitNoPrefix)
		case anyLine(rawCommitA, git):
			return *refuse(CommitAll)
		case coauthor:
			return *refuse(AISignature)
		}
		return Verdict{Commit: true}
	}
	if anyLine(rawPush, git) {
		switch {
		case anyLine(rawForce, git):
			return *refuse(ForcePush)
		case !prefixed:
			return *refuse(PushNoPrefix)
		}
		return Verdict{}
	}
	if coauthor {
		return *refuse(AISignature)
	}
	if anyLine(rawClaude, raw) {
		if prefixed {
			return Verdict{}
		}
		return *refuse(ClaudeDirPrefix)
	}
	if anyLine(rawDestroy, git) {
		return *refuse(Destructive)
	}
	for _, l := range strings.Split(git, "\n") {
		for _, occ := range rawRestore.FindAllString(l, -1) {
			if !rawStaged.MatchString(occ) || rawTree.MatchString(occ) {
				return *refuse(Destructive)
			}
		}
	}
	if o.AgentType != "" && anyLine(rawStash, rawStashRd.ReplaceAllString(git, "git stash-read$2")) {
		return *refuse(StashFromAgent)
	}
	if anyLine(rawBranchD, git) {
		return *refuse(ForceDelete)
	}
	return Verdict{}
}
