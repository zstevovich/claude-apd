// Package shell reads a Bash command line the way the shell will run it and
// reports what it finds to a Visitor: simple commands with their words and
// output redirections, the places where state stops leaking (subshells,
// substitutions, pipeline elements), loops, and substitutions inside double
// quotes. It knows the shell's grammar and nothing about any guard's rules.
package shell

import (
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

// Assign is one `NAME=value`. Opaque marks a value the reader does not model
// (an array, an indexed element): the name is known, the value is not.
type Assign struct {
	Name, Value    string
	Append, Opaque bool
}

// Command is one simple command.
//
// Words have quotes removed. An expansion stays as its own text (`$HOME`,
// `${x:-y}`), an unquoted command substitution is the single character `$`,
// and a substitution inside double quotes is kept as written. Writes are the
// targets of output redirections attached to the command, in the same form.
type Command struct {
	Decl         string // export, local, declare, readonly, typeset — or ""
	Assigns      []Assign
	Words        []string
	Writes       []string
	UnknownRedir bool
	Heredoc      string
	// Function: the command word names a shell function defined earlier, so the
	// shell runs that function and not a builtin or a program of the same name.
	// Call, the body's commands and Return follow.
	Function bool
}

// Scope is a region whose changes to the working directory and to variables do
// not reach the code after it.
type Scope int

const (
	Subshell     Scope = iota // ( … )
	Substitution              // $( … ), ` … `, <( … ), >( … )
	PipeElement               // each side of a |
	Background                // … &, coproc
	FuncBody                  // a function's body, read where it is defined
)

// Visitor receives the command in execution order.
type Visitor interface {
	Command(Command)
	Enter(Scope)
	Leave(Scope)
	// For is `for NAME in items`; the loop body follows as ordinary commands.
	For(name string, items []string)
	// QuotedSubst is a substitution inside double quotes or an unquoted heredoc
	// body: `$(…)` or a backquoted command, as written.
	QuotedSubst(text string)
	// Call and Return bracket a function body run by a call. assigns are the
	// call's own `X=v f` prefix: in effect for the body, gone after it. Everything
	// else the body changes stays changed — it runs in the caller's shell.
	Call(assigns []Assign)
	Return()
	// Lost: from here on the reader no longer knows what the shell's state is
	// (the working directory, the variables).
	Lost(why string)
}

// Walk parses src and reports it to v. An error means the parser could not read
// the command; nothing after the error point was reported.
func Walk(src string, v Visitor) error { return NewReader().Walk(src, v) }

// Reader carries what one shell remembers between pieces of text it is given:
// the functions defined so far. Text passed to `eval` runs in the same shell, so
// it is read with the same Reader.
type Reader struct {
	funcs map[string]fn
	calls int
}

type fn struct {
	body *syntax.Stmt
	src  string
	// maybe: the definition sits where it may not have run (a branch, a loop
	// body, the right side of && or ||), so the name may still be something else.
	maybe bool
}

func NewReader() *Reader { return &Reader{funcs: map[string]fn{}} }

func (r *Reader) Walk(src string, v Visitor) error {
	f, err := syntax.NewParser(syntax.Variant(syntax.LangBash)).Parse(strings.NewReader(src), "")
	if err != nil {
		return err
	}
	w := &walker{Reader: r, src: src, v: v}
	w.stmts(f.Stmts)
	return nil
}

type walker struct {
	*Reader
	src  string
	v    Visitor
	cond int // depth inside code that may not run
}

// maybeRun reads code that the shell may skip.
func (w *walker) maybeRun(f func()) {
	w.cond++
	f()
	w.cond--
}

func (w *walker) text(n syntax.Node) string { return w.src[n.Pos().Offset():n.End().Offset()] }

// scoped reads f inside a scope: what it defines or changes stays inside.
func (w *walker) scoped(s Scope, f func()) {
	saved := make(map[string]fn, len(w.funcs))
	for k, v := range w.funcs {
		saved[k] = v
	}
	w.v.Enter(s)
	f()
	w.v.Leave(s)
	w.Reader.funcs = saved
}

// unescape removes the backslashes the shell removes: every one outside quotes,
// and inside double quotes only those before `"`, `\`, `$`, a backquote or a newline.
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

// ansiC decodes the body of $'…' with bash's own escapes: \n \t \e \\ \' \" and the
// rest of the single-letter set, \NNN (one to three octal digits), \xHH (one or
// two), \uHHHH, \UHHHHHHHH and \cX. An escape bash does not define keeps its backslash.
func ansiC(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	simple := map[byte]byte{'a': 7, 'b': 8, 'e': 27, 'E': 27, 'f': 12, 'n': 10, 'r': 13, 't': 9, 'v': 11,
		'\\': '\\', '\'': '\'', '"': '"', '?': '?'}
	digits := func(i, max int, base int) (rune, int) {
		var v rune
		n := 0
		for n < max && i+n < len(s) {
			c := s[i+n]
			var d int
			switch {
			case c >= '0' && c <= '9':
				d = int(c - '0')
			case c >= 'a' && c <= 'f':
				d = int(c-'a') + 10
			case c >= 'A' && c <= 'F':
				d = int(c-'A') + 10
			default:
				d = 99
			}
			if d >= base {
				break
			}
			v = v*rune(base) + rune(d)
			n++
		}
		return v, n
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] != '\\' || i+1 >= len(s) {
			b.WriteByte(s[i])
			continue
		}
		c := s[i+1]
		if r, ok := simple[c]; ok {
			b.WriteByte(r)
			i++
			continue
		}
		switch {
		case c >= '0' && c <= '7':
			v, n := digits(i+1, 3, 8)
			b.WriteByte(byte(v))
			i += n
		case c == 'x' || c == 'u' || c == 'U':
			max := map[byte]int{'x': 2, 'u': 4, 'U': 8}[c]
			v, n := digits(i+2, max, 16)
			if n == 0 {
				b.WriteByte('\\')
				continue
			}
			if c == 'x' {
				b.WriteByte(byte(v))
			} else {
				b.WriteRune(v)
			}
			i += 1 + n
		case c == 'c' && i+2 < len(s):
			b.WriteByte(s[i+2] & 0x1f)
			i += 2
		default:
			b.WriteByte('\\')
		}
	}
	return b.String()
}

func (w *walker) parts(ps []syntax.WordPart, quoted bool) string {
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
			b.WriteString(w.parts(x.Parts, true))
		case *syntax.CmdSubst:
			if quoted {
				t := w.text(x)
				w.v.QuotedSubst(t)
				b.WriteString(t)
			} else {
				w.scoped(Substitution, func() { w.stmts(x.Stmts) })
				b.WriteString("$")
			}
		case *syntax.ProcSubst:
			w.scoped(Substitution, func() { w.stmts(x.Stmts) })
			b.WriteString("/dev/fd/63")
		default:
			w.inner(p)
			b.WriteString(w.text(p))
		}
	}
	return b.String()
}

// inner reports the command substitutions nested inside a node the walker does
// not otherwise model (a parameter expansion, arithmetic, a test).
func (w *walker) inner(n syntax.Node) {
	syntax.Walk(n, func(x syntax.Node) bool {
		if cs, ok := x.(*syntax.CmdSubst); ok {
			w.scoped(Substitution, func() { w.stmts(cs.Stmts) })
			return false
		}
		return true
	})
}

func (w *walker) word(x *syntax.Word) string {
	if x == nil {
		return ""
	}
	return w.parts(x.Parts, false)
}

func (w *walker) stmts(l []*syntax.Stmt) {
	for _, s := range l {
		w.stmt(s, "")
	}
}

var stdinReaders = map[string]bool{"bash": true, "sh": true, "zsh": true, "dash": true,
	"python": true, "python3": true, "node": true, "ruby": true, "php": true, "perl": true}

func readsStdin(s *syntax.Stmt) bool {
	c, ok := s.Cmd.(*syntax.CallExpr)
	return ok && len(c.Args) > 0 && stdinReaders[c.Args[0].Lit()]
}

func fdOnly(s string) bool {
	if s == "-" {
		return true
	}
	s = strings.TrimSuffix(s, "-")
	if s == "" {
		return false
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// stmt reports one statement. fed is a heredoc body piped into it from the
// previous pipeline element.
func (w *walker) stmt(s *syntax.Stmt, fed string) {
	switch {
	case s == nil:
	case s.Background || s.Coprocess:
		w.scoped(Background, func() { w.stmt1(s, fed) })
	default:
		w.stmt1(s, fed)
	}
}

func (w *walker) stmt1(s *syntax.Stmt, fed string) {
	c := Command{Heredoc: fed}
	for _, r := range s.Redirs {
		switch r.Op {
		case syntax.RdrOut, syntax.AppOut, syntax.RdrAll, syntax.AppAll, syntax.ClbOut, syntax.RdrInOut:
			// `<> file` opens for reading and writing and creates the file
			c.Writes = append(c.Writes, w.word(r.Word))
		case syntax.DplOut:
			// `>&2` and `>&-` act on a descriptor; `>& file` writes stdout and stderr to the file
			if t := w.word(r.Word); !fdOnly(t) {
				c.Writes = append(c.Writes, t)
			}
		case syntax.Hdoc, syntax.DashHdoc:
			body := w.parts(r.Hdoc.Parts, true)
			if body != "" && !strings.HasSuffix(body, "\n") {
				body += "\n"
			}
			c.Heredoc += body
		case syntax.RdrIn, syntax.DplIn, syntax.WordHdoc:
			w.word(r.Word)
		default:
			w.word(r.Word)
			c.UnknownRedir = true
		}
	}
	// a compound command's own redirections are reported after its body
	tail := func() {
		if len(c.Writes) > 0 || c.UnknownRedir {
			w.v.Command(Command{Writes: c.Writes, UnknownRedir: c.UnknownRedir})
		}
	}
	switch x := s.Cmd.(type) {
	case nil:
		w.v.Command(c)
	case *syntax.CallExpr:
		for _, a := range x.Assigns {
			c.Assigns = append(c.Assigns, w.assign(a))
		}
		for _, a := range x.Args {
			c.Words = append(c.Words, w.word(a))
		}
		// a call runs the body here, in the caller's shell — by the name the shell
		// sees after quote removal ("f", \f and f are the same call)
		var f fn
		called := false
		if len(c.Words) > 0 {
			f, called = w.funcs[c.Words[0]]
		}
		// a name that is only maybe a function is read as both: the command of
		// that name, then the body — and after it the state is not known
		c.Function = called && !f.maybe
		w.v.Command(c)
		switch {
		case called && w.calls >= 16:
			w.v.Lost("more function calls than the reader follows")
		case called:
			w.calls++
			w.v.Call(c.Assigns)
			(&walker{Reader: w.Reader, src: f.src, v: w.v, cond: w.cond}).stmt(f.body, "")
			w.v.Return()
			if f.maybe {
				w.v.Lost("a function that may not have been defined")
			}
		default:
			// unset, also behind `command` / `builtin`
			k := 0
			for k < len(c.Words) && (c.Words[k] == "command" || c.Words[k] == "builtin") {
				k++
			}
			if k+1 < len(c.Words) && c.Words[k] == "unset" {
				w.unset(c.Words[k+1:])
			}
		}
	case *syntax.DeclClause:
		c.Decl = x.Variant.Value
		for _, a := range x.Args {
			if a.Name == nil {
				c.Words = append(c.Words, w.word(a.Value))
			} else if !a.Naked {
				c.Assigns = append(c.Assigns, w.assign(a))
			}
		}
		w.v.Command(c)
	case *syntax.BinaryCmd:
		if x.Op == syntax.Pipe || x.Op == syntax.PipeAll {
			body := ""
			if readsStdin(x.Y) {
				// a heredoc piped into a shell or an interpreter is that program's text
				for _, r := range x.X.Redirs {
					if r.Op == syntax.Hdoc || r.Op == syntax.DashHdoc {
						body += w.parts(r.Hdoc.Parts, true)
					}
				}
			}
			w.scoped(PipeElement, func() { w.stmt(x.X, "") })
			w.scoped(PipeElement, func() { w.stmt(x.Y, body) })
		} else {
			w.stmt(x.X, "")
			w.maybeRun(func() { w.stmt(x.Y, "") }) // the right side of && / || may not run
		}
		tail()
	case *syntax.Subshell:
		w.scoped(Subshell, func() { w.stmts(x.Stmts) })
		tail()
	case *syntax.Block:
		w.stmts(x.Stmts)
		tail()
	case *syntax.IfClause:
		for cl := x; cl != nil; cl = cl.Else {
			if cl == x {
				w.stmts(cl.Cond)
			} else {
				w.maybeRun(func() { w.stmts(cl.Cond) })
			}
			w.maybeRun(func() { w.stmts(cl.Then) })
		}
		tail()
	case *syntax.WhileClause:
		w.stmts(x.Cond)
		w.maybeRun(func() { w.stmts(x.Do) })
		tail()
	case *syntax.ForClause:
		if wi, ok := x.Loop.(*syntax.WordIter); ok && wi.InPos.IsValid() {
			var items []string
			for _, it := range wi.Items {
				items = append(items, w.word(it))
			}
			w.v.For(wi.Name.Value, items)
		} else {
			w.inner(x.Loop)
		}
		w.maybeRun(func() { w.stmts(x.Do) })
		tail()
	case *syntax.CaseClause:
		w.word(x.Word)
		for _, it := range x.Items {
			w.maybeRun(func() { w.stmts(it.Stmts) })
		}
		tail()
	case *syntax.FuncDecl:
		// read once where it is defined (a body is judged called or not); the name
		// exists only afterwards, so the body's own recursion is not followed here
		w.scoped(FuncBody, func() { w.stmt(x.Body, "") })
		w.funcs[x.Name.Value] = fn{x.Body, w.src, w.cond > 0}
	case *syntax.TimeClause:
		w.stmt(x.Stmt, "")
	case *syntax.CoprocClause:
		w.scoped(Background, func() { w.stmt(x.Stmt, "") })
	default:
		// (( … )), [[ … ]], let: no words to report, but a substitution inside still runs
		w.inner(s.Cmd)
		tail()
	}
}

// unset: `unset -f NAME` removes a function. Plain `unset NAME` removes the
// variable if there is one and the function only otherwise — which of the two
// the reader cannot tell, so a function of that name leaves the state unknown.
func (w *walker) unset(args []string) {
	fOnly, vOnly := false, false
	for _, x := range args {
		switch {
		case x == "-f":
			fOnly = true
		case x == "-v" || x == "-n":
			vOnly = true
		case strings.HasPrefix(x, "-"):
		default:
			f, ok := w.funcs[x]
			if !ok || vOnly {
				continue
			}
			if fOnly && w.cond > 0 {
				// an unset that may not run: the function may still be there
				f.maybe = true
				w.funcs[x] = f
				continue
			}
			if !fOnly {
				w.v.Lost("unset of a name that is a function")
			}
			delete(w.funcs, x) // not followed any more: a body replayed after Lost would claim to know the state again
		}
	}
}

func (w *walker) assign(a *syntax.Assign) Assign {
	out := Assign{Name: a.Name.Value, Append: a.Append}
	if a.Index != nil || a.Array != nil {
		out.Opaque = true
		w.inner(a)
		return out
	}
	out.Value = w.word(a.Value)
	return out
}
