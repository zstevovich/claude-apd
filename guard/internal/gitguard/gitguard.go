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
	return Verdict{Commit: j.commit}
}

func (j *judge) Enter(shell.Scope)        {}
func (j *judge) Leave(shell.Scope)        {}
func (j *judge) For(string, []string)     {}
func (j *judge) Call([]shell.Assign)      {}
func (j *judge) Return()                  {}
func (j *judge) Lost(string)              {}
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
	if j.depth >= 8 || j.verdict != nil {
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

func (j *judge) Command(c shell.Command) {
	if j.verdict != nil || len(c.Words) == 0 {
		return
	}
	// the statement's own `APD_ORCHESTRATOR_COMMIT=1 git …` prefix signs it
	marked := false
	for _, a := range c.Assigns {
		marked = marked || isMarker(a.Name, a.Value)
	}
	u := tools.Unwrap(c.Words)
	for _, e := range u.Env {
		k := strings.Index(e, "=")
		marked = marked || isMarker(e[:k], e[k+1:])
	}
	if text, ok := tools.ShellText(u.Cmd, u.Args, c.Heredoc); ok {
		j.nested(text)
	}
	// git by any spelling and behind any wrapper: every word that is `git` or
	// ends in `/git` starts a statement (xcrun git, /usr/bin/git, find -exec git …)
	words := append([]string{u.Cmd}, u.Args...)
	for k, w := range words {
		if isGit(w) && j.verdict == nil {
			j.statement(words[k+1:], marked)
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

// flags whose next word is a value — never a flag, never a path
var valueFlags = map[string][]string{
	"commit": {"-m", "-F", "-C", "-c", "-t", "--message", "--file", "--author", "--date", "--template", "--fixup",
		"--squash", "--reuse-message", "--reedit-message", "--trailer", "--cleanup", "--pathspec-from-file"},
	"push":  {"-o", "--push-option", "--receive-pack", "--exec", "--repo"},
	"add":   {"--chmod", "--pathspec-from-file"},
	"clean": {"-e", "--exclude"},
}

func (j *judge) statement(words []string, marked bool) {
	// git's own options come before the subcommand
	sub, hooksOff, i := "", false, 0
	for i < len(words) && sub == "" {
		w := words[i]
		switch {
		case w == "-c" || w == "--config-env":
			hooksOff = hooksOff || hooksPath(at(words, i+1), "core.hookspath=")
			i += 2
		case in(w, "-C", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix"):
			i += 2
		case strings.HasPrefix(w, "--config-env="):
			hooksOff = hooksOff || hooksPath(w, "--config-env=core.hookspath=")
			i++
		case strings.HasPrefix(w, "-c"):
			hooksOff = hooksOff || hooksPath(w, "-ccore.hookspath=")
			i++
		case strings.HasPrefix(w, "-"):
			i++
		default:
			sub = w
			i++
		}
	}
	if sub == "" {
		return
	}
	var args []string
	for k := i; k < len(words); k++ {
		if in(words[k], valueFlags[sub]...) {
			k++
			continue
		}
		args = append(args, words[k])
	}
	signed := j.signed(marked)

	// --no-verify on any statement, and its equivalents: commit -n, -c core.hooksPath=…
	nv := has(args, "--no-verify") || hooksOff
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
			if in(a, ".", "./", ":/", "-A", "-u", "-U", "--all", "--update") || strings.HasPrefix(a, "--all=") ||
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
			if a == "--all" || clusterHas(a, "a", "mFCctSu") {
				j.block(CommitAll)
				return
			}
		}
		if strings.Contains(lower(j.o.Command), "co-authored-by") {
			j.block(AISignature)
		}
	case "push":
		for _, a := range args {
			if in(a, "--force", "--force-with-lease", "--force-if-includes") || strings.HasPrefix(a, "--force-with-lease=") ||
				(strings.HasPrefix(a, "+") && len(a) > 1) || clusterHas(a, "f", "o") {
				j.block(ForcePush) // `+refspec` is a force push by refspec
				return
			}
		}
		if !signed {
			j.block(PushNoPrefix)
		}
	case "reset":
		if has(args, "--hard") {
			j.block(Destructive)
		}
	case "clean":
		dry, force := false, false
		for _, a := range args {
			dry = dry || a == "--dry-run" || clusterHas(a, "n", "e")
			force = force || a == "--force" || clusterHas(a, "fdxX", "e")
		}
		if force && !dry {
			j.block(Destructive)
		}
	case "checkout":
		if has(args, "--") || has(args, ".") {
			j.block(Destructive)
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
			tree = tree || a == "--worktree" || (!strings.HasPrefix(a, "--") && clusterHas(a, "W", "s"))
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
		if has(args, "-d") {
			j.block(Destructive)
		}
	case "branch":
		if has(args, "-D") {
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
