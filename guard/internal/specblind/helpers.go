package specblind

import (
	"regexp"
	"strings"
)

// anyText stands for text only the shell knows: a `$…` expansion, a brace
// group, a backquoted substitution. Unlike `*` it may be a name that begins
// with a dot.
const anyText = "\x01"

func strip(s, chars string) string {
	if !strings.ContainsAny(s, chars) {
		return s
	}
	return strings.Map(func(r rune) rune {
		if strings.ContainsRune(chars, r) {
			return -1
		}
		return r
	}, s)
}

func in(s string, l ...string) bool {
	for _, x := range l {
		if s == x {
			return true
		}
	}
	return false
}

// fields splits the way the shell's default IFS does: space, tab, newline.
func fields(s string) []string {
	return strings.FieldsFunc(s, func(r rune) bool { return r == ' ' || r == '\t' || r == '\n' })
}

func isGlob(s string) bool { return strings.ContainsAny(s, "*?[") }

// norm brings a project-relative path to one spelling: quotes removed, `//`
// and `/./` collapsed, a leading `./` and a trailing `/` dropped. The project
// root is the empty string.
func norm(p string) string {
	p = strip(p, `"'`)
	for strings.Contains(p, "/./") {
		p = strings.ReplaceAll(p, "/./", "/")
	}
	for strings.Contains(p, "//") {
		p = strings.ReplaceAll(p, "//", "/")
	}
	p = strings.TrimPrefix(p, "./")
	p = strings.TrimSuffix(p, "/")
	if p == "." {
		return ""
	}
	return p
}

// cutGlob keeps the literal part of a path before its first wildcard.
func cutGlob(t string) string {
	if k := strings.IndexAny(t, "*?["); k >= 0 {
		t = strings.TrimSuffix(t[:k], "/")
	}
	return t
}

// reaches: p is the blinded directory, lies inside it, or is an ancestor of it.
func reaches(p, blinded string) bool {
	return p == "" || p == blinded || strings.HasPrefix(p, blinded+"/") || strings.HasPrefix(blinded, p+"/")
}

var (
	braceRe  = regexp.MustCompile(`\{[^{}]*\}`)
	dollarRe = regexp.MustCompile(`\$[A-Za-z0-9_*@#?!:.\-]*`)
	nameRe   = regexp.MustCompile(`^[A-Za-z0-9_]+$`)
)

// gtok reduces a token to the glob the shell would make of it: quotes and
// backslashes removed, the value taken from `NAME=value` and `--opt=value`, a
// brace group, a backquote and a `$…` expansion each replaced by anyText.
func gtok(p string) string {
	if k := strings.LastIndexAny(p, "<>"); k >= 0 {
		p = p[k+1:]
	}
	p = strip(p, `;&|()`)
	p = strip(p, `"'\`)
	if k := strings.Index(p, "="); k > 0 && nameRe.MatchString(p[:k]) && !(p[0] >= '0' && p[0] <= '9') {
		p = p[k+1:]
	}
	if strings.HasPrefix(p, "--") {
		if k := strings.Index(p, "="); k >= 0 {
			p = p[k+1:]
		}
	}
	for {
		q := braceRe.ReplaceAllString(p, anyText)
		if q == p {
			break
		}
		p = q
	}
	p = strings.ReplaceAll(p, "`", anyText)
	if strings.Contains(p, "$") {
		p = dollarRe.ReplaceAllString(p, anyText)
	}
	return p
}

// globRe turns one path component of a shell pattern into a regexp. A `[` that
// is never closed is an ordinary character, as it is for the shell.
func globRe(pat string) *regexp.Regexp {
	var b strings.Builder
	b.WriteString("^(?s)")
	for i := 0; i < len(pat); i++ {
		switch c := pat[i]; c {
		case '*':
			b.WriteString(".*")
		case '?':
			b.WriteString(".")
		case '[':
			j := i + 1
			neg := false
			if j < len(pat) && (pat[j] == '!' || pat[j] == '^') {
				neg = true
				j++
			}
			start := j
			if j < len(pat) && pat[j] == ']' {
				j++
			}
			for j < len(pat) && pat[j] != ']' {
				if pat[j] == '[' && j+1 < len(pat) && pat[j+1] == ':' {
					if k := strings.Index(pat[j:], ":]"); k >= 0 {
						j += k + 2
						continue
					}
				}
				j++
			}
			if j >= len(pat) {
				b.WriteString(`\[`)
				continue
			}
			body := pat[start:j]
			var cls strings.Builder
			for k := 0; k < len(body); k++ {
				if body[k] == '[' && k+1 < len(body) && body[k+1] == ':' {
					if e := strings.Index(body[k:], ":]"); e >= 0 {
						cls.WriteString(body[k : k+e+2])
						k += e + 1
						continue
					}
				}
				if strings.IndexByte(`\]^[`, body[k]) >= 0 {
					cls.WriteByte('\\')
				}
				cls.WriteByte(body[k])
			}
			b.WriteString("[")
			if neg {
				b.WriteString("^")
			}
			b.WriteString(cls.String())
			b.WriteString("]")
			i = j
		default:
			b.WriteString(regexp.QuoteMeta(string(c)))
		}
	}
	b.WriteString("$")
	re, err := regexp.Compile(b.String())
	if err != nil {
		return regexp.MustCompile("^" + regexp.QuoteMeta(pat) + "$")
	}
	return re
}

// compMatch matches one path component against one name the way pathname
// expansion does: a pattern that begins with a wildcard does not match a name
// that begins with a dot. A component that begins with anyText is exempt —
// there the expansion itself can supply the dot.
func compMatch(pat, name string) bool {
	if strings.HasPrefix(name, ".") && pat != "" && strings.IndexByte("*?[", pat[0]) >= 0 {
		return false
	}
	return globRe(strings.ReplaceAll(pat, anyText, "*")).MatchString(name)
}

func comps(p string) []string {
	var out []string
	for _, c := range strings.Split(p, "/") {
		if c != "" && c != "." {
			out = append(out, c)
		}
	}
	return out
}

// globReaches: can the glob tok match the blinded directory b?
//
//	"full"  it can name b or something inside it
//	"anc"   it can name an ancestor of b and stops there
//	""      neither
//
// A full match is tried at every offset (the token may be absolute, or relative
// to another directory); an ancestor counts only at offset 0. A match proves
// something only if a matched component carries literal text: `"$f"`, `$a/$b`
// and `$dir/*` are the reviewer's own loops, not a path to pipeline state.
func globReaches(tok, b string) string {
	P, B := comps(tok), comps(b)
	if len(P) == 0 || len(B) == 0 {
		return ""
	}
	for k := 0; k < len(P); k++ {
		n := len(P) - k
		if n > len(B) {
			n = len(B)
		}
		ok, lit := true, false
		for j := 0; j < n; j++ {
			c := P[k+j]
			if !compMatch(c, B[j]) {
				ok = false
				break
			}
			if strip(c, anyText+"*?[]") != "" {
				lit = true
			}
		}
		if !ok || !lit {
			continue
		}
		if n == len(B) {
			return "full"
		}
		if k == 0 {
			return "anc"
		}
	}
	return ""
}

// abbr: tok is an abbreviation git would accept for the long option full, at
// least min characters long.
func abbr(tok, full string, min int) bool {
	return len(tok) >= min && strings.HasPrefix(full, tok)
}

func base(p string) string {
	if k := strings.LastIndex(p, "/"); k >= 0 {
		p = p[k+1:]
	}
	return strings.TrimPrefix(p, `\`)
}

// dotOnly: the token is a spelling of a directory made of dots and slashes
// alone (`.`, `./`, `..`, `/`).
func dotOnly(t string) bool {
	return t != "" && strings.Trim(t, "./") == ""
}
