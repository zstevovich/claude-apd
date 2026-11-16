// Package bashscope judges a Bash command against a write scope: which files it
// would write, and whether the caller may write there. Ported from
// plugins/apd/bin/core/guard-bash-scope; the command is read by a shell parser.
package bashscope

import (
	"os"
	"regexp"
	"sort"
	"strings"

	"github.com/zstevovich/claude-apd/guard/internal/paths"
	"github.com/zstevovich/claude-apd/guard/internal/shell"
	"github.com/zstevovich/claude-apd/guard/internal/tools"
)

type target struct {
	raw, abs, note string
	apd            bool
}

type cfg struct {
	projDir, projCanon, home, tmpdir, pluginRoot string
	scopeRaw, scopeCanon                         []string
	denyAll                                      bool
	budget                                       *int
	env                                          paths.Env
	apdRoot                                      string // canonical plugins/apd directory; "" = unknown
}

type cwdState struct {
	cwd     string
	unknown bool
}

type judge struct {
	c           *cfg
	command     string
	depth       int
	data        bool
	protectOnly bool
	cwd         string
	cwdUnknown  bool
	dirStack    []cwdState
	group       int
	vn, vv      []string
	targets     []target
	stmtAPD     bool
	rtWrite     bool
	rtText      string
	rtCwdCache  bool
	rtCwdUnk    bool
	rtAllScope  bool
	rtAllProj   bool
	nCwd        []cwdState
	nTxt        []string
	saved       []snapshot
	frames      [][]restore
	altered     map[string]bool
	rd          *shell.Reader
	evals       int
	envN, envV  []string // assignments that reach only the current command's environment
	reason      string
	lost        bool // the reader lost track of the shell's state at some point
}

// ---------- paths (internal/paths) ----------

func isDir(p string) bool  { return paths.IsDir(p) }
func exists(p string) bool { return paths.Exists(p) }

func (c *cfg) canonAbs(p, base string, nofollow bool) string {
	return c.env.CanonAbs(p, base, nofollow)
}
func (c *cfg) canonCached(p, base string, nofollow bool) string {
	return c.env.Canon(p, base, nofollow)
}
func hasTraversal(p string) bool     { return paths.HasTraversal(p) }
func isScratchpad(p string) bool     { return paths.IsScratchpad(p) }
func isPluginCache(p string) bool    { return paths.IsPluginCache(p) }
func (c *cfg) inScope(p string) bool { return paths.InScope(p, c.scopeCanon) }

// ---------- variables ----------

func (j *judge) setvar(n, v string) {
	for i := range j.vn {
		if j.vn[i] == n {
			j.vv[i] = v
			return
		}
	}
	j.vn = append(j.vn, n)
	j.vv = append(j.vv, v)
}

func repl(s, n, v string) string {
	s = strings.ReplaceAll(s, "${"+n+"}", v)
	return strings.ReplaceAll(s, "$"+n, v)
}

func (j *judge) subst(s string) string {
	if !strings.Contains(s, "$") {
		return s
	}
	idx := make([]int, len(j.vn))
	for i := range idx {
		idx[i] = i
	}
	sort.SliceStable(idx, func(a, b int) bool { return len(j.vn[idx[a]]) > len(j.vn[idx[b]]) })
	for _, i := range idx {
		s = repl(s, j.vn[i], j.vv[i])
	}
	s = repl(s, "TMPDIR", j.c.tmpdir)
	if j.c.pluginRoot != "" {
		s = repl(s, "CLAUDE_PLUGIN_ROOT", j.c.pluginRoot)
	}
	s = repl(s, "HOME", j.c.home)
	s = repl(s, "PWD", j.cwd)
	return s
}

func unresolved(s string) bool { return strings.ContainsAny(s, "$`") }

func (j *judge) knownVar(n string) bool {
	for _, v := range j.vn {
		if v == n {
			return true
		}
	}
	switch n {
	case "HOME", "PWD", "TMPDIR":
		return true
	case "CLAUDE_PLUGIN_ROOT":
		return j.c.pluginRoot != ""
	}
	return false
}

var pipeMentionRe = regexp.MustCompile(`(?i)\.apd/pipeline(/|[^A-Za-z0-9_./-]|$)`)

// fenceCase spells the fenced directories the one way the text rules know them.
var fenceCase = regexp.MustCompile(`(?i)\.apd/pipeline|plugins/cache`)

func (j *judge) namesFenced() bool {
	return strings.Contains(strings.ToLower(j.command), "plugins/cache") || pipeMentionRe.MatchString(j.command)
}

var varNameCut = regexp.MustCompile(`[^A-Za-z0-9_].*$`)
var varTail1 = regexp.MustCompile(`^\$\{[^}]*\}`)
var varTail2 = regexp.MustCompile(`^\$[A-Za-z0-9_]*(\{[^}]*\})?`)

func varName(p string) string {
	v := strings.TrimPrefix(p, "$")
	v = strings.TrimPrefix(v, "{")
	return varNameCut.ReplaceAllString(v, "")
}
func varTail(p string) string {
	if varTail1.MatchString(p) {
		p = varTail1.ReplaceAllString(p, "")
	}
	return varTail2.ReplaceAllString(p, "")
}

// ---------- targets ----------

func (j *judge) add(t target) { t.apd = j.stmtAPD; j.targets = append(j.targets, t) }

var devFd = regexp.MustCompile(`^/dev/fd/[0-9][0-9]?$`)
var fdWord = regexp.MustCompile(`^([0-9]+-?|-)$`)

// tilde: `~` is $HOME as the shell has it when the word is expanded — an
// assignment made in this command included.
func (j *judge) tilde(s string) string {
	if s != "~" && !strings.HasPrefix(s, "~/") {
		return s
	}
	if h, ok := j.assigned("HOME"); ok {
		return h + s[1:]
	}
	return s
}

// rcMoved: this command points curl or wget at a start-up file of its own choosing.
func (j *judge) rcMoved() bool {
	names := []string{"HOME", "CURL_HOME", "XDG_CONFIG_HOME", "WGETRC", "SYSTEM_WGETRC"}
	for _, n := range names {
		if _, ok := j.assigned(n); ok {
			return true
		}
		for _, e := range j.envN {
			if e == n {
				return true
			}
		}
	}
	return false
}

func (j *judge) addTarget(raw string, nofollow bool) {
	switch raw {
	case "", "/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty":
		return
	}
	if strings.HasPrefix(raw, "&") || devFd.MatchString(raw) {
		return
	}
	s := j.subst(j.tilde(raw))
	if strings.Contains(raw, "$") && !strings.ContainsAny(raw, " \t\n") && strings.ContainsAny(s, " \t\n") {
		// `d='src/a /etc/x'; touch $d`: unquoted, the value is two arguments. The
		// word no longer says whether it was quoted, so it is judged both ways —
		// as the one name it would be quoted (below), and as each of its words.
		for _, f := range strings.Fields(s) {
			j.addTarget(f, nofollow)
		}
	}
	if unresolved(s) {
		j.add(target{raw: raw, note: "unresolved variable or substitution"})
		return
	}
	if !(strings.HasPrefix(s, "/") || s == "~" || strings.HasPrefix(s, "~/")) && j.cwdUnknown {
		j.add(target{raw: raw, note: "relative to a working directory the guard could not resolve"})
		return
	}
	j.add(target{raw: raw, abs: j.c.canonCached(s, j.cwd, nofollow)})
}

func (j *judge) addUnknown(what string) {
	j.add(target{raw: what, note: "its targets are not visible to the guard — name the files instead"})
}
func (j *judge) addOpaque(raw, what string) {
	if len(raw) > 60 {
		raw = raw[:60]
	}
	j.add(target{raw: raw, note: "opaque shell body: " + what})
}

// ---------- runtime writes ----------

func lineMatch(re *regexp.Regexp, text string) bool {
	for _, l := range strings.Split(text, "\n") {
		if re.MatchString(l) {
			return true
		}
	}
	return false
}

var rtRe = map[string]*regexp.Regexp{
	"python": regexp.MustCompile(`(?i)open[[:space:]]*\([^)]*,[[:space:]]*['"][rwax+b]*[wax]|mode[[:space:]]*=[[:space:]]*['"][rwax+b]*[wax]|\.write\(|write_text\(|write_bytes\(|shutil\.|os\.(rename|replace|remove|unlink|makedirs|mkdir|rmdir|link|symlink|system)|subprocess|\.unlink\(|rmtree\(|\.mkdir\(|\.touch\(|\.rename\(|\.replace\(`),
	"node":   regexp.MustCompile(`(?i)writeFile|appendFile|createWriteStream|mkdirSync|\.mkdir\(|copyFile|renameSync|\.rename\(|unlink|rmSync|\.rm\(|rmdir|truncate|child_process|execSync`),
	"ruby":   regexp.MustCompile(`(?i)File\.(write|open\([^)]*,[[:space:]]*['"][rwax+b]*[wax]|rename|delete|unlink)|FileUtils\.|IO\.write|system\(|` + "`"),
	"php":    regexp.MustCompile(`(?i)file_put_contents|fwrite|fopen\([^)]*,[[:space:]]*['"][rwax+b]*[wax]|rename\(|copy\(|mkdir\(|unlink\(|rmdir\(|exec\(|shell_exec|system\(`),
	"perl":   regexp.MustCompile(`(?i)open[[:space:]]*\([^)]*,[[:space:]]*['"]?[[:space:]]*>|open[[:space:]]+[A-Z_]+[[:space:]]*,[[:space:]]*['"]>|File::Copy|rename\(|unlink|mkdir\(|rmdir\(|system\(|` + "`"),
}

func (j *judge) rtMark(text string) {
	j.rtWrite = true
	j.rtText += text + "\n"
	if isPluginCache(j.cwd) {
		j.rtCwdCache = true
	}
	if j.cwdUnknown {
		j.rtCwdUnk = true
	}
	if !j.c.inScope(j.cwd) {
		j.rtAllScope = false
	}
	if !strings.HasPrefix(j.cwd+"/", j.c.projCanon+"/") {
		j.rtAllProj = false
	}
}

// ---------- nested shells ----------

var ansiRe = regexp.MustCompile(`\\x[0-9a-fA-F]|\\[0-7]{3}|\\u[0-9a-fA-F]|\\U[0-9a-fA-F]`)

func (j *judge) recurse(text string, data bool) {
	if text == "" {
		return
	}
	text = strings.ReplaceAll(text, "\x1e", "\n")
	for k := range j.envN { // what `X=v sh -c …` hands the nested shell
		text = repl(text, j.envN[k], j.envV[k])
	}
	text = j.subst(text)
	if strings.Contains(text, unknownValue) {
		j.addOpaque(text, "variable body") // a value the guard gave up on (read, getopts, unset …)
		return
	}
	t := strings.TrimLeft(text, " ")
	if strings.HasPrefix(t, "$(") || strings.HasPrefix(t, "`") {
		if !data && j.namesFenced() {
			j.addOpaque(text, "substitution output runs")
			return
		}
	} else if strings.HasPrefix(t, "$") {
		j.addOpaque(text, "variable body")
		return
	}
	if ansiRe.MatchString(text) {
		j.addUnknown("shell text with ANSI-C escapes")
		return
	}
	if j.depth >= 3 {
		if j.namesFenced() {
			j.addOpaque(text, "nested shell beyond the depth cap")
		} else {
			j.addUnknown("nested shell (depth > 3)")
		}
		return
	}
	if *j.c.budget <= 0 {
		if j.namesFenced() {
			j.addOpaque(text, "nested shells beyond the budget")
		} else {
			j.addUnknown("nested shells beyond the budget")
		}
		return
	}
	*j.c.budget--
	n := &judge{c: j.c, command: text, depth: j.depth + 1, data: data}
	if n.run(j.cwd).Blocked() {
		r := text
		if len(r) > 60 {
			r = r[:60]
		}
		j.add(target{raw: r, note: "nested shell text writes outside the scope"})
	}
}

// ---------- reading the command (internal/shell) ----------

// snapshot is the state a subshell, a substitution or a pipeline element gets a
// copy of: what it changes does not reach the commands after it.
type snapshot struct {
	cwd     string
	unknown bool
	vn, vv  []string
	dirs    []cwdState
	group   int
}

func (j *judge) Enter(s shell.Scope) {
	j.saved = append(j.saved, snapshot{j.cwd, j.cwdUnknown, append([]string(nil), j.vn...),
		append([]string(nil), j.vv...), append([]cwdState(nil), j.dirStack...), j.group})
	if s == shell.Subshell || s == shell.Substitution {
		j.group++
	}
}

func (j *judge) Leave(shell.Scope) {
	k := len(j.saved) - 1
	sn := j.saved[k]
	j.saved = j.saved[:k]
	j.cwd, j.cwdUnknown, j.vn, j.vv, j.dirStack, j.group = sn.cwd, sn.unknown, sn.vn, sn.vv, sn.dirs, sn.group
}

// QuotedSubst: the substitution runs, its output is data for a command judged
// on its own. One nested reading per working directory, at the end.
func (j *judge) QuotedSubst(text string) {
	for i := range j.nCwd {
		if j.nCwd[i].cwd == j.cwd && j.nCwd[i].unknown == j.cwdUnknown {
			j.nTxt[i] += "\x1e" + text
			return
		}
	}
	j.nCwd = append(j.nCwd, cwdState{j.cwd, j.cwdUnknown})
	j.nTxt = append(j.nTxt, text)
}

// For: the loop variable takes the first item that is NOT in scope, if there is
// one, so a write on it in the body is refused; otherwise the first item.
func (j *judge) For(name string, items []string) {
	w, first := "", ""
	for k, raw := range items {
		if k == 0 {
			first = raw
		}
		body := j.subst(raw)
		if unresolved(body) || !j.c.inScope(j.c.canonCached(body, j.cwd, false)) {
			w = raw
			break
		}
	}
	if w == "" {
		w = first
	}
	j.setvar(name, w)
}

func (j *judge) Command(c shell.Command) { j.process(c) }

// Call: `X=v f` — the prefix is in effect while the body runs, and only then.
func (j *judge) Call(assigns []shell.Assign) {
	var fr []restore
	for _, a := range assigns {
		fr = append(fr, restore{a.Name})
		j.setvar(a.Name, j.valueOf(a))
	}
	j.frames = append(j.frames, fr)
}

func (j *judge) Return() {
	k := len(j.frames) - 1
	fr := j.frames[k]
	j.frames = j.frames[:k]
	for i := len(fr) - 1; i >= 0; i-- {
		// bash restores the old value; a shell in POSIX mode (`sh` on macOS) keeps
		// the prefix. Which one runs is not the guard's to know.
		j.setvar(fr[i].name, unknownValue)
	}
}

type restore struct{ name string }

// Lost: the reader stopped following the shell's state — nothing relative and
// nothing built from a variable can be placed after this point.
func (j *judge) Lost(string) {
	j.lost = true
	j.cwdUnknown = true
	for i := range j.vv {
		j.vv[i] = unknownValue
	}
}

// evalHere reads text that `eval` runs in THIS shell: a cd, an assignment or a
// function defined in it is still in effect for the commands after it.
func (j *judge) evalHere(text string) {
	if text == "" {
		return
	}
	for k := range j.envN {
		text = repl(text, j.envN[k], j.envV[k])
	}
	text = j.subst(text)
	if strings.Contains(text, unknownValue) {
		j.addOpaque(text, "variable body")
		return
	}
	switch t := strings.TrimLeft(text, " "); {
	case strings.HasPrefix(t, "$(") || strings.HasPrefix(t, "`"):
		// the OUTPUT of the substitution is what runs, and that is not visible
		if j.namesFenced() {
			j.addOpaque(text, "substitution output runs")
			return
		}
	case strings.HasPrefix(t, "$"):
		j.addOpaque(text, "variable body")
		return
	}
	if j.evals++; j.evals > 8 {
		j.addUnknown("eval nested deeper than the guard reads")
		j.Lost("")
		return
	}
	data := j.data
	j.data = false
	if err := j.rd.Walk(text, j); err != nil {
		j.addUnknown("eval text the parser could not read")
		if j.namesFenced() {
			j.addOpaque("unreadable eval text", "the parser stopped: "+err.Error())
		}
		j.Lost("")
	}
	j.data = data
}

// stateWords: builtins that change the shell's own state.
var stateWords = map[string]bool{"cd": true, "pushd": true, "popd": true, "eval": true, "export": true, "declare": true,
	"typeset": true, "local": true, "readonly": true, "unset": true, "source": true, ".": true, "set": true, "shopt": true,
	"alias": true, "command": true, "builtin": true, "exec": true}

// programOnly: builtins whose effect is on the shell itself. Behind a wrapper
// that starts a program they are not the builtin.
var programOnly = map[string]bool{"cd": true, "pushd": true, "popd": true, "read": true, "mapfile": true, "readarray": true,
	"printf": true, "getopts": true, "unset": true, "export": true, "local": true, "declare": true, "typeset": true, "readonly": true}

// unknownValue stands for a variable whose value the guard cannot know (read,
// mapfile, an array): a path built from it is unresolved, and so refused.
const unknownValue = "`unknown`"

func (j *judge) assigned(n string) (string, bool) {
	for i := range j.vn {
		if j.vn[i] == n {
			return j.vv[i], true
		}
	}
	return "", false
}

func (j *judge) valueOf(a shell.Assign) string {
	if a.Opaque || j.altered[a.Name] {
		return unknownValue
	}
	v := j.subst(a.Value)
	if a.Append {
		old, ok := j.assigned(a.Name)
		if !ok {
			return unknownValue
		}
		return old + v
	}
	return v
}

func in(s string, l ...string) bool {
	for _, x := range l {
		if s == x {
			return true
		}
	}
	return false
}
func at(a []string, i int) string {
	if i >= 0 && i < len(a) {
		return a[i]
	}
	return ""
}

var nameRe = regexp.MustCompile(`^[A-Za-z0-9_]+$`)
var apdCore = []string{"pipeline-advance", "verify-apd", "pipeline-post-commit", "pipeline-gate"}

// apdTool: is this word one of APD's own tools — the real ones, by where they
// live, not anything whose path merely ends like one.
func (j *judge) apdTool(w, next string) bool {
	// The plugin root written as the environment's own variable, exactly: what it
	// expands to is not this command's doing. An assignment made in the command
	// is substituted below and judged by where it really points.
	for _, v := range []struct{ name, tail string }{{"APD_PLUGIN_ROOT", "/bin/core/"}, {"CLAUDE_PLUGIN_ROOT", "/plugins/apd/bin/core/"}} {
		if _, set := j.assigned(v.name); set {
			continue
		}
		for _, t := range apdCore {
			if w == "$"+v.name+v.tail+t || w == "${"+v.name+"}"+v.tail+t {
				return true
			}
		}
	}
	s := j.subst(w)
	if unresolved(s) {
		return false
	}
	if s == "apd" {
		return next == "pipeline"
	}
	if !strings.Contains(s, "/") {
		return false
	}
	p := j.c.canonCached(s, j.cwd, true)
	if p == j.c.projCanon+"/.claude/bin/apd" || (j.c.apdRoot != "" && p == j.c.apdRoot+"/bin/apd") {
		return next == "pipeline"
	}
	if j.c.apdRoot != "" {
		for _, t := range apdCore {
			if p == j.c.apdRoot+"/bin/core/"+t {
				return true
			}
		}
	}
	return false
}

// altersValue: declare/typeset/local with an attribute under which the stored
// value is not the text assigned — a nameref (-n), a case change (-l, -u), an
// integer (-i), an array (-a, -A) — or with any option the guard does not know.
// -x, -r, -g and -p leave the value as written.
func altersValue(words []string) bool {
	for _, w := range words {
		if len(w) < 2 || (w[0] != '-' && w[0] != '+') || w == "--" {
			continue
		}
		if strings.Trim(w[1:], "xrgp") != "" {
			return true
		}
	}
	return false
}

// alter marks names whose stored value is no longer the text assigned to them.
func (j *judge) alter(names ...string) {
	if j.altered == nil {
		j.altered = map[string]bool{}
	}
	for _, n := range names {
		if nameRe.MatchString(n) && !strings.HasPrefix(n, "-") {
			j.altered[n] = true
			j.setvar(n, unknownValue)
		}
	}
}

func (j *judge) process(c shell.Command) {
	st := c.Words
	n := len(st)
	// `X=v` alone, or under export/local/declare, changes the shell. `X=v cmd`
	// reaches only cmd's environment: this line's own words and redirections
	// were expanded before it, and the next command does not see it.
	persistent := n == 0 || c.Decl != ""
	if c.Decl != "" && altersValue(st) {
		// the attribute stays on the name: every later assignment is altered too
		for _, a := range c.Assigns {
			j.alter(a.Name)
		}
		j.alter(st...)
	}
	j.envN, j.envV = nil, nil
	for _, a := range c.Assigns {
		v := j.valueOf(a)
		if persistent {
			j.setvar(a.Name, v)
		} else {
			j.envN, j.envV = append(j.envN, a.Name), append(j.envV, v)
		}
	}
	j.stmtAPD = false
	writes := func() {
		for _, x := range c.Writes {
			j.addTarget(x, false)
		}
		if c.UnknownRedir {
			j.addUnknown("a redirection the guard does not know")
		}
	}
	if n == 0 || c.Function {
		// a function of this name runs, not the builtin or the tool: its body follows
		writes()
		return
	}
	u := tools.Unwrap(st)
	for _, e := range u.Env { // env X=v cmd
		k := strings.Index(e, "=")
		j.envN, j.envV = append(j.envN, e[:k]), append(j.envV, j.subst(e[k+1:]))
	}
	cmd, a := u.Cmd, u.Args
	if u.Xargs && (tools.Writer(cmd) || cmd == "git") {
		// the command's targets come from stdin: not visible
		j.addUnknown("xargs " + cmd)
	}

	switch {
	case cmd == "$" || strings.HasPrefix(cmd, "$(") || strings.HasPrefix(cmd, "`"):
		// a substitution in command position: its OUTPUT is the command that runs
		if (!j.data || j.group > 0) && j.namesFenced() {
			j.addOpaque(cmd, "substitution in command position")
			writes()
			return
		}
	case strings.HasPrefix(cmd, "$"):
		// a variable in command position: readable only when this command assigned it
		head := j.subst(cmd)
		f := strings.Fields(head)
		if len(f) == 0 && len(a) == 0 {
			writes() // `SUDO=; $SUDO`: nothing runs
			return
		}
		if len(f) > 0 && strings.HasPrefix(f[0], "$") {
			j.addOpaque(cmd, "variable in command position")
			writes()
			return
		}
		// `SUDO=; $SUDO npm install`: an empty value leaves the arguments as the command
		if len(f) == 0 {
			f, a = a[:1], a[1:]
		}
		if defined, maybe := j.rd.Func(f[0]); defined {
			// a function called through the variable: its body runs in THIS shell
			j.evalHere("'" + strings.ReplaceAll(f[0], "'", `'\''`) + "'")
			if !maybe {
				writes()
				return
			}
			// a function that may not have been defined: the name may as well be the
			// program, so the command and its arguments are judged too
		}
		// The shell only SPLITS an expanded value into words — it does not read
		// `x=1`, `>` or `;` in it as syntax. The words of the value, followed by the
		// arguments exactly as the parser made them, are the command: it is judged
		// below like any other, in this shell (`g='cd src'; $g` does change directory;
		// `g='x=src'; $g` runs a program named `x=src` and assigns nothing).
		if len(f) > 1 && stateWords[f[0]] {
			// `c='cd src'; $c` changes directory; `"$c"` is one word, a program named
			// `cd src` that does not exist, and changes nothing. The words here no
			// longer say which was written: the command is judged as if it ran, and
			// after it the state counts as unknown.
			defer j.Lost("a state-changing command behind a variable")
		}
		fed := u.Xargs // `xargs $g`: stdin still supplies part of the arguments
		u = tools.Unwrap(append(f, a...))
		u.Xargs = u.Xargs || fed
		for _, e := range u.Env { // g='env X=v cmd': the variable reaches the command
			k := strings.Index(e, "=")
			j.envN, j.envV = append(j.envN, e[:k]), append(j.envV, j.subst(e[k+1:]))
		}
		cmd, a = u.Cmd, u.Args
		if cmd == "" || strings.HasPrefix(cmd, "$") || strings.HasPrefix(cmd, "`") {
			j.addOpaque(head, "variable in command position")
			writes()
			return
		}
		if u.Xargs && (tools.Writer(cmd) || cmd == "git") {
			j.addUnknown("xargs " + cmd)
		}
	}

	if cmd == "bash" || cmd == "sh" {
		j.stmtAPD = j.apdTool(at(a, 0), at(a, 1))
	} else {
		j.stmtAPD = j.apdTool(cmd, at(a, 0))
	}

	chdir := func(w string) {
		w = j.subst(j.tilde(w))
		if unresolved(w) {
			j.cwdUnknown = true
		} else {
			j.cwd, j.cwdUnknown = j.c.canonCached(w, j.cwd, false), false
		}
	}
	forget := func(names ...string) {
		for _, x := range names {
			if nameRe.MatchString(x) {
				j.setvar(x, unknownValue)
			}
		}
	}
	if u.Program && programOnly[cmd] {
		// `nice cd dir`, `env export X=v`, `sudo read x`: a program of that name in a
		// child process — this shell's directory and variables stay as they were
		writes()
		return
	}
	switch cmd {
	case "cd":
		switch w := at(tools.Positionals(a, `^$`), 0); w {
		case "", "~":
			if _, moved := j.assigned("HOME"); moved {
				chdir("~")
			} else {
				j.cwd, j.cwdUnknown = j.c.home, false
			}
		case "-":
			j.cwdUnknown = true
		default:
			chdir(w)
		}
	case "pushd":
		w := at(tools.Positionals(a, `^$`), 0)
		j.dirStack = append(j.dirStack, cwdState{j.cwd, j.cwdUnknown})
		if w == "" {
			j.cwdUnknown = true // swaps the top two: not modelled
		} else {
			chdir(w)
		}
	case "popd":
		if k := len(j.dirStack); k > 0 {
			j.cwd, j.cwdUnknown = j.dirStack[k-1].cwd, j.dirStack[k-1].unknown
			j.dirStack = j.dirStack[:k-1]
		} else {
			j.cwdUnknown = true
		}
	case "read":
		// the value comes from input the guard does not see
		forget(tools.Positionals(a, `^-[adinNptu]$`)...)
		for k, x := range a {
			if x == "-a" {
				forget(at(a, k+1))
			}
		}
	case "mapfile", "readarray":
		if nf := tools.Positionals(a, `^-[dnOsutCc]$`); len(nf) > 0 {
			forget(nf[len(nf)-1])
		}
	case "printf":
		if at(a, 0) == "-v" {
			forget(at(a, 1))
		}
	case "getopts":
		forget(at(a, 1))
	case "unset":
		forget(tools.Positionals(a, `^$`)...)
	case "export", "local", "declare", "typeset", "readonly":
		// reached through `command` or `builtin`: the assignments still last
		for _, x := range a {
			if k := strings.Index(x, "="); k > 0 && nameRe.MatchString(x[:k]) {
				if altersValue(a) {
					j.alter(x[:k])
				} else if !j.altered[x[:k]] {
					j.setvar(x[:k], j.subst(x[k+1:]))
				}
			}
		}
		if altersValue(a) {
			j.alter(a...)
		}
	case "eval":
		if u.Program {
			// `nice eval …`, `timeout 5 eval …`: a program named eval, not the builtin —
			// nothing it sets reaches this shell; its text is still judged
			j.recurse(strings.Join(a, " "), false)
			break
		}
		// runs in THIS shell
		j.evalHere(strings.Join(a, " "))
	case "bash", "sh", "zsh", "dash", "su":
		// a shell of its own
		if text, ok := tools.ShellText(cmd, a, c.Heredoc); ok {
			j.recurse(text, false)
		}
	case "python", "python2", "python3", "node", "nodejs", "ruby", "php":
		lang := cmd
		if strings.HasPrefix(cmd, "python") {
			lang = "python"
		} else if strings.HasPrefix(cmd, "node") {
			lang = "node"
		}
		text, take := "", false
		for _, x := range a {
			if take {
				text += x + "\n"
				take = false
				continue
			}
			switch {
			case in(x, "-c", "-e", "-r", "--eval", "--print", "-p"):
				take = true
			case strings.HasPrefix(x, "--eval=") || strings.HasPrefix(x, "--print="):
				text += x[strings.Index(x, "=")+1:] + "\n"
			case len(x) > 2 && (strings.HasPrefix(x, "-c") || strings.HasPrefix(x, "-e") || strings.HasPrefix(x, "-r")):
				text += x[2:] + "\n"
			}
		}
		if c.Heredoc != "" {
			// a program on stdin, unless a script file was named
			script := ""
			for _, x := range tools.Positionals(a, `^(-c|-e|-r|--eval|-m|-W|-X|-r|-d)$`) {
				if x != "-" {
					script = x
				}
			}
			if script == "" {
				text += c.Heredoc
			}
		}
		if text != "" && lineMatch(rtRe[lang], text) {
			j.rtMark(text + "\n" + strings.Join(a, " "))
		}
	default:
		if (cmd == "curl" || cmd == "wget") && j.rcMoved() {
			j.addUnknown(cmd + " with its start-up file moved by this command")
		}
		if ts, ok := tools.Writes(cmd, a); ok {
			for _, t := range ts {
				if t.Unknown != "" {
					j.addUnknown(t.Unknown)
				} else {
					j.addTarget(t.Path, t.NoFollow)
				}
			}
		} else if cmd == "perl" {
			text, take := "", false
			for _, x := range a {
				if take {
					text += x + "\n"
					take = false
				} else if x == "-e" || x == "-E" {
					take = true
				}
			}
			text += c.Heredoc
			if text != "" && lineMatch(rtRe["perl"], text) {
				j.rtMark(text + "\n" + strings.Join(a, " "))
			}
		}
	}
	writes()
}

// ---------- stage 0: the substring checks that run before the parser ----------

var plugWrite = []string{"tee ", "sed -i", "sed --in-place", "cp ", "mv ", "dd ", "install ", "mkdir ", "mkdir -p", "touch ", "rm ", "rm -f", "rm -rf", "rmdir "}
var redirPipeRe = regexp.MustCompile(`>[^&].*\.apd/pipeline/|>>.*\.apd/pipeline/`)

type rtPair struct{ a, b *regexp.Regexp }

var stage0rt = []rtPair{
	{regexp.MustCompile(`(^|[;&|] *)node\s+(-e|--eval|--print)\s`), regexp.MustCompile(`(?i)writeFile|writeFileSync|appendFile|appendFileSync|createWriteStream|mkdirSync|copyFile`)},
	{regexp.MustCompile(`(^|[;&|] *)python[3]?\s+(-c)\s`), regexp.MustCompile(`(?i)open\s*\(|\.write\s*\(|Path\s*\(|shutil\.|os\.rename|os\.replace|pathlib`)},
	{regexp.MustCompile(`(^|[;&|] *)ruby\s+(-e)\s`), regexp.MustCompile(`(?i)File\.(write|open|rename)|FileUtils\.(cp|mv|mkdir)`)},
	{regexp.MustCompile(`(^|[;&|] *)php\s+(-r)\s`), regexp.MustCompile(`(?i)file_put_contents|fwrite|fopen|rename|copy|mkdir`)},
	{regexp.MustCompile(`(^|[;&|] *)perl\s+(-e)\s`), regexp.MustCompile(`(?i)open\s*\(|print\s+\$|File::Copy|rename`)},
}

func (j *judge) stage0() bool {
	c := fenceCase.ReplaceAllStringFunc(j.command, strings.ToLower)
	const pp = ".apd/pipeline/"
	if !strings.Contains(c, pp) {
		return false
	}
	for _, t := range []string{"pipeline-advance", "apd pipeline", "verify-apd", "pipeline-post-commit", "pipeline-gate", ".guide-marker"} {
		if strings.Contains(c, t) {
			return false
		}
	}
	for _, wp := range plugWrite {
		if k := strings.Index(c, wp); k >= 0 && strings.Contains(c[k+len(wp):], pp) {
			j.reason = "stage0: write op before the pipeline dir"
			return true
		}
	}
	if lineMatch(redirPipeRe, c) {
		j.reason = "stage0: redirect to the pipeline dir"
		return true
	}
	for _, p := range stage0rt {
		if lineMatch(p.a, c) && lineMatch(p.b, c) {
			j.reason = "stage0: runtime write naming the pipeline dir"
			return true
		}
	}
	return false
}

// ---------- decide ----------

var tokRe = regexp.MustCompile(`[$~./A-Za-z0-9_-][A-Za-z0-9_./~{}$-]*`)
var tokRePO = regexp.MustCompile(`[~./A-Za-z0-9_-][A-Za-z0-9_./~-]*`)
var rtMkdirRe = regexp.MustCompile(`makedirs|mkdir|mkpath|MkdirAll|create_dir|ensureDir|ensure_dir|FileUtils|rename|move|copytree|copy2|copyfile|copy\(|copyFile|cpSync|extract|unpack|install|system\(|subprocess|spawn|exec|popen|shell_exec|passthru|(^|[^A-Za-z])(cp|mv|tar|rsync|unzip|install|ditto) `)
var scanSubs = []struct {
	re *regexp.Regexp
	to string
}{
	{regexp.MustCompilePOSIX(`[Ff][Ii][Ll][Ee]://[A-Za-z0-9.-]*/`), "/"},
	{regexp.MustCompilePOSIX(`</?[A-Za-z][A-Za-z0-9:-]*>`), " "},
	{regexp.MustCompilePOSIX(`(https?|ftps?|ssh|git|s3|gs|wss?|rsync|svn|smb|ldap|data)://[^[:space:]"']*`), " "},
	{regexp.MustCompilePOSIX(`"/(\^[^"]*|[^"]*\\[^"]*|[^"]*\$)/[a-zA-Z]{0,5}"`), " "},
	{regexp.MustCompilePOSIX(`'/(\^[^']*|[^']*\\[^']*|[^']*\$)/[a-zA-Z]{0,5}'`), " "},
	{regexp.MustCompilePOSIX(`"#(\^[^"#]*|[^"#]*\\[^"#]*|[^"#]*\$)#[a-zA-Z]{0,5}"`), " "},
}

// The reasons a command is refused — the same names the audit log has always used.
const (
	PipelineState = "pipeline-state-write"    // a write into .apd/pipeline by anything but APD's own tools
	PluginCache   = "plugin-cache-write"      // a write into an installed plugin
	OpaqueBody    = "opaque-shell-body"       // text handed to a shell that the guard cannot read
	NestedRefusal = "nested-shell-refusal"    // a nested shell's own command was refused
	OutOfScope    = "out-of-scope-bash-write" // a write outside what the caller may write
)

// Verdict is the guard's answer. The zero value allows.
type Verdict struct {
	Code   string // one of the constants above; "" = allowed
	Detail string
}

func (v Verdict) Blocked() bool { return v.Code != "" }

func block(code, detail string) Verdict { return Verdict{code, detail} }

func (j *judge) pathy(s string) bool { return strings.Contains(s, "/") || strings.HasPrefix(s, "~") }

func (j *judge) canonTok(s string) string { return j.c.canonCached(s, j.cwd, false) }

func (j *judge) decide() Verdict {
	if len(j.targets) == 0 && !j.rtWrite {
		return Verdict{}
	}
	namesCache := strings.Contains(j.command, "plugins/cache")
	for _, t := range j.targets {
		if strings.HasPrefix(t.note, "opaque shell body") {
			return block(OpaqueBody, t.note)
		}
		if t.abs == "" {
			if namesCache {
				return block(PluginCache, "plugin cache named, target unresolved: "+t.raw)
			}
			continue
		}
		if isPluginCache(t.abs) {
			return block(PluginCache, "plugin cache: "+t.abs)
		}
		r := j.subst(t.raw)
		if r == "~" {
			r = j.c.home
		} else if strings.HasPrefix(r, "~/") {
			r = j.c.home + "/" + r[2:]
		}
		if isPluginCache(r) {
			return block(PluginCache, "plugin cache by spelling: "+t.raw)
		}
	}
	if j.rtWrite {
		if j.rtCwdCache {
			return block(PluginCache, "writing program run inside the plugin cache")
		}
		for _, p := range tokRe.FindAllString(j.rtText, -1) {
			if strings.HasPrefix(p, "$") {
				if !j.knownVar(varName(p)) {
					p = varTail(p)
					if !strings.Contains(p, "/") {
						continue
					}
				}
			} else if !j.pathy(p) {
				continue
			}
			s := j.subst(p)
			if unresolved(s) {
				if namesCache {
					return block(PluginCache, "plugin cache named, program path unresolved: "+p)
				}
				continue
			}
			if !j.pathy(s) {
				continue
			}
			if isPluginCache(s) || isPluginCache(j.canonTok(s)) {
				return block(PluginCache, "plugin cache named in the program: "+p)
			}
		}
	}

	if j.protectOnly {
		for _, t := range j.targets {
			if strings.HasPrefix(t.note, "nested shell text") {
				return block(NestedRefusal, "nested shell refused: "+t.raw)
			}
		}
		// compared without regard to case: on a case-insensitive volume `.APD/Pipeline`
		// is the same directory, and the resolved path keeps the case it was written in
		pipe := strings.ToLower(j.c.projCanon + "/.apd/pipeline")
		under := func(p string) bool {
			p = strings.ToLower(p)
			return p == pipe || strings.HasPrefix(p+"/", pipe+"/")
		}
		for _, t := range j.targets {
			if j.lost && !t.apd && t.abs == "" {
				// The reader lost track of the shell's state (a brace expansion too
				// large to follow, a function that may not be defined, more calls than
				// are followed). The working directory itself did not change, so a
				// relative write may still land in the pipeline directory: unplaced
				// means refused.
				return block(PipelineState, "a write the guard cannot place after it lost track of the shell's state: "+t.raw)
			}
			if t.apd || t.abs == "" {
				continue
			}
			if t.abs[strings.LastIndex(t.abs, "/")+1:] == ".guide-marker" {
				continue
			}
			if under(t.abs) {
				return block(PipelineState, "pipeline dir: "+t.abs)
			}
		}
		if j.rtWrite {
			for _, p := range tokRePO.FindAllString(j.rtText, -1) {
				if !(j.pathy(p) || strings.HasPrefix(p, ".apd")) {
					continue
				}
				s := j.subst(p)
				if unresolved(s) {
					continue
				}
				if under(j.canonTok(s)) {
					return block(PipelineState, "runtime write to the pipeline dir: "+p)
				}
			}
		}
		return Verdict{}
	}

	noScope := j.c.denyAll && len(j.c.scopeRaw) == 0
	for _, t := range j.targets {
		if strings.HasPrefix(t.note, "opaque shell body") {
			return block(OpaqueBody, t.note)
		}
		if t.note != "" {
			return block(OutOfScope, "unplaceable target: "+t.raw+" ("+t.note+")")
		}
		if hasTraversal(t.abs) {
			return block(OutOfScope, "traversal: "+t.abs)
		}
		if noScope {
			if isScratchpad(t.abs) {
				continue
			}
			return block(OutOfScope, "no writable scope: "+t.raw)
		}
		if !j.c.inScope(t.abs) {
			return block(OutOfScope, "out of scope: "+t.raw+" -> "+t.abs)
		}
	}

	if j.rtWrite {
		mk := lineMatch(rtMkdirRe, j.rtText)
		lines := strings.Split(j.rtText, "\n")
		for k := range lines {
			for _, s := range scanSubs {
				lines[k] = s.re.ReplaceAllString(lines[k], s.to)
			}
		}
		scan := strings.Join(lines, "\n")
		if noScope {
			return block(OutOfScope, "runtime write with no writable scope")
		}
		if j.rtCwdUnk || (!j.rtAllScope && !j.rtAllProj) {
			return block(OutOfScope, "runtime write from a working directory outside the project")
		}
		any := false
		for _, p := range tokRe.FindAllString(scan, -1) {
			tail := false
			if strings.HasPrefix(p, "$") {
				if !j.knownVar(varName(p)) {
					p = varTail(p)
					tail = true
					if !strings.Contains(p, "/") {
						continue
					}
				}
			} else if !j.pathy(p) {
				continue
			}
			s := j.subst(p)
			if unresolved(s) {
				return block(OutOfScope, "runtime path unresolved: "+p)
			}
			if !j.pathy(s) {
				continue
			}
			trav := hasTraversal(s)
			cands := []string{s}
			if strings.HasPrefix(s, "//") && len(s) > 2 && s[2] != '/' {
				c2 := s[2:]
				cands = []string{"/" + c2}
				if k := strings.Index(c2, "/"); k >= 0 {
					cands = append(cands, "/"+c2[k+1:])
				}
			}
			for _, s := range cands {
				if in(s, "/", "//", "///", "/dev/null") {
					continue
				}
				if strings.HasPrefix(s, "/") && !mk && !tail && !trav {
					f := strings.TrimPrefix(strings.TrimPrefix(s, "/"), "/")
					if k := strings.Index(f, "/"); k >= 0 {
						f = f[:k]
					}
					if f != "" && !exists("/"+f) {
						continue
					}
				}
				any = true
				abs := j.canonTok(s)
				if hasTraversal(abs) {
					return block(OutOfScope, "runtime traversal: "+p)
				}
				if !j.c.inScope(abs) {
					return block(OutOfScope, "runtime path out of scope: "+p)
				}
			}
		}
		if !any && !j.rtAllScope {
			return block(OutOfScope, "runtime write with bare names outside the scope")
		}
	}
	return Verdict{}
}

func (j *judge) run(cwdArg string) Verdict {
	j.rtAllScope, j.rtAllProj = true, true
	if j.command == "" {
		return Verdict{}
	}
	if j.stage0() {
		return block(PipelineState, j.reason)
	}
	j.protectOnly = len(j.c.scopeRaw) == 0 && !j.c.denyAll
	base := cwdArg
	if base == "" || !isDir(base) {
		base = j.c.projDir
	}
	wd, _ := os.Getwd()
	j.cwd = j.c.canonAbs(base, wd, false)
	if j.rd == nil {
		j.rd = shell.NewReader()
	}
	if err := j.rd.Walk(j.command, j); err != nil {
		j.addUnknown("command the parser could not read")
		if j.namesFenced() {
			j.addOpaque("unreadable command", "the parser stopped: "+err.Error())
		}
	}
	save := cwdState{j.cwd, j.cwdUnknown}
	for k := range j.nCwd {
		j.cwd, j.cwdUnknown = j.nCwd[k].cwd, j.nCwd[k].unknown
		t := j.nTxt[k]
		switch {
		case strings.HasPrefix(t, "$("):
			j.recurse(t, true)
		case strings.HasPrefix(t, "`"):
			j.recurse(strings.TrimSuffix(strings.TrimPrefix(t, "`"), "`"), false)
		default:
			j.recurse(t, false)
		}
	}
	j.cwd, j.cwdUnknown = save.cwd, save.unknown
	return j.decide()
}

// Options is one call of the guard: the command, where it runs, and what the caller may write.
type Options struct {
	Command, Cwd, ProjectDir string
	Scope                    []string
	DenyAllWrites            bool
	Home, TmpDir, PluginRoot string
	ApdRoot                  string // the plugin's own plugins/apd directory
}

// Judge answers whether the command may run, and if not, why.
func Judge(o Options) Verdict {
	c := &cfg{home: o.Home, tmpdir: o.TmpDir, pluginRoot: o.PluginRoot, projDir: o.ProjectDir,
		scopeRaw: o.Scope, denyAll: o.DenyAllWrites, env: paths.Env{Home: o.Home}}
	if c.tmpdir == "" {
		c.tmpdir = "/tmp"
	}
	b := 40
	c.budget = &b
	c.projCanon = paths.Real(c.projDir)
	if c.projCanon == "" {
		c.projCanon = c.projDir
	}
	if o.ApdRoot != "" {
		if c.apdRoot = paths.Real(o.ApdRoot); c.apdRoot == "" {
			c.apdRoot = o.ApdRoot
		}
	}
	wd, _ := os.Getwd()
	for _, r := range c.scopeRaw {
		r = strings.TrimSuffix(r, "/")
		if strings.HasPrefix(r, "/") {
			c.scopeCanon = append(c.scopeCanon, c.canonAbs(r, wd, false))
		} else {
			c.scopeCanon = append(c.scopeCanon, c.canonAbs(r, c.projCanon, false))
		}
	}
	j := &judge{c: c, command: o.Command}
	return j.run(o.Cwd)
}
