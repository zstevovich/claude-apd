// Package specblind keeps the adversarial reviewer blind to the task's intent:
// it may not read the pipeline directory (spec card, plan, rationales) or the
// project memory, by any tool. Ported from plugins/apd/bin/core/guard-spec-blind.
//
// Two channels. A Read/Glob/Grep target is compared as a canonical path. A Bash
// command is judged twice: the raw text for blinded paths named anywhere in it
// (an interpreter runs its heredoc body), then every statement the shell reader
// reports, with the rule that a read rooted at an ancestor of a blinded
// directory reaches it.
package specblind

import (
	"path/filepath"
	"regexp"
	"strings"

	"github.com/zstevovich/claude-apd/guard/internal/paths"
	"github.com/zstevovich/claude-apd/guard/internal/shell"
	"github.com/zstevovich/claude-apd/guard/internal/tools"
)

// AllowedBasename is the one file in the pipeline directory the reviewer reads:
// its own scope.
const AllowedBasename = ".reviewed-files"

type Options struct {
	AgentType string
	Tool      string // Read, Glob, Grep, Bash
	FilePath  string
	Command   string

	ProjectDir  string
	PipelineDir string
	MemoryDir   string
	Home        string
	Cwd         string
}

// Verdict: What completes "adversarial-reviewer may not read …"; Detail is the
// audit log's detail field.
type Verdict struct{ What, Detail string }

func (v Verdict) Blocked() bool { return v.What != "" }

// Governs reports whether the guard applies to this caller: the adversarial
// reviewer under its canonical name or any name that still says what it is.
func Governs(agentType string) bool { return strings.Contains(agentType, "adversarial") }

type denied Verdict

type judge struct {
	o         Options
	env       paths.Env
	projCanon string
	pipe, mem string // project-relative
	allowed   string
	command   string
	opaque    bool
	bodies    string // every heredoc body in the command
	bodiesRun bool
	vars      map[string][]string
	depth     int
}

func (j *judge) deny(what, detail string) { panic(denied{what, detail}) }

func relTo(dir, root string) string {
	return strings.TrimPrefix(dir, strings.TrimSuffix(root, "/")+"/")
}

// Judge returns the verdict for one tool call.
func Judge(o Options) (v Verdict) {
	if !Governs(o.AgentType) {
		return Verdict{}
	}
	j := &judge{o: o, env: paths.Env{Home: o.Home}, command: o.Command, vars: map[string][]string{}}
	j.projCanon = paths.Real(o.ProjectDir)
	if j.projCanon == "" {
		j.projCanon = o.ProjectDir
	}
	// compared without regard to case: on a case-insensitive volume `.APD/pipeline`
	// is the same directory
	j.pipe = strings.ToLower(relTo(o.PipelineDir, o.ProjectDir))
	j.mem = strings.ToLower(relTo(o.MemoryDir, o.ProjectDir))
	j.allowed = j.pipe + "/" + AllowedBasename
	defer func() {
		if r := recover(); r != nil {
			d, ok := r.(denied)
			if !ok {
				panic(r)
			}
			v = Verdict(d)
		}
	}()
	if o.FilePath == "" && o.Command == "" && in(o.Tool, "Grep", "Glob") {
		j.deny("the whole project (a "+o.Tool+" with no path)", "tool:"+o.Tool+":nopath")
	}
	if o.FilePath != "" {
		j.filePath(o.FilePath)
	}
	if o.Command != "" {
		j.bash()
	}
	return Verdict{}
}

// relPath is the physical path of p relative to the project: "" for the project
// root itself, an absolute path when p lies outside the project.
func (j *judge) relPath(p string) string {
	abs := j.env.CanonAbs(p, j.o.Cwd, false)
	if strings.EqualFold(abs, j.projCanon) {
		return ""
	}
	if n := len(j.projCanon) + 1; len(abs) > n && strings.EqualFold(abs[:n], j.projCanon+"/") {
		return abs[n:]
	}
	return abs
}

// ---------- channel 1: Read / Glob / Grep ----------

func (j *judge) filePath(p string) {
	rel := strings.ToLower(norm(j.relPath(p)))
	// a `..` that survived resolution: the comparison below cannot be trusted
	if paths.HasTraversal(rel) {
		j.deny("a path with unresolved traversal ("+rel+")", rel)
	}
	if rel == j.allowed {
		return
	}
	show, detail := rel, rel
	if rel == "" {
		show, detail = "the project root", "."
	}
	if reaches(rel, j.pipe) {
		j.deny("pipeline state ("+show+")", detail)
	}
	if reaches(rel, j.mem) {
		j.deny("project memory ("+show+")", detail)
	}
}

// ---------- channel 2: Bash ----------

// blindCommands print pipeline state through a sanctioned path: a leak for this role.
var blindCommands = []string{"pipeline show", "pipeline status", "pipeline metrics", "pipeline report", "apd report"}

// one thing the shell reader reported, kept in order
type event struct {
	cmd    *shell.Command
	pwd    bool     // a substitution in this command's words ran `pwd`
	loop   []string // items of a for/select loop
	name   string   // … and its variable
	quoted string   // a substitution inside double quotes, as written
}

type collector struct {
	events []event
	subst  int
	pwd    bool
}

func (c *collector) Enter(s shell.Scope) {
	if s == shell.Substitution {
		c.subst++
	}
}
func (c *collector) Leave(s shell.Scope) {
	if s == shell.Substitution {
		c.subst--
	}
}
func (c *collector) Call([]shell.Assign) {}
func (c *collector) Return()             {}
func (c *collector) Lost(string)         {}
func (c *collector) QuotedSubst(t string) {
	c.events = append(c.events, event{quoted: t})
}
func (c *collector) For(name string, items []string) {
	c.events = append(c.events, event{loop: append([]string{}, items...), name: name})
}
func (c *collector) Command(cmd shell.Command) {
	e := event{cmd: &cmd}
	dollar := false
	for _, w := range cmd.Words {
		dollar = dollar || strings.HasPrefix(w, "$")
	}
	if dollar {
		e.pwd, c.pwd = c.pwd, false
	}
	if c.subst > 0 && len(cmd.Words) > 0 && base(cmd.Words[0]) == "pwd" {
		c.pwd = true
	}
	c.events = append(c.events, e)
}

func read(text string) ([]event, bool) {
	c := &collector{}
	if err := shell.Walk(text, c); err != nil {
		return nil, false
	}
	return c.events, true
}

func (j *judge) bash() {
	for _, bc := range blindCommands {
		if strings.Contains(j.command, bc) {
			j.deny("pipeline state via `"+bc+"`", "cmd:"+bc)
		}
	}
	events, ok := read(j.command)
	j.opaque = !ok
	j.rawPass()
	if !ok {
		j.fallback()
		return
	}
	for _, e := range events {
		if e.cmd != nil {
			j.bodies += e.cmd.Heredoc
		}
	}
	j.run(events)
}

// blindCommand judges the words of a statement for an apd command that prints
// pipeline state, by any alias and however the words are spaced or quoted.
func (j *judge) blindCommand(words []string) {
	at := func(i int) string {
		if i < len(words) {
			return words[i]
		}
		return ""
	}
	unknown := func(s string) bool { return strings.ContainsAny(s, "$`") }
	prints := func(s string) bool { return in(s, "show", "status", "metrics", "report", "stats") || unknown(s) }
	for i, w := range words {
		next, after := at(i+1), at(i+2)
		switch b := base(w); {
		case b == "apd" && (in(next, "report", "rp") || unknown(next)):
			j.deny("pipeline state via `apd "+next+"`", "cmd:apd report")
		case b == "apd" && in(next, "pipeline", "pl") && prints(after):
			j.deny("pipeline state via `apd "+next+" "+after+"`", "cmd:pipeline "+after)
		case b == "pipeline-advance" && prints(next):
			j.deny("pipeline state via `pipeline-advance "+next+"`", "cmd:pipeline "+next)
		case b == "pipeline-report" || b == "pipeline-report-turns":
			j.deny("pipeline state via `"+b+"`", "cmd:apd report")
		}
	}
}

// named: the text, already in lower case, carries a blinded directory by name. The review scope itself
// is allowed.
func (j *judge) named(text, shown string) {
	text = strings.TrimSuffix(text, j.allowed)
	switch {
	case strings.Contains(text, j.pipe):
		j.deny("pipeline state ("+shown+")", "cmd:"+shown)
	case strings.Contains(text, j.mem):
		j.deny("project memory ("+shown+")", "cmd:"+shown)
	}
}

func (j *judge) globHits(g string) bool {
	if !isGlob(g) && !strings.Contains(g, anyText) {
		return false
	}
	gn := norm(g)
	return globReaches(gn, j.pipe) != "" || globReaches(gn, j.mem) != ""
}

// rawPass judges the text of the command word by word, heredoc bodies
// included: a blinded path named anywhere, a setting that widens what a pattern
// reads, an option that takes git past the index.
func (j *judge) rawPass() {
	for _, raw := range fields(j.command) {
		tok := strip(raw, `;&|()<>`)
		if tok == "" {
			continue
		}
		// a blinded path can ride inside a token that is not a path at all:
		// `git show HEAD:.apd/pipeline/spec-card.md`
		plain := strip(tok, `"'`)
		j.named(strings.ToLower(plain), plain)
		// what the shell makes of the token
		g := gtok(strings.ToLower(raw))
		j.named(g, plain)
		// The pattern test belongs to the statements, where the command is known
		// (a grep pattern or a `find -name` value is not a path). Here it runs only
		// when the command could not be read: fail closed.
		if j.opaque && j.globHits(g) {
			j.deny("pipeline state or project memory (a pattern that can match it: "+plain+")", "cmd:"+plain)
		}
		// settings that change what a glob matches, and GREP_OPTIONS, which makes
		// a plain grep recursive
		switch {
		case strings.HasPrefix(plain, "GLOBIGNORE="), strings.HasPrefix(plain, "GREP_OPTIONS="):
			j.deny("pipeline state (a shell or grep setting that widens what a pattern reads: "+plain+")", "cmd:"+plain)
		case j.opaque && (strings.Contains(plain, "dotglob") || strings.Contains(plain, "globdots") ||
			strings.Contains(plain, "GLOBDOTS") || strings.Contains(plain, "extglob")):
			j.deny("pipeline state (a shell or grep setting, in a command that could not be tokenized: "+plain+")", "cmd:"+plain)
		}
		// options that make git read the working tree instead of the index
		opt := plain
		if k := strings.Index(opt, "="); k >= 0 {
			opt = opt[:k]
		}
		opt = strip(opt, `\`)
		if abbr(opt, "--no-index", 7) || abbr(opt, "--untracked", 5) || abbr(opt, "--no-exclude-standard", 8) {
			j.deny("files git does not track (`"+opt+"` reads the working tree past the index, pipeline state included)", "cmd:"+opt)
		}
		t := strings.ToLower(cutGlob(norm(tok)))
		if t == "" || t == j.allowed {
			continue // the root is judged with the statements
		}
		if t == j.pipe || strings.HasPrefix(t, j.pipe+"/") || t == j.mem || strings.HasPrefix(t, j.mem+"/") {
			j.deny("pipeline state or project memory ("+t+")", "cmd:"+t)
		}
	}
}

// rawHasDot: the command carries a bare `.` / `./` word anywhere.
func (j *judge) rawHasDot() bool {
	for _, r := range fields(j.command) {
		if dotOnly(strip(r, `][{};&|()<>"',*`)) {
			return true
		}
	}
	return false
}

// pathWord judges a word the shell opens itself or hands to a loop: a
// redirection target, an item of a `for` list.
func (j *judge) pathWord(w string) {
	for _, cand := range j.expand(w) {
		g := gtok(strings.ToLower(cand))
		j.named(g, cand)
		if lt := norm(g); lt != "" && lt != j.allowed && (reaches(lt, j.pipe) || reaches(lt, j.mem)) {
			j.deny("a directory that contains pipeline state ("+cand+", in a loop list or a redirection)", "cmd:"+cand)
		}
		if j.globHits(g) {
			j.deny("pipeline state or project memory (a pattern that can match it: "+cand+")", "cmd:"+cand)
		}
		j.physical(true, cand)
	}
}

// ---------- variables ----------

// expand returns the word and, when it names variables the command itself
// assigned, the word with those values filled in. Every value a name was given
// anywhere in the command counts.
func (j *judge) expand(w string) []string {
	out := []string{w}
	if !strings.Contains(w, "$") {
		return out
	}
	for name, vals := range j.vars {
		if !strings.Contains(w, "$"+name) && !strings.Contains(w, "${"+name+"}") {
			continue
		}
		var next []string
		for _, cur := range out {
			next = append(next, cur)
			for _, v := range vals {
				r := strings.ReplaceAll(strings.ReplaceAll(cur, "${"+name+"}", v), "$"+name, v)
				if r != cur && len(next) < 16 {
					next = append(next, r)
				}
			}
		}
		out = next
	}
	return out
}

func (j *judge) setvar(name, value string) {
	if name == "" || len(j.vars[name]) >= 8 {
		return
	}
	for _, v := range j.expand(value) {
		if !in(v, j.vars[name]...) && len(j.vars[name]) < 8 {
			j.vars[name] = append(j.vars[name], v)
		}
	}
}

// variants returns the statement as written and with assigned variables filled in.
func (j *judge) variants(words []string) [][]string {
	out := [][]string{words}
	if len(j.vars) == 0 {
		return out
	}
	for i, w := range words {
		alts := j.expand(w)
		if len(alts) == 1 {
			continue
		}
		var next [][]string
		for _, cur := range out {
			for _, a := range alts {
				if len(next) >= 16 {
					break
				}
				cp := append([]string{}, cur...)
				cp[i] = a
				next = append(next, cp)
			}
		}
		out = next
	}
	return out
}

// ---------- statements ----------

func (j *judge) run(events []event) {
	for _, e := range events {
		switch {
		case e.quoted != "":
			t := e.quoted
			if strings.HasPrefix(t, "$(") {
				t = strings.TrimSuffix(strings.TrimPrefix(t, "$("), ")")
			} else {
				t = strings.Trim(t, "`")
			}
			j.text(t)
		case e.cmd == nil:
			for _, it := range e.loop {
				j.pathWord(it)
				j.setvar(e.name, it)
			}
		default:
			c := e.cmd
			for _, a := range c.Assigns {
				if !a.Opaque {
					j.setvar(a.Name, a.Value)
				}
			}
			for _, r := range append(append([]string{}, c.Reads...), c.Writes...) {
				j.pathWord(r)
			}
			if len(c.Words) == 0 {
				continue
			}
			for _, words := range j.variants(c.Words) {
				j.blindCommand(words)
				u := tools.Unwrap(words)
				if u.Cmd == "" {
					continue
				}
				if text, ok := tools.ShellText(base(u.Cmd), u.Args, ""); ok {
					j.text(text)
				}
				args := u.Args
				if e.pwd {
					// `$(pwd)` unquoted: the working directory, taken as the project root
					args = append([]string{}, args...)
					for i, a := range args {
						if a == "$" || strings.HasPrefix(a, "$/") {
							args[i] = j.projCanon + a[1:]
						}
					}
				}
				if u.Xargs {
					j.stmt("xargs", append([]string{base(u.Cmd)}, args...))
				} else {
					j.stmt(base(u.Cmd), args)
				}
			}
		}
	}
}

// text judges shell text another shell will run: a heredoc body fed to a
// shell, the string after `sh -c`, a command line handed to a runner.
func (j *judge) text(t string) {
	if t == "" {
		return
	}
	if j.depth < 8 {
		if events, ok := read(t); ok {
			j.depth++
			j.run(events)
			j.depth--
			return
		}
	}
	for _, r := range fields(t) {
		if dotOnly(strip(r, `;&|()<>"'`)) {
			j.deny("a directory that contains pipeline state (the project root; a shell body could not be tokenized)", "cmd:.")
		}
	}
}

func (j *judge) heredocBodies() {
	if !j.bodiesRun && strings.Contains(j.command, "<<") {
		j.bodiesRun = true
		j.text(j.bodies)
	}
}

var grepFamily = map[string]bool{"grep": true, "egrep": true, "fgrep": true, "ggrep": true, "ugrep": true, "ug": true,
	"zgrep": true, "bzgrep": true, "xzgrep": true, "zegrep": true, "zfgrep": true, "pcregrep": true, "pcre2grep": true}

var rgFamily = map[string]bool{"rg": true, "ag": true, "ack": true, "ack-grep": true, "sift": true, "pt": true, "ucg": true}

var readers = map[string]bool{}

func init() {
	for _, c := range strings.Fields("find fd fdfind bfs gfind ls gls eza exa lsd tree du gdu cat head tail less more diff cp gcp rsync tar gtar zip 7z 7za unzip xargs stat file wc sort awk gawk sed gsed python python3 node php ruby perl rg ag ack ack-grep sift pt ucg rgrep ditto") {
		readers[c] = true
	}
}

// grepRecursive: a grep argument that makes it read directories.
func grepRecursive(a string) bool {
	switch {
	case a == "recurse", strings.HasPrefix(a, "--di") && strings.Contains(a[4:], "=r"),
		strings.HasPrefix(a, "--rec"), strings.HasPrefix(a, "--deref"):
		return true
	case in(a, "-r", "-R", "-d"):
		return true
	case strings.HasPrefix(a, "--"):
		return false
	}
	return strings.HasPrefix(a, "-") && strings.ContainsAny(a, "rR")
}

// isReader: does this command read a directory tree it is handed?
func isReader(c string, args []string) bool {
	if readers[c] {
		return true
	}
	if grepFamily[c] {
		for _, a := range args {
			if grepRecursive(a) {
				return true
			}
		}
	}
	return false
}

// judgeGit: staging is how an ignored file reaches `git diff --cached`; an
// alias can run anything; ls-files can list the ignored names.
func (j *judge) judgeGit(args []string) {
	sub, i := "", 0
	for i < len(args) {
		a := args[i]
		i++
		switch {
		case a == "-c":
			if i < len(args) {
				if v := strip(args[i], `"'`); strings.HasPrefix(v, "alias.") {
					j.deny("the index or the working tree (a git alias defined on the command line can run anything: "+args[i]+")", "cmd:git-alias")
				}
				i++
			}
			continue
		case in(a, "-C", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env"):
			if i < len(args) {
				i++
			}
			continue
		case strings.HasPrefix(a, "-"):
			continue
		}
		sub = a
		break
	}
	rest := args[i:]
	switch {
	case in(sub, "add", "stage"):
		j.deny("the index (git "+sub+" stages files — ignored ones with -f — for `git diff --cached`; this role reads, it does not stage)", "cmd:git-"+sub)
	case strings.HasPrefix(sub, "$"), strings.HasPrefix(sub, "`"):
		j.deny("the index or the working tree (the git subcommand is text only the shell knows: "+sub+")", "cmd:git-subst")
	case sub == "config":
		for _, a := range rest {
			if strings.HasPrefix(a, "alias.") {
				j.deny("the index or the working tree (defining a git alias: "+a+")", "cmd:git-alias")
			}
		}
	case sub == "update-index":
		for _, a := range rest {
			if in(a, "--add", "--index-info", "--stdin") {
				j.deny("the index (git update-index "+a+" puts files into it, ignored ones included)", "cmd:git-update-index")
			}
		}
	case sub == "ls-files":
		others, std := false, false
		for _, a := range rest {
			switch {
			case in(a, "-o", "--others"):
				others = true
			case a == "--exclude-standard":
				std = true
			case strings.HasPrefix(a, "--"):
				if abbr(a, "--ignored", 4) {
					j.deny("the names of ignored files (git ls-files "+a+")", "cmd:git-ls-files-ignored")
				}
				others = others || abbr(a, "--others", 3)
				std = std || abbr(a, "--exclude-standard", 12)
			case strings.HasPrefix(a, "-") && strings.Contains(a, "i"):
				j.deny("the names of ignored files (git ls-files "+a+" lists pipeline state for a reader down the pipe)", "cmd:git-ls-files-ignored")
			case strings.HasPrefix(a, "-") && strings.Contains(a, "o"):
				others = true
			}
		}
		if others && !std {
			j.deny("the names of ignored files (git ls-files --others without --exclude-standard lists pipeline state)", "cmd:git-ls-files-others")
		}
	}
}

// operands counts the words that are not options; valued options take the next word.
func operands(args []string, valued ...string) int {
	n, skip := 0, false
	for _, a := range args {
		switch {
		case skip:
			skip = false
		case in(a, valued...):
			skip = true
		case strings.HasPrefix(a, "-"):
		default:
			n++
		}
	}
	return n
}

// readsCwd: a recursive reader with no path operand reads the current
// directory — `grep -rn foo`, `rg foo`, `find -name x`, `ls -R`, `tree`.
func readsCwd(c string, args []string) bool {
	switch {
	case in(c, "find", "gfind", "bfs"):
		i := 0
		for i < len(args) {
			a := args[i]
			if in(a, "-H", "-L", "-P") || strings.HasPrefix(a, "-O") {
				i++
			} else if a == "-D" {
				i += 2
			} else {
				break
			}
		}
		if i >= len(args) {
			return true
		}
		a := args[i]
		return a == "" || strings.HasPrefix(a, "-") || in(a, "(", "!", `\(`)
	case in(c, "tree", "du", "gdu"):
		return operands(args, "-L", "-P", "-I", "-o", "-d", "--max-depth", "--exclude", "-B", "--block-size",
			"--threshold", "-t", "--filelimit", "--charset", "--sort", "--timefmt") == 0
	case in(c, "ls", "gls", "eza", "exa", "lsd"):
		rec, n := false, 0
		for _, a := range args {
			switch {
			case in(a, "--recursive", "--tree"):
				rec = true
			case strings.HasPrefix(a, "--"):
			case strings.HasPrefix(a, "-"):
				rec = rec || strings.Contains(a, "R")
			default:
				n++
			}
		}
		return rec && n == 0
	case in(c, "fd", "fdfind"):
		for _, a := range args {
			if in(a, "--search-path", "--base-directory") || strings.HasPrefix(a, "--search-path=") || strings.HasPrefix(a, "--base-directory=") {
				return false
			}
		}
		return operands(args, "-e", "-E", "-t", "-d", "-x", "-X", "-j", "-c", "-S", "-o", "--extension", "--exclude",
			"--type", "--max-depth", "--min-depth", "--exact-depth", "--exec", "--exec-batch", "--color", "--size",
			"--changed-within", "--changed-before", "--owner", "--threads", "--max-results", "--batch-size",
			"--ignore-file", "--path-separator", "--format") < 2
	case c == "rgrep": // always recursive: pattern + paths
		return operands(args) <= 1
	case grepFamily[c]:
		n, skip, haspat, rec := 0, false, false, false
		for _, a := range args {
			if skip {
				skip = false
				continue
			}
			switch {
			case in(a, "-e", "-f", "--regexp", "--file"):
				haspat, skip = true, true
			case strings.HasPrefix(a, "--regexp="), strings.HasPrefix(a, "--file="):
				haspat = true
			case in(a, "-m", "-A", "-B", "-C", "-D", "--include", "--exclude", "--exclude-dir", "--exclude-from",
				"--max-count", "--after-context", "--before-context", "--context", "--label", "--devices",
				"--binary-files", "--directories", "-d"):
				skip = true
			case in(a, "-r", "-R", "--recursive", "--dereference-recursive", "--directories=recurse"):
				rec = true
			case strings.HasPrefix(a, "--di") && strings.Contains(a[4:], "=r"), strings.HasPrefix(a, "--rec"), strings.HasPrefix(a, "--deref"):
				rec = true // GNU grep takes prefixes: `--dir=recurse`, `--recurs`
			case strings.HasPrefix(a, "--di"):
				skip = true
			case strings.HasPrefix(a, "--"):
			case strings.HasPrefix(a, "-") && len(a) > 1 && (strings.HasSuffix(a, "e") || strings.HasSuffix(a, "f")):
				// a cluster ending in -e / -f takes the pattern as its value
				haspat, skip = true, true
				rec = rec || strings.ContainsAny(a, "rR")
			case strings.HasPrefix(a, "-") && strings.ContainsAny(a, "rR"):
				rec = true
			case strings.HasPrefix(a, "-"):
			default:
				n++
			}
		}
		if !rec {
			for _, a := range args {
				rec = rec || in(a, "rec", "recu", "recur", "recurs", "recurse") // `-d recurse`
			}
		}
		if !rec {
			return false
		}
		if !haspat {
			n-- // the first operand is the pattern
		}
		return n <= 0
	case rgFamily[c]:
		n, skip, haspat := 0, false, false
		for _, a := range args {
			if skip {
				skip = false
				continue
			}
			switch {
			case in(a, "--files", "--type-list"):
				haspat = true // no pattern operand in these modes
			case in(a, "-e", "-f", "--regexp", "--file"):
				haspat, skip = true, true
			case strings.HasPrefix(a, "--regexp="), strings.HasPrefix(a, "--file="):
				haspat = true
			case in(a, "-g", "-t", "-T", "-A", "-B", "-C", "-m", "-j", "-M", "-E", "-r", "-d", "-G", "--glob", "--iglob",
				"--type", "--type-not", "--type-add", "--type-clear", "--max-count", "--context", "--after-context",
				"--before-context", "--max-depth", "--depth", "--threads", "--encoding", "--sort", "--sortr", "--color",
				"--colors", "--replace", "--max-columns", "--max-filesize", "--pre", "--pre-glob", "--engine",
				"--field-match-separator", "--field-context-separator", "--path-separator", "--ignore-file",
				"--context-separator", "--dfa-size-limit", "--regex-size-limit", "--ignore", "--ignore-dir",
				"--file-search-regex", "--pager", "--workers", "--ackrc", "--match"):
				skip = true
			case strings.HasPrefix(a, "-"):
			default:
				n++
			}
		}
		if !haspat {
			n--
		}
		return n <= 0
	}
	return false
}

var searchers = map[string]bool{"rgrep": true}

func init() {
	for c := range grepFamily {
		searchers[c] = true
	}
	for c := range rgFamily {
		searchers[c] = true
	}
}

// judgeGlobs applies the pattern test to the arguments that are paths. A
// grep/rg pattern, the value of an option that takes a pattern or a glob, and
// the program of jq or an interpreter are text for that tool, not paths.
func (j *judge) judgeGlobs(reader bool, c string, args []string) {
	hasprog := false
	for _, a := range args {
		if in(a, "-e", "-f", "--regexp", "--file", "--from-file") || strings.HasPrefix(a, "--regexp=") ||
			strings.HasPrefix(a, "--file=") || strings.HasPrefix(a, "--from-file=") {
			hasprog = true
		}
	}
	skip, first, forced, gsub := 0, true, false, ""
	for _, a := range args {
		if skip > 0 {
			skip--
			continue
		}
		switch {
		case searchers[c]:
			if in(a, "-e", "-f", "--regexp", "--file", "-g", "-t", "-T", "-m", "-A", "-B", "-C", "-D", "-d", "-j", "-M", "-E", "-G",
				"--glob", "--iglob", "--type", "--type-not", "--type-add", "--include", "--exclude", "--exclude-dir",
				"--exclude-from", "--max-count", "--after-context", "--before-context", "--context", "--label",
				"--devices", "--binary-files", "--directories", "--max-depth", "--replace", "--pre", "--pre-glob",
				"--ignore-file", "--ignore", "--ignore-dir", "--file-search-regex", "--match", "--color", "--colors",
				"--sort", "--sortr", "--encoding", "--threads") {
				skip = 1
				continue
			}
			if strings.HasPrefix(a, "-") {
				continue
			}
			if !hasprog && first {
				first = false
				continue // the pattern operand
			}
		case in(c, "find", "gfind", "bfs"):
			if in(a, "-name", "-iname", "-path", "-ipath", "-wholename", "-iwholename", "-regex", "-iregex", "-lname",
				"-ilname", "-printf", "-fprintf", "-user", "-group", "-perm", "-size", "-mtime", "-mmin", "-type",
				"-maxdepth", "-mindepth") {
				skip = 1
				continue
			}
		case in(c, "fd", "fdfind"):
			if in(a, "-e", "-E", "-t", "-d", "-x", "-X", "-g", "--extension", "--exclude", "--type", "--max-depth", "--glob") {
				skip = 1
				continue
			}
			if strings.HasPrefix(a, "-") {
				continue
			}
			if first {
				first = false
				continue // the pattern operand
			}
		case in(c, "python", "python2", "python3", "node", "nodejs", "php"):
			if in(a, "-c", "-e", "-r", "-p", "-m", "--eval", "--print", "-W", "-X") {
				skip = 1
				continue
			}
			if strings.HasPrefix(a, "-") {
				continue
			}
		case in(c, "jq", "yq"):
			switch {
			case in(a, "-f", "--from-file", "--indent"):
				skip = 1
				continue
			case in(a, "--arg", "--argjson"):
				skip = 2
				continue
			case in(a, "--slurpfile", "--rawfile"):
				skip, forced = 1, true // the name; the file after it is a path
				continue
			case strings.HasPrefix(a, "-"):
				continue
			}
			if forced {
				forced = false // … judged, never taken for the filter
			} else if !hasprog && first {
				first = false
				continue // the filter
			}
		case c == "git":
			switch {
			case in(a, "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--grep", "-G", "-S", "--author", "--committer",
				"--format", "--pretty", "-m", "--message", "-L", "--since", "--until", "--date", "-e"):
				skip = 1
				continue
			case strings.HasPrefix(a, "--grep="), strings.HasPrefix(a, "--author="), strings.HasPrefix(a, "--committer="),
				strings.HasPrefix(a, "--format="), strings.HasPrefix(a, "--pretty="), strings.HasPrefix(a, "--since="),
				strings.HasPrefix(a, "--until="), len(a) > 2 && (strings.HasPrefix(a, "-G") || strings.HasPrefix(a, "-S")):
				continue
			case strings.HasPrefix(a, "-"):
			case gsub == "":
				gsub = a
				continue
			case gsub == "grep" && !hasprog && first:
				first = false
				continue
			}
		}
		g := gtok(strings.ToLower(a))
		rest := strings.TrimSuffix(g, j.allowed)
		if strings.Contains(rest, j.pipe) || strings.Contains(rest, j.mem) {
			j.deny("pipeline state or project memory ("+a+")", "cmd:"+a)
		}
		if rest != g {
			continue // the review scope itself
		}
		if !isGlob(g) && !strings.Contains(g, anyText) {
			continue
		}
		gn := norm(g)
		for _, b := range []string{j.pipe, j.mem} {
			switch globReaches(gn, b) {
			case "full":
				j.deny("pipeline state or project memory (a pattern that can match it: "+a+")", "cmd:"+a)
			case "anc":
				if reader || in(c, "cd", "pushd") {
					j.deny("a directory that contains pipeline state (a pattern that can match it: "+a+")", "cmd:"+a)
				}
			}
		}
	}
}

// shellSettings: a shell told to match dot names with a plain `*`, or to read `+(…)` forms.
func (j *judge) shellSettings(c string, args []string) {
	switch {
	case in(c, "shopt", "setopt", "set"):
		for _, a := range args {
			if in(a, "dotglob", "globdots", "GLOB_DOTS", "GLOBDOTS", "glob_dots", "extglob", "extendedglob", "EXTENDED_GLOB", "kshglob") {
				j.deny("pipeline state (a shell setting that widens what a pattern matches: "+c+" "+a+")", "cmd:"+c+"-"+a)
			}
		}
	case in(c, "bash", "zsh", "sh", "ksh", "dash"):
		for _, a := range args {
			if in(a, "dotglob", "globdots", "extglob", "extendedglob", "GLOB_DOTS") {
				j.deny("pipeline state (a shell started with a setting that widens what a pattern matches: "+a+")", "cmd:"+c+"-"+a)
			}
		}
	}
}

// runners hand their arguments to another command; which word that is cannot be
// told here, so the whole statement counts as a reader.
var runners = map[string]bool{}

func init() {
	for _, c := range strings.Fields("stdbuf setsid unbuffer flock script watch busybox chrt taskset strace ltrace nohup command exec time env nice ionice sudo doas caffeinate timeout hyperfine parallel ssh perf valgrind gdb docker podman make npx npm pnpm yarn composer bundle poetry uv pipx cargo go dotnet mvn gradle") {
		runners[c] = true
	}
}

const (
	walkers  = `(os\.walk|os\.fwalk|glob\.glob|glob\.iglob|scandir|listdir|readdirSync|readdir|opendir|Dir\.glob|Dir\.entries|Dir\.children|Find\.find|File::Find|RecursiveDirectoryIterator|\.rglob|\.glob|\.iterdir)`
	shellout = "(system|exec|popen|spawn|subprocess|run|shell_exec|passthru|child_process|Open3|proc_open|pexpect|delegator|invoke|qx|%x|`)"
	rdWords  = `(find|fd|ls|tree|du|rg|ag|ack|grep|cat|head|tail|diff|cp|rsync|tar|zip)`
)

var (
	walkRe1  = regexp.MustCompile(walkers + `[^;]* (\.|\./|\*\*[^ ]*)( |$)`)
	walkRe2  = regexp.MustCompile(` (\.|\./) +\.(walk|rglob|glob|iterdir)`)
	cwdRe    = regexp.MustCompile(`(getcwd|os\.curdir|Path\.cwd|Path  *\.|process\.cwd|Dir\.pwd|Dir\.getwd|cwd  *\.)`)
	walkRe3  = regexp.MustCompile(`(os\.walk|os\.fwalk|glob\.glob|glob\.iglob|scandir|listdir|readdirSync|readdir|opendir|Dir\.glob|Dir\.entries|Find\.find|File::Find|find *[^a-z]|\.rglob|\.glob|\.iterdir)`)
	outRe1   = regexp.MustCompile(shellout + `[^;]* ` + rdWords + `( [^;]*)? \.( |$)`)
	outRe2   = regexp.MustCompile(` ` + rdWords + `( [^;]*)? \.( |$).*` + shellout)
	outRe3   = regexp.MustCompile(` (find|fd|ls|tree|du|rg|ag|ack|grep)( [^|]*)? \. [^|]*\| *getline`)
	escapeRe = regexp.MustCompile(`(?m)(^|[^A-Za-z0-9_])(find|fd|ls|tree|du|rg|ag|ack|grep)([^A-Za-z0-9_])`)
	flatten  = strings.NewReplacer("\n", " ", `"`, " ", "'", " ", "[", " ", "]", " ", "(", " ", ")", " ", "{", " ", "}", " ", ",", " ")
)

// rootNames: the working directory under its other names, taken as the project root.
var rootNames = []string{"$PWD", "${PWD}", "$(pwd)", "`pwd`", "$(git rev-parse --show-toplevel)",
	"$CLAUDE_PROJECT_DIR", "${CLAUDE_PROJECT_DIR}", "$APD_PROJECT_DIR", "${APD_PROJECT_DIR}", "$OLDPWD", "$INIT_CWD",
	"$(pwd -P)", "$(pwd -L)", "${PWD:-.}", "${PWD%/}"}

const containsState = "a directory that contains pipeline state "

func (j *judge) stmt(c string, args []string) {
	if c == "" {
		return
	}
	if c == "git" {
		// git is exempt from the ancestor rule (the pipeline directory is ignored, so
		// `git diff .` cannot surface it) — not from named paths, staging or a glob
		j.judgeGit(args)
		j.judgeGlobs(false, "git", args)
		return
	}
	// a substitution or a variable in command position, or `.` as the command
	// word: what runs is not written here — fail closed on any bare dot
	if strings.HasPrefix(c, "$") || strings.HasPrefix(c, "`") || c == "." {
		if j.rawHasDot() {
			j.deny(containsState+"(the project root, behind a substitution)", "cmd:.")
		}
		return
	}
	// `command -p find .`, `exec -a NAME find .`: the stepped wrapper left its
	// option (and -a's value) as the command word
	for strings.HasPrefix(c, "-") {
		if c == "-a" && len(args) > 0 {
			args = args[1:]
		}
		if len(args) == 0 {
			return
		}
		c, args = args[0], args[1:]
	}
	if in(c, "ln", "gln", "link") {
		// a link made now is followed by a later word of the same command, when
		// nothing on disk can be resolved yet — and this role reads, it links nothing
		j.deny("anything through a new link (this role reads; a link can lead into pipeline state)", "cmd:"+c)
	}
	j.shellSettings(c, args)
	if readsCwd(c, args) {
		j.deny("the whole project (a recursive "+c+" with no path reads the current directory, pipeline state and memory included — name the path)", "cmd:"+c+":nopath")
	}
	reader := isReader(c, args)
	if runners[c] {
		reader = true
		for _, a := range args {
			if strings.ContainsAny(a, " \t\n") {
				j.text(a) // an argument that is itself a command line: `watch "find . -name x"`
			}
			if in(a, "sh", "bash", "zsh", "dash", "ksh") {
				j.heredocBodies() // `cat <<EOF | script -q /dev/null sh`
			}
		}
	}
	switch {
	case c == "xargs":
		// the targets come from stdin
		if j.rawHasDot() {
			j.deny(containsState+"(the project root, through xargs)", "cmd:.")
		}
	case in(c, "sh", "bash", "zsh", "dash", "ksh", "source"):
		// a heredoc fed to a shell runs its body
		hasC, pos, stdin := false, false, false
		for _, a := range args {
			switch {
			case a == "-c":
				hasC = true
			case a == "-s":
				stdin = true
			case strings.HasPrefix(a, "-"):
			case a == "/dev/stdin":
				stdin = true
			default:
				pos = true
			}
		}
		if stdin || (!hasC && !pos) {
			j.heredocBodies()
		}
		if hasC {
			for _, a := range args {
				if (a == "$" || strings.Contains(a, "$(") || strings.Contains(a, "`")) && j.rawHasDot() {
					j.deny(containsState+"(the project root, through a shell fed a substitution)", "cmd:.")
				}
			}
		}
	case in(c, "python", "python2", "python3", "node", "nodejs", "php", "ruby", "perl", "awk", "gawk"):
		flat := flatten.Replace(j.command)
		// a program that walks the tree itself needs no shell-out
		if walkRe1.MatchString(flat) || walkRe2.MatchString(flat) || (cwdRe.MatchString(flat) && walkRe3.MatchString(flat)) {
			j.deny(containsState+"(the project root, walked by a program)", "cmd:walk")
		}
		// a shell-out call that carries a reader word and a bare dot
		if outRe1.MatchString(flat) || outRe2.MatchString(flat) || outRe3.MatchString(flat) {
			j.deny(containsState+"(the project root, through a program that shells out)", "cmd:.")
		}
	case in(c, "sed", "gsed", "vim", "vi", "nvim", "ex", "less", "more"):
		// these run shell text through `e` / `:!` / `!`
		if escapeRe.MatchString(j.command) && j.rawHasDot() {
			j.deny(containsState+"(the project root, through an editor or sed shell escape)", "cmd:.")
		}
	}
	j.judgeGlobs(reader, c, args)
	if reader {
		// a reader whose argument is a substitution reads whatever it yields
		for _, a := range args {
			whole := a == "$" || (strings.HasPrefix(a, "$(") && strings.HasSuffix(a, ")")) || (len(a) > 1 && strings.HasPrefix(a, "`") && strings.HasSuffix(a, "`"))
			if whole && (strings.Contains(j.command, "--show-toplevel") || strings.Contains(j.command, "--show-cdup")) {
				j.deny(containsState+"(the project root, through git rev-parse)", "cmd:toplevel")
			}
		}
		for _, a := range args {
			if (a == "$" || strings.Contains(a, "$(") || strings.Contains(a, "`")) && j.rawHasDot() {
				j.deny(containsState+"(the project root, through a substitution)", "cmd:.")
			}
		}
	}
	for _, a := range args {
		j.operand(reader, strip(a, `"'`))
	}
}

// outside judges a resolved path that is the project root or lies outside the
// project; done reports that nothing is left to judge.
func (j *judge) outside(reader bool, a, rel string) (done bool) {
	switch {
	case rel == "":
		if reader {
			j.deny(containsState+"(the project root: "+a+")", "cmd:"+a)
		}
		return true
	case strings.HasPrefix(rel, "/"):
		if strings.HasPrefix(strings.ToLower(j.projCanon)+"/", strings.ToLower(strings.TrimSuffix(rel, "/"))+"/") {
			if reader {
				j.deny(containsState+"(an ancestor of the project: "+a+")", "cmd:"+a)
			}
			return true
		}
	}
	return false
}

// homeVar: a begins with `$HOME` or `${HOME}` as a whole name; the result is
// where the rest of the path starts, or -1.
func homeVar(a string) int {
	for _, n := range []string{"${HOME}", "$HOME"} {
		if strings.HasPrefix(a, n) && (len(a) == len(n) || a[len(n)] == '/') {
			return len(n)
		}
	}
	return -1
}

// physical judges where an operand really leads: a path that exists is
// resolved through its symbolic links, a pattern by the directory its literal
// part names. `ln -s .apd x` in one call and `cat x/pipeline/…` in the next
// names nothing blinded in the text.
func (j *judge) physical(reader bool, a string) {
	lit := a
	if k := strings.IndexAny(lit, "*?["); k >= 0 {
		lit = lit[:k]
		if s := strings.LastIndex(lit, "/"); s >= 0 {
			lit = lit[:s]
		} else {
			return
		}
	}
	if lit == "" || strings.ContainsAny(lit, "$`") {
		return
	}
	bases := []string{j.projCanon}
	if j.o.Cwd != "" && j.o.Cwd != j.projCanon {
		bases = append(bases, j.o.Cwd) // the call's own working directory, when it is not the root
	}
	for _, b := range bases {
		p := lit
		if !strings.HasPrefix(p, "/") {
			p = b + "/" + p
		}
		// the deepest part that exists is resolved; a path with no link in it
		// comes back as written and is left to the rules on its text
		if real := j.env.CanonAbs(p, "/", false); real != filepath.Clean(p) {
			j.linked(reader, a, real)
		}
	}
}

func (j *judge) linked(reader bool, a, real string) {
	rel := strings.ToLower(norm(j.relPath(real)))
	if rel == j.allowed || strings.HasPrefix(rel, "/") {
		return
	}
	inside := func(b string) bool { return rel == b || strings.HasPrefix(rel, b+"/") }
	if inside(j.pipe) || inside(j.mem) {
		j.deny(containsState+"("+a+" is a link into it)", "cmd:"+a)
	}
	if rel != "" && (strings.HasPrefix(j.pipe, rel+"/") || strings.HasPrefix(j.mem, rel+"/")) {
		j.deny(containsState+"("+a+" is a link to "+rel+")", "cmd:"+a)
	}
	if rel == "" && reader {
		j.deny(containsState+"("+a+" is a link to the project root)", "cmd:"+a)
	}
}

// operand applies the ancestor rule to one argument.
func (j *judge) operand(reader bool, a string) {
	written := a
	// the reader's mark for `~user`, `~+`, `~-`
	if strings.HasPrefix(a, "`~") {
		a = a[1:]
		if in(a, "~+", "~-") || strings.HasPrefix(a, "~+/") || strings.HasPrefix(a, "~-/") {
			a = j.projCanon + a[2:]
		}
	} else if a == "~" || strings.HasPrefix(a, "~/") {
		a = j.o.Home + a[1:]
	} else if h := homeVar(a); h >= 0 {
		a = j.o.Home + a[h:]
	} else {
		for _, n := range rootNames {
			if strings.HasPrefix(a, n) {
				a = j.projCanon + a[len(n):]
				break
			}
		}
	}
	// an absolute operand is resolved: the project root or one of its ancestors
	// is the root, a path inside the project is judged by its relative form
	if strings.HasPrefix(a, "/") {
		rel := j.relPath(a)
		if j.outside(reader, a, rel) {
			return
		}
		if !strings.HasPrefix(rel, "/") {
			a = rel
		}
	}
	// a relative path that climbs back: `src/..` is the project root
	if !in(a, "..") && !strings.HasPrefix(a, "../") && !strings.HasPrefix(a, "/") &&
		(strings.HasSuffix(a, "/..") || strings.Contains(a, "/../")) {
		rel := j.relPath(j.projCanon + "/" + a)
		if j.outside(reader, a, rel) {
			return
		}
		if !strings.HasPrefix(rel, "/") {
			a = rel
		}
	}
	j.physical(reader, a)
	if a != written && isGlob(a) {
		// a pattern behind a name for the root (`$PWD/.a*`), judged in its relative form
		for _, b := range []string{j.pipe, j.mem} {
			if r := globReaches(strings.ToLower(norm(a)), b); r == "full" || (r == "anc" && reader) {
				j.deny(containsState+"(a pattern that can match it: "+written+")", "cmd:"+written)
			}
		}
	}
	t := strings.ToLower(cutGlob(norm(a)))
	// `..`, `../..`, `/` are ancestors of the project; `../<name>` is a sibling.
	// Never `...`: `go test ./...` is the canonical Go form.
	if !strings.Contains(t, "...") && in(t, "..", "../..", "../../..", "../../../..", "../../../../..", "/.", "//", "/./.") {
		if reader {
			j.deny(containsState+"(an ancestor of the project: "+t+")", "cmd:"+t)
		}
		return
	}
	if t == "" {
		if dotOnly(a) && reader { // `.`, `./`, `./.`, `.//`
			j.deny(containsState+"(the project root)", "cmd:.")
		}
		return
	}
	if t == j.allowed {
		return
	}
	if reaches(t, j.pipe) || reaches(t, j.mem) {
		j.deny(containsState+"("+t+")", "cmd:"+t)
	}
}

// fallback judges a command the shell reader could not read: every bare dot and
// every ancestor word denies, a `git add` or a recursive reader anywhere in the
// text denies. A command that starts with git is exempt from the ancestor part.
func (j *judge) fallback() {
	head := j.command
	if k := strings.Index(head, " "); k >= 0 {
		head = head[:k]
	}
	gitHead := base(head) == "git"
	git, grep, rec := false, false, false
	words := fields(j.command)
	for _, raw := range words {
		tok := strip(raw, `;&|()<>"'`)
		if k := strings.LastIndex(tok, "/"); k >= 0 {
			tok = tok[k+1:]
		}
		switch {
		case tok == "git":
			git = true
		case in(tok, "add", "stage"):
			if git {
				j.deny("the index (git "+tok+"; the command could not be tokenized)", "cmd:git-"+tok)
			}
		case in(tok, "find", "gfind", "bfs", "fd", "fdfind", "tree", "du", "gdu", "rg", "ag", "ack"):
			j.deny("the whole project (a recursive "+tok+" in a command that could not be tokenized)", "cmd:"+tok+":opaque")
		case in(tok, "grep", "egrep", "fgrep", "ggrep", "ugrep", "ug"):
			grep = true
		case in(tok, "--recursive", "--dereference-recursive"):
			rec = true
		case strings.HasPrefix(tok, "--"):
		case strings.HasPrefix(tok, "-") && strings.ContainsAny(tok, "rR"):
			rec = true
		}
	}
	if grep && rec {
		j.deny("the whole project (a recursive grep in a command that could not be tokenized)", "cmd:grep:opaque")
	}
	for _, raw := range words {
		tok := strip(raw, `;&|()<>"'`)
		if tok == "" {
			continue
		}
		t := strings.ToLower(cutGlob(norm(tok)))
		if t == "" {
			if in(tok, ".", "./") && !gitHead {
				j.deny(containsState+"(the project root; the command could not be tokenized)", "cmd:.")
			}
			continue
		}
		if t == j.allowed {
			continue
		}
		if (reaches(t, j.pipe) || reaches(t, j.mem)) && !gitHead {
			j.deny(containsState+"("+t+")", "cmd:"+t)
		}
	}
}
