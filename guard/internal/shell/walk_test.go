package shell

import (
	"fmt"
	"strings"
	"testing"
)

// trace records what Walk reports, one compact line per event.
type trace struct{ out []string }

func (t *trace) Command(c Command) {
	s := "cmd"
	if c.Decl != "" {
		s += " decl=" + c.Decl
	}
	for _, a := range c.Assigns {
		op := "="
		if a.Append {
			op = "+="
		}
		if a.Opaque {
			op = "=?"
		}
		s += " " + a.Name + op + a.Value
	}
	if len(c.Words) > 0 {
		s += " [" + strings.Join(c.Words, "|") + "]"
	}
	if len(c.Writes) > 0 {
		s += " >" + strings.Join(c.Writes, ",")
	}
	if c.Heredoc != "" {
		s += fmt.Sprintf(" heredoc=%q", c.Heredoc)
	}
	if c.UnknownRedir {
		s += " ?redir"
	}
	t.out = append(t.out, s)
}
func (t *trace) Enter(s Scope) { t.out = append(t.out, fmt.Sprintf("enter %d", s)) }
func (t *trace) Leave(s Scope) { t.out = append(t.out, "leave") }
func (t *trace) For(n string, it []string) {
	t.out = append(t.out, "for "+n+" in "+strings.Join(it, "|"))
}
func (t *trace) QuotedSubst(x string) { t.out = append(t.out, "quoted "+x) }
func (t *trace) Lost(why string)      { t.out = append(t.out, "lost") }
func (t *trace) Call([]Assign)        { t.out = append(t.out, "call") }
func (t *trace) Return()              { t.out = append(t.out, "return") }

func TestWalk(t *testing.T) {
	cases := []struct{ src, want string }{
		{`echo "a b" 'c d' e\ f`, `cmd [echo|a b|c d|e f]`},
		{`echo x > out 2>&1`, `cmd [echo|x] >out`},
		{`echo x >& out`, `cmd [echo|x] >out`},
		{`echo x <> out`, `cmd [echo|x] >out`},
		{`cat < in`, `cmd [cat]`},
		{`X=1 Y="$HOME/a" cmd arg`, `cmd X=1 Y=$HOME/a [cmd|arg]`},
		{`X=1`, `cmd X=1`},
		{`export X=1`, `cmd decl=export X=1`},
		{`X+=b`, `cmd X+=b`},
		{`X=(a b)`, `cmd X=?`},
		{`echo $'a\x2fb'`, `cmd [echo|a/b]`},
		{`echo $'a\57b' $'a\x2Fb' $'\u0074ee' $'t\145e' $'a\tb' $'it\'s' $'a\qb'`, "cmd [echo|a/b|a/b|tee|tee|a\tb|it's|a\\qb]"},
		{`(cd a; ls)`, `enter 0; cmd [cd|a]; cmd [ls]; leave`},
		{`a | b`, `enter 2; cmd [a]; leave; enter 2; cmd [b]; leave`},
		{`a && b`, `cmd [a]; cmd [b]`},
		{`a & b`, `enter 3; cmd [a]; leave; cmd [b]`},
		{`rm $(ls)`, `enter 1; cmd [ls]; leave; cmd [rm|$]`},
		{`echo "n: $(wc -l f)"`, `quoted $(wc -l f); cmd [echo|n: $(wc -l f)]`},
		{`for f in a b; do rm $f; done`, `for f in a|b; cmd [rm|$f]`},
		{`{ a; b; } > out`, `cmd [a]; cmd [b]; cmd >out`},
		{`if a; then b; else c; fi`, `cmd [a]; cmd [b]; cmd [c]`},
		{"cat <<X\nbody\nX", `cmd [cat] heredoc="body\n"`},
		{"cat <<X | sh\nbody\nX", `enter 2; cmd [cat] heredoc="body\n"; leave; enter 2; cmd [sh] heredoc="body\n"; leave`},
		{`f() { a; }; f`, `enter 4; cmd [a]; leave; cmd [f]; call; cmd [a]; return`},
		{`f() { a; }; "f"; \f`, `enter 4; cmd [a]; leave; cmd [f]; call; cmd [a]; return; cmd [f]; call; cmd [a]; return`},
		{`f() { f; }; f`, `enter 4; cmd [f]; leave` + strings.Repeat("; cmd [f]; call", 16) + `; cmd [f]; lost` + strings.Repeat("; return", 16)},
		{`true && f() { a; }; f`, `cmd [true]; enter 4; cmd [a]; leave; cmd [f]; call; cmd [a]; return; lost`},
		{`f() { a; }; false && unset -f f; f`, `enter 4; cmd [a]; leave; cmd [false]; cmd [unset|-f|f]; cmd [f]; call; cmd [a]; return; lost`},
		{`f() { a; }; command unset -f f; f`, `enter 4; cmd [a]; leave; cmd [command|unset|-f|f]; cmd [f]`},
		{`(f() { a; }); f`, `enter 0; enter 4; cmd [a]; leave; leave; cmd [f]`},
		{`f() { a; }; unset -f f; f`, `enter 4; cmd [a]; leave; cmd [unset|-f|f]; cmd [f]`},
		{`f() { a; }; unset f; f`, `enter 4; cmd [a]; leave; cmd [unset|f]; lost; cmd [f]`},
		{`(( $(a) ))`, `enter 1; cmd [a]; leave`},
		{`[[ $a > $b ]] && c`, `cmd [c]`},
		{`diff <(a) <(b)`, `enter 1; cmd [a]; leave; enter 1; cmd [b]; leave; cmd [diff|/dev/fd/63|/dev/fd/63]`},
	}
	for _, c := range cases {
		tr := &trace{}
		if err := Walk(c.src, tr); err != nil {
			t.Errorf("%q: %v", c.src, err)
			continue
		}
		if got := strings.Join(tr.out, "; "); got != c.want {
			t.Errorf("%q\n   got  %s\n   want %s", c.src, got, c.want)
		}
	}
}

func TestUnreadable(t *testing.T) {
	for _, src := range []string{`echo "unclosed`, "cat <<'ÉOF'\nbody\nÉOF", `echo "$((echo x > a) )"`} {
		if err := Walk(src, &trace{}); err == nil {
			t.Errorf("%q: expected the parser to refuse it", src)
		}
	}
}
