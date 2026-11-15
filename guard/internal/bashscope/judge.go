// Package bashscope judges a Bash command against a write scope: which files it
// would write, and whether the caller may write there. Ported from
// plugins/apd/bin/core/guard-bash-scope; the command is read by a shell parser.
package bashscope

import (
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/zstevovich/claude-apd/guard/internal/paths"
	"mvdan.cc/sh/v3/syntax"
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
}

type cwdState struct {
	cwd     string
	unknown bool
}

type judge struct {
	c           *cfg
	command     string
	src         string
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
	reason      string
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

var pipeMentionRe = regexp.MustCompile(`\.apd/pipeline(/|[^A-Za-z0-9_./-]|$)`)

func (j *judge) namesFenced() bool {
	return strings.Contains(j.command, "plugins/cache") || pipeMentionRe.MatchString(j.command)
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

func (j *judge) addTarget(raw string, nofollow bool) {
	switch raw {
	case "", "/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty":
		return
	}
	if strings.HasPrefix(raw, "&") || devFd.MatchString(raw) {
		return
	}
	if strings.Contains(raw, `\`) {
		j.add(target{raw: raw, note: "a backslash escape in a path is not decoded"})
		return
	}
	s := j.subst(raw)
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
	text = j.subst(text)
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
	if rc, _ := n.run(j.cwd); rc == 2 {
		r := text
		if len(r) > 60 {
			r = r[:60]
		}
		j.add(target{raw: r, note: "nested shell text writes outside the scope"})
	}
}

// ---------- words ----------

func (j *judge) node(n syntax.Node) string {
	return j.src[n.Pos().Offset():n.End().Offset()]
}

func unescape(s string, dq bool) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+1 < len(s) {
			n := s[i+1]
			if n == '\n' {
				i++
				continue
			}
			if !dq || n == '"' || n == '\\' || n == '$' || n == '`' {
				b.WriteByte(n)
				i++
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

func ansiC(s string) string {
	// $'…' decoded: Go's own escape rules cover \xHH, \NNN, \uHHHH, \n, \t, \\
	if v, err := strconv.Unquote(`"` + strings.ReplaceAll(strings.ReplaceAll(s, `\'`, `'`), `"`, `\"`) + `"`); err == nil {
		return v
	}
	return s
}

func (j *judge) inline(stmts []*syntax.Stmt) {
	save := cwdState{j.cwd, j.cwdUnknown}
	j.group++
	j.stmts(stmts)
	j.group--
	j.cwd, j.cwdUnknown = save.cwd, save.unknown
}

func (j *judge) queueNested(text string) {
	for i := range j.nCwd {
		if j.nCwd[i].cwd == j.cwd && j.nCwd[i].unknown == j.cwdUnknown {
			j.nTxt[i] += "\x1e" + text
			return
		}
	}
	j.nCwd = append(j.nCwd, cwdState{j.cwd, j.cwdUnknown})
	j.nTxt = append(j.nTxt, text)
}

func (j *judge) parts(ps []syntax.WordPart, quoted bool) string {
	var b strings.Builder
	for _, p := range ps {
		switch x := p.(type) {
		case *syntax.Lit:
			b.WriteString(unescape(x.Value, quoted))
		case *syntax.SglQuoted:
			if x.Dollar {
				b.WriteString(ansiC(x.Value))
			} else {
				b.WriteString(x.Value)
			}
		case *syntax.DblQuoted:
			b.WriteString(j.parts(x.Parts, true))
		case *syntax.CmdSubst:
			if quoted {
				t := j.node(x)
				j.queueNested(t)
				b.WriteString(t)
			} else {
				j.inline(x.Stmts)
				b.WriteString("$")
			}
		case *syntax.ProcSubst:
			j.inline(x.Stmts)
			b.WriteString("/dev/fd/63")
		default:
			syntax.Walk(p, func(n syntax.Node) bool {
				if cs, ok := n.(*syntax.CmdSubst); ok {
					j.inline(cs.Stmts)
					return false
				}
				return true
			})
			b.WriteString(j.node(p))
		}
	}
	return b.String()
}

func (j *judge) word(w *syntax.Word) string {
	if w == nil {
		return ""
	}
	return j.parts(w.Parts, false)
}

func (j *judge) assign(a *syntax.Assign) string {
	if a.Name == nil {
		return j.word(a.Value)
	}
	if a.Naked {
		return a.Name.Value
	}
	if a.Append || a.Index != nil || a.Array != nil {
		return j.node(a)
	}
	return a.Name.Value + "=" + j.word(a.Value)
}

// ---------- statements ----------

func (j *judge) stmts(l []*syntax.Stmt) {
	for _, s := range l {
		j.stmt(s, "")
	}
}

func isStdinReader(s *syntax.Stmt) bool {
	c, ok := s.Cmd.(*syntax.CallExpr)
	if !ok || len(c.Args) == 0 {
		return false
	}
	switch c.Args[0].Lit() {
	case "bash", "sh", "zsh", "dash", "python", "python3", "node", "ruby", "php", "perl":
		return true
	}
	return false
}

func (j *judge) stmt(s *syntax.Stmt, fedBody string) {
	if s == nil {
		return
	}
	var rt []string
	hb := fedBody
	for _, r := range s.Redirs {
		switch r.Op {
		case syntax.RdrOut, syntax.AppOut, syntax.RdrAll, syntax.AppAll, syntax.ClbOut:
			rt = append(rt, j.word(r.Word))
		case syntax.Hdoc, syntax.DashHdoc:
			body := j.parts(r.Hdoc.Parts, true)
			if body != "" && !strings.HasSuffix(body, "\n") {
				body += "\n"
			}
			hb += body
		case syntax.RdrInOut:
			// `<> file` opens for reading AND writing, and creates the file
			rt = append(rt, j.word(r.Word))
		case syntax.DplOut:
			// `>&2`, `>&-` duplicate or close a descriptor; `>& file` writes stdout and stderr to the file
			if w := j.word(r.Word); !fdWord.MatchString(w) {
				rt = append(rt, w)
			}
		case syntax.RdrIn, syntax.DplIn, syntax.WordHdoc:
			j.word(r.Word)
		default:
			j.word(r.Word)
			j.addUnknown("a redirection the guard does not know")
		}
	}
	switch c := s.Cmd.(type) {
	case nil:
		j.process(nil, rt, hb)
	case *syntax.CallExpr:
		var st []string
		for _, a := range c.Assigns {
			st = append(st, j.assign(a))
		}
		for _, a := range c.Args {
			st = append(st, j.word(a))
		}
		j.process(st, rt, hb)
	case *syntax.DeclClause:
		st := []string{c.Variant.Value}
		for _, a := range c.Args {
			st = append(st, j.assign(a))
		}
		j.process(st, rt, hb)
	case *syntax.BinaryCmd:
		if (c.Op == syntax.Pipe || c.Op == syntax.PipeAll) && isStdinReader(c.Y) {
			// a heredoc piped into a shell or interpreter is that program's text
			body := ""
			for _, r := range c.X.Redirs {
				if r.Op == syntax.Hdoc || r.Op == syntax.DashHdoc {
					body += j.parts(r.Hdoc.Parts, true)
				}
			}
			j.stmt(c.X, "")
			j.stmt(c.Y, body)
		} else {
			j.stmt(c.X, "")
			j.stmt(c.Y, "")
		}
		j.process(nil, rt, "")
	case *syntax.Subshell:
		j.inline(c.Stmts)
		j.process(nil, rt, "")
	case *syntax.Block:
		j.stmts(c.Stmts)
		j.process(nil, rt, "")
	case *syntax.IfClause:
		for cl := c; cl != nil; cl = cl.Else {
			j.stmts(cl.Cond)
			j.stmts(cl.Then)
		}
		j.process(nil, rt, "")
	case *syntax.WhileClause:
		j.stmts(c.Cond)
		j.stmts(c.Do)
		j.process(nil, rt, "")
	case *syntax.ForClause:
		if wi, ok := c.Loop.(*syntax.WordIter); ok && wi.InPos.IsValid() {
			w, last, first := "", "", true
			for _, it := range wi.Items {
				raw := j.word(it)
				if first {
					last, first = raw, false
				}
				body := j.subst(raw)
				if unresolved(body) {
					w = raw
					break
				}
				if !j.c.inScope(j.c.canonCached(body, j.cwd, false)) {
					w = raw
					break
				}
			}
			if w == "" {
				w = last
			}
			j.setvar(wi.Name.Value, w)
		}
		j.stmts(c.Do)
		j.process(nil, rt, "")
	case *syntax.CaseClause:
		j.word(c.Word)
		for _, it := range c.Items {
			j.stmts(it.Stmts)
		}
		j.process(nil, rt, "")
	case *syntax.FuncDecl:
		j.stmt(c.Body, "")
	case *syntax.TimeClause:
		j.stmt(c.Stmt, "")
	case *syntax.CoprocClause:
		j.stmt(c.Stmt, "")
	default:
		// (( … )), [[ … ]], let: no words to judge, but a substitution inside still runs
		syntax.Walk(s.Cmd, func(n syntax.Node) bool {
			if cs, ok := n.(*syntax.CmdSubst); ok {
				j.inline(cs.Stmts)
				return false
			}
			return true
		})
		j.process(nil, rt, "")
	}
}

func positionals(a []string, vflags string) []string {
	re := regexp.MustCompile(vflags)
	var nf []string
	flagsDone, skip := false, false
	for _, x := range a {
		if skip {
			skip = false
			continue
		}
		if !flagsDone {
			if x == "--" {
				flagsDone = true
				continue
			}
			if len(x) >= 2 && x[0] == '-' {
				if re.MatchString(x) {
					skip = true
				}
				continue
			}
		}
		nf = append(nf, x)
	}
	return nf
}

func apdToolWord(w, next string) bool {
	for _, t := range []string{"pipeline-advance", "verify-apd", "pipeline-post-commit", "pipeline-gate"} {
		if strings.HasSuffix(w, "/plugins/apd/bin/core/"+t) {
			return true
		}
		if strings.Contains(w, "APD_PLUGIN_ROOT") && strings.HasSuffix(w, "/bin/core/"+t) {
			return true
		}
	}
	if w == "apd" || w == ".claude/bin/apd" || strings.HasSuffix(w, "/.claude/bin/apd") || strings.HasSuffix(w, "/plugins/apd/bin/apd") {
		return next == "pipeline"
	}
	return false
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
var writers = []string{"cp", "mv", "rm", "rmdir", "mkdir", "touch", "tee", "sed", "perl", "install", "dd", "ln", "truncate", "chmod", "chown", "rsync"}

func (j *judge) process(st, rt []string, hb string) {
	n := len(st)
	if n == 0 && len(rt) == 0 {
		return
	}
	i := 0
	skipFlags := func(valued ...string) {
		i++
		for i < n {
			if in(st[i], valued...) {
				i += 2
			} else if strings.HasPrefix(st[i], "-") {
				i++
			} else {
				break
			}
		}
	}
loop:
	for i < n {
		w := st[i]
		if k := strings.Index(w, "="); k >= 0 {
			name := w[:k]
			if !nameRe.MatchString(name) {
				break
			}
			j.setvar(name, j.subst(w[k+1:]))
			i++
			continue
		}
		switch w {
		case "!", "function", "coproc", "time", "export", "local", "declare", "typeset", "readonly", "command", "builtin", "exec", "nohup", "caffeinate",
			"if", "then", "else", "elif", "fi", "while", "until", "do", "done", "in", "case", "esac", "{", "}":
			i++
		case "sudo", "doas":
			skipFlags("-u", "-g", "-p", "-h", "-C", "-D", "-r", "-t", "-U")
		case "nice", "ionice":
			skipFlags("-n", "-c", "-p")
		case "timeout":
			i++
			for i < n {
				if in(st[i], "-k", "-s", "--kill-after", "--signal") {
					i += 2
				} else if strings.HasPrefix(st[i], "-") {
					i++
				} else {
					i++
					break
				}
			}
		case "env":
			skipFlags("-u", "-C", "-S", "--unset", "--chdir")
		case "xargs":
			skipFlags("-I", "-n", "-P", "-L", "-s", "-d", "-E", "-a")
			if in(at(st, i), append(writers, "git")...) {
				j.addUnknown("xargs " + st[i])
			}
		default:
			break loop
		}
	}
	cmd := at(st, i)
	var a []string
	if i+1 < n {
		a = st[i+1:]
	}
	j.stmtAPD = false

	switch {
	case cmd == "$" || strings.HasPrefix(cmd, "$(") || strings.HasPrefix(cmd, "`"):
		if (!j.data || j.group > 0) && j.namesFenced() {
			j.addOpaque(cmd, "substitution in command position")
			return
		}
	case strings.Contains(cmd, `\`):
		j.addOpaque(cmd, "undecoded escape in the command word")
		return
	case strings.HasPrefix(cmd, "$"):
		text := cmd
		if len(a) > 0 {
			text += " " + strings.Join(a, " ")
		}
		text = j.subst(text)
		if strings.HasPrefix(strings.TrimLeft(text, " "), "$") {
			j.addOpaque(cmd, "variable in command position")
			return
		}
		j.recurse(text, false)
		return
	}

	if cmd == "bash" || cmd == "sh" {
		j.stmtAPD = apdToolWord(at(a, 0), at(a, 1))
	} else {
		j.stmtAPD = apdToolWord(cmd, at(a, 0))
	}

	tgt := func(x string) { j.addTarget(x, false) }
	switch cmd {
	case "cd":
		nf := positionals(a, `^$`)
		w := at(nf, 0)
		switch w {
		case "", "~":
			j.cwd, j.cwdUnknown = j.c.home, false
		case "-":
			j.cwdUnknown = true
		default:
			w = j.subst(w)
			if unresolved(w) {
				j.cwdUnknown = true
			} else {
				j.cwd, j.cwdUnknown = j.c.canonCached(w, j.cwd, false), false
			}
		}
	case "pushd":
		nf := positionals(a, `^$`)
		w := at(nf, 0)
		j.dirStack = append(j.dirStack, cwdState{j.cwd, j.cwdUnknown})
		if w == "" {
			j.cwdUnknown = true
		} else {
			w = j.subst(w)
			if unresolved(w) {
				j.cwdUnknown = true
			} else {
				j.cwd, j.cwdUnknown = j.c.canonCached(w, j.cwd, false), false
			}
		}
	case "popd":
		if k := len(j.dirStack); k > 0 {
			j.cwd, j.cwdUnknown = j.dirStack[k-1].cwd, j.dirStack[k-1].unknown
			j.dirStack = j.dirStack[:k-1]
		} else {
			j.cwdUnknown = true
		}
	case "cp", "install":
		w := ""
		for k, x := range a {
			if x == "-t" || x == "--target-directory" {
				w = at(a, k+1)
			} else if strings.HasPrefix(x, "--target-directory=") {
				w = strings.TrimPrefix(x, "--target-directory=")
			}
		}
		if w != "" {
			tgt(w)
		} else if nf := positionals(a, `^(-t|--target-directory|-m|-o|-g|--mode|--owner|--group)$`); len(nf) > 0 {
			tgt(nf[len(nf)-1])
		}
	case "mv":
		for _, x := range positionals(a, `^(-t|--target-directory)$`) {
			tgt(x)
		}
		for k, x := range a {
			if x == "-t" || x == "--target-directory" {
				tgt(at(a, k+1))
			} else if strings.HasPrefix(x, "--target-directory=") {
				tgt(strings.TrimPrefix(x, "--target-directory="))
			}
		}
	case "mkdir":
		for _, x := range positionals(a, `^(-m|--mode)$`) {
			tgt(x)
		}
	case "touch":
		for _, x := range positionals(a, `^(-t|-r|-d|--date|--reference)$`) {
			tgt(x)
		}
	case "rm", "rmdir", "tee", "unlink", "chmod", "chown", "chgrp", "truncate", "ln", "rsync", "shred":
		var nf []string
		switch cmd {
		case "chmod", "chown", "chgrp":
			nf = positionals(a, `^(--reference)$`)
			if len(nf) > 0 {
				nf = nf[1:]
			}
		case "truncate":
			nf = positionals(a, `^(-s|-r|--size|--reference)$`)
		case "rsync":
			nf = positionals(a, `^(-e|--rsh|--exclude|--include|--filter|--files-from|--log-file)$`)
			if len(nf) > 0 {
				nf = nf[len(nf)-1:]
			}
		case "ln":
			nf = positionals(a, `^(-t|--target-directory|-S|--suffix)$`)
			if len(nf) >= 2 {
				nf = nf[len(nf)-1:]
			} else if len(nf) == 1 {
				nf = []string{nf[0][strings.LastIndex(nf[0], "/")+1:]}
			}
		default:
			nf = positionals(a, `^$`)
		}
		nofollow := in(cmd, "rm", "rmdir", "unlink")
		for _, x := range nf {
			j.addTarget(x, nofollow)
		}
	case "dd":
		for _, x := range a {
			if strings.HasPrefix(x, "of=") {
				tgt(x[3:])
			}
		}
	case "curl", "wget":
		hasO := false
		for k, x := range a {
			switch {
			case in(x, "-o", "--output", "-O", "--output-document"):
				tgt(at(a, k+1))
			case strings.HasPrefix(x, "--output=") || strings.HasPrefix(x, "--output-document="):
				tgt(x[strings.Index(x, "=")+1:])
			case strings.HasPrefix(x, "-o"):
				if cmd == "curl" {
					tgt(x[2:])
				}
			case strings.HasPrefix(x, "-O"):
				if cmd == "wget" {
					tgt(x[2:])
				}
			}
			if strings.HasPrefix(x, "-O") || strings.HasPrefix(x, "--output-document") {
				hasO = true
			}
		}
		if cmd == "wget" && !hasO {
			tgt("./")
		}
	case "sort":
		for k, x := range a {
			switch {
			case x == "-o" || x == "--output":
				tgt(at(a, k+1))
			case strings.HasPrefix(x, "--output="):
				tgt(x[9:])
			case strings.HasPrefix(x, "-o") && len(x) > 2:
				tgt(x[2:])
			}
		}
	case "tar", "unzip":
		w := ""
		for k, x := range a {
			if in(x, "-C", "--directory", "-d") {
				w = at(a, k+1)
			} else if strings.HasPrefix(x, "--directory=") {
				w = x[12:]
			}
		}
		body := cmd == "unzip"
		if cmd == "tar" {
			for _, x := range a {
				if x == "--extract" || (strings.HasPrefix(x, "-") && strings.Contains(x[1:], "x")) {
					body = true
				} else if len(x) >= 2 && isLetter(x[0]) && strings.Contains(x[1:], "x") {
					body = true
				}
			}
		}
		if body {
			if w == "" {
				w = "./"
			}
			tgt(w)
		}
	case "sed":
		inplace, hasExpr := false, false
		for _, x := range a {
			switch {
			case strings.HasPrefix(x, "--in-place"):
				inplace = true
			case in(x, "-e", "--expression", "-f", "--file"):
				hasExpr = true
			case len(x) > 2 && (strings.HasPrefix(x, "-e") || strings.HasPrefix(x, "-f")):
				hasExpr = true
			case len(x) >= 2 && x[0] == '-' && isLetter(x[1]):
				if strings.Contains(x, "i") {
					inplace = true
				}
			}
		}
		if inplace {
			seenPat, expect := false, false
			for _, x := range a {
				if expect {
					expect = false
					continue
				}
				if x == "" {
					continue
				}
				if in(x, "-e", "--expression", "-f", "--file") {
					expect = true
					continue
				}
				if strings.HasPrefix(x, "-") {
					continue
				}
				if !hasExpr && !seenPat {
					seenPat = true
					continue
				}
				tgt(x)
			}
		}
	case "perl":
		inplace := false
		for _, x := range a {
			if strings.HasPrefix(x, "-i") || (len(x) >= 2 && x[0] == '-' && isAlnum(x[1]) && strings.Contains(x[2:], "i")) {
				if x != "-e" && x != "-E" {
					inplace = true
				}
			}
		}
		if inplace {
			expect := false
			for _, x := range a {
				if expect {
					expect = false
					continue
				}
				if in(x, "-e", "-E", "-M", "-m") {
					expect = true
					continue
				}
				if strings.HasPrefix(x, "-") {
					continue
				}
				tgt(x)
			}
		} else {
			text, expect := "", false
			for _, x := range a {
				if expect {
					text += x + "\n"
					expect = false
					continue
				}
				if x == "-e" || x == "-E" {
					expect = true
				}
			}
			text += hb
			if text != "" && lineMatch(rtRe["perl"], text) {
				j.rtMark(text + "\n" + strings.Join(a, " "))
			}
		}
	case "git":
		w := at(a, 0)
		switch w {
		case "rm", "mv", "restore", "clean":
			nf := positionals(a[1:], `^(--source|--pathspec-from-file)$`)
			for _, x := range nf {
				tgt(x)
			}
			if w == "clean" && len(nf) == 0 {
				tgt("./")
			}
		case "checkout":
			body := false
			for _, x := range a[1:] {
				if body {
					tgt(x)
				} else if x == "--" {
					body = true
				}
			}
		}
	case "eval":
		j.recurse(strings.Join(a, " "), false)
	case "bash", "sh", "zsh", "dash", "su":
		text, w := "", false
		for _, x := range a {
			if w {
				text = x
				break
			}
			if x == "-c" {
				w = true
			} else if strings.HasPrefix(x, "-c") {
				text = x[2:]
				break
			}
		}
		if text == "" {
			text = hb
		}
		if text != "" {
			j.recurse(text, false)
		}
	case "python", "python2", "python3", "node", "nodejs", "ruby", "php":
		lang := cmd
		if strings.HasPrefix(cmd, "python") {
			lang = "python"
		} else if strings.HasPrefix(cmd, "node") {
			lang = "node"
		}
		text, w := "", false
		for _, x := range a {
			if w {
				text += x + "\n"
				w = false
				continue
			}
			switch {
			case in(x, "-c", "-e", "-r", "--eval", "--print", "-p"):
				w = true
			case strings.HasPrefix(x, "--eval=") || strings.HasPrefix(x, "--print="):
				text += x[strings.Index(x, "=")+1:] + "\n"
			case len(x) > 2 && (strings.HasPrefix(x, "-c") || strings.HasPrefix(x, "-e") || strings.HasPrefix(x, "-r")):
				text += x[2:] + "\n"
			}
		}
		if hb != "" {
			last := ""
			for _, x := range positionals(a, `^(-c|-e|-r|--eval|-m|-W|-X|-r|-d)$`) {
				if x != "-" {
					last = x
				}
			}
			if last == "" {
				text += hb
			}
		}
		if text != "" && lineMatch(rtRe[lang], text) {
			j.rtMark(text + "\n" + strings.Join(a, " "))
		}
	case "find":
		body := false
		for _, x := range a {
			if x == "-delete" {
				body = true
			} else if in(x, "-exec", "-execdir", "-ok", "-okdir") {
				last := x
				for k := len(a) - 1; k >= 0; k-- {
					if a[k] == x {
						if k+1 < len(a) {
							last = a[k+1]
						}
						break
					}
				}
				if in(last, append(writers, "sh", "bash")...) {
					body = true
				}
			}
		}
		if body {
			var nf []string
			for _, x := range a {
				if strings.HasPrefix(x, "-") || x == "(" || x == "!" {
					break
				}
				nf = append(nf, x)
			}
			if len(nf) == 0 {
				nf = []string{"./"}
			}
			for _, x := range nf {
				tgt(x)
			}
		}
	}
	for _, x := range rt {
		tgt(x)
	}
}

func isLetter(c byte) bool { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') }
func isAlnum(c byte) bool  { return isLetter(c) || (c >= '0' && c <= '9') }

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
	c := j.command
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

func (j *judge) block(r string) (int, string) { return 2, r }

func (j *judge) pathy(s string) bool { return strings.Contains(s, "/") || strings.HasPrefix(s, "~") }

func (j *judge) canonTok(s string) string { return j.c.canonCached(s, j.cwd, false) }

func (j *judge) decide() (int, string) {
	if len(j.targets) == 0 && !j.rtWrite {
		return 0, ""
	}
	namesCache := strings.Contains(j.command, "plugins/cache")
	for _, t := range j.targets {
		if strings.HasPrefix(t.note, "opaque shell body") {
			return j.block(t.note)
		}
		if t.abs == "" {
			if namesCache {
				return j.block("plugin cache named, target unresolved: " + t.raw)
			}
			continue
		}
		if isPluginCache(t.abs) {
			return j.block("plugin cache: " + t.abs)
		}
		r := j.subst(t.raw)
		if r == "~" {
			r = j.c.home
		} else if strings.HasPrefix(r, "~/") {
			r = j.c.home + "/" + r[2:]
		}
		if isPluginCache(r) {
			return j.block("plugin cache by spelling: " + t.raw)
		}
	}
	if j.rtWrite {
		if j.rtCwdCache {
			return j.block("writing program run inside the plugin cache")
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
					return j.block("plugin cache named, program path unresolved: " + p)
				}
				continue
			}
			if !j.pathy(s) {
				continue
			}
			if isPluginCache(s) || isPluginCache(j.canonTok(s)) {
				return j.block("plugin cache named in the program: " + p)
			}
		}
	}

	if j.protectOnly {
		for _, t := range j.targets {
			if strings.HasPrefix(t.note, "nested shell text") {
				return j.block("nested shell refused: " + t.raw)
			}
		}
		pipe := j.c.projCanon + "/.apd/pipeline"
		under := func(p string) bool { return p == pipe || strings.HasPrefix(p+"/", pipe+"/") }
		for _, t := range j.targets {
			if t.apd || t.abs == "" {
				continue
			}
			if t.abs[strings.LastIndex(t.abs, "/")+1:] == ".guide-marker" {
				continue
			}
			if under(t.abs) {
				return j.block("pipeline dir: " + t.abs)
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
					return j.block("runtime write to the pipeline dir: " + p)
				}
			}
		}
		return 0, ""
	}

	noScope := j.c.denyAll && len(j.c.scopeRaw) == 0
	for _, t := range j.targets {
		if strings.HasPrefix(t.note, "opaque shell body") {
			return j.block(t.note)
		}
		if t.note != "" {
			return j.block("unplaceable target: " + t.raw + " (" + t.note + ")")
		}
		if hasTraversal(t.abs) {
			return j.block("traversal: " + t.abs)
		}
		if noScope {
			if isScratchpad(t.abs) {
				continue
			}
			return j.block("no writable scope: " + t.raw)
		}
		if !j.c.inScope(t.abs) {
			return j.block("out of scope: " + t.raw + " -> " + t.abs)
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
			return j.block("runtime write with no writable scope")
		}
		if j.rtCwdUnk || (!j.rtAllScope && !j.rtAllProj) {
			return j.block("runtime write from a working directory outside the project")
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
				return j.block("runtime path unresolved: " + p)
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
					return j.block("runtime traversal: " + p)
				}
				if !j.c.inScope(abs) {
					return j.block("runtime path out of scope: " + p)
				}
			}
		}
		if !any && !j.rtAllScope {
			return j.block("runtime write with bare names outside the scope")
		}
	}
	return 0, ""
}

func (j *judge) run(cwdArg string) (int, string) {
	j.src = j.command
	j.rtAllScope, j.rtAllProj = true, true
	if j.command == "" {
		return 0, ""
	}
	if j.stage0() {
		return 2, j.reason
	}
	j.protectOnly = len(j.c.scopeRaw) == 0 && !j.c.denyAll
	base := cwdArg
	if base == "" || !isDir(base) {
		base = j.c.projDir
	}
	wd, _ := os.Getwd()
	j.cwd = j.c.canonAbs(base, wd, false)
	p := syntax.NewParser(syntax.Variant(syntax.LangBash))
	f, err := p.Parse(strings.NewReader(j.command), "")
	if err != nil {
		j.addUnknown("command the parser could not read")
		if j.namesFenced() {
			j.addOpaque("unreadable command", "the parser stopped: "+err.Error())
		}
	} else {
		j.stmts(f.Stmts)
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
}

// Judge returns 0 (allow) or 2 (block) and, for a block, a one-line reason.
func Judge(o Options) (int, string) {
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
