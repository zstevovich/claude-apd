// Package tools knows which arguments of a command-line tool are files it
// writes. One entry per tool; each is a pure function of the argument list, so
// what the guard believes about `cp` or `tar` can be read and tested in one place.
package tools

import (
	"regexp"
	"strings"
)

// Target is a path a tool would write. NoFollow marks tools that act on a
// symlink itself (rm, rmdir, unlink) and not on what it points to.
type Target struct {
	Path     string
	NoFollow bool
}

// Writes returns the files `cmd args…` would write. ok is false when the tool
// is not in the table, or is in it but this invocation writes no file by itself
// (`sed` without -i, `find` without -delete or -exec).
func Writes(cmd string, args []string) (targets []Target, ok bool) {
	f := table[cmd]
	if f == nil {
		return nil, false
	}
	paths, ok := f(cmd, args)
	if !ok {
		return nil, false
	}
	nofollow := cmd == "rm" || cmd == "rmdir" || cmd == "unlink"
	for _, p := range paths {
		targets = append(targets, Target{Path: p, NoFollow: nofollow})
	}
	return targets, true
}

// Writer reports whether cmd is a tool that writes files — what `xargs` and
// `find -exec` need to know about the command they are handed.
func Writer(cmd string) bool { return writers[cmd] }

var writers = map[string]bool{"cp": true, "mv": true, "rm": true, "rmdir": true, "mkdir": true, "touch": true,
	"tee": true, "sed": true, "perl": true, "install": true, "dd": true, "ln": true, "truncate": true,
	"chmod": true, "chown": true, "rsync": true}

type entry func(cmd string, a []string) ([]string, bool)

var table map[string]entry

func init() {
	table = map[string]entry{
		"cp": copyLike, "install": copyLike,
		"mv":    move,
		"mkdir": all(`^(-m|--mode)$`),
		"touch": all(`^(-t|-r|-d|--date|--reference)$`),
		"rm":    all(`^$`), "rmdir": all(`^$`), "unlink": all(`^$`), "tee": all(`^$`), "shred": all(`^$`),
		"chmod": afterFirst, "chown": afterFirst, "chgrp": afterFirst,
		"truncate": all(`^(-s|-r|--size|--reference)$`),
		"rsync":    rsync,
		"ln":       link,
		"dd":       dd,
		"curl":     download, "wget": download,
		"sort": sortOut,
		"tar":  extract, "unzip": extract,
		"sed":  sedInPlace,
		"perl": perlInPlace,
		"git":  git,
		"find": find,
	}
}

func at(a []string, i int) string {
	if i >= 0 && i < len(a) {
		return a[i]
	}
	return ""
}

func in(s string, l ...string) bool {
	for _, x := range l {
		if s == x {
			return true
		}
	}
	return false
}

func letter(c byte) bool { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') }
func alnum(c byte) bool  { return letter(c) || (c >= '0' && c <= '9') }

// Positionals returns the arguments that are not flags. A flag matching valued
// consumes the argument after it; `--` ends the flags; `-` alone is data.
func Positionals(a []string, valued string) []string {
	re := regexp.MustCompile(valued)
	var out []string
	done, skip := false, false
	for _, x := range a {
		if skip {
			skip = false
			continue
		}
		if !done {
			if x == "--" {
				done = true
				continue
			}
			if len(x) >= 2 && x[0] == '-' {
				skip = re.MatchString(x)
				continue
			}
		}
		out = append(out, x)
	}
	return out
}

func all(valued string) entry {
	return func(_ string, a []string) ([]string, bool) { return Positionals(a, valued), true }
}

// targetDir is GNU `-t DIR` / `--target-directory=DIR`.
func targetDir(a []string) []string {
	var out []string
	for k, x := range a {
		if x == "-t" || x == "--target-directory" {
			out = append(out, at(a, k+1))
		} else if strings.HasPrefix(x, "--target-directory=") {
			out = append(out, strings.TrimPrefix(x, "--target-directory="))
		}
	}
	return out
}

// cp, install: the destination is the last operand, or the -t directory.
func copyLike(_ string, a []string) ([]string, bool) {
	if d := targetDir(a); len(d) > 0 && d[len(d)-1] != "" {
		return d[len(d)-1:], true
	}
	nf := Positionals(a, `^(-t|--target-directory|-m|-o|-g|--mode|--owner|--group)$`)
	if len(nf) == 0 {
		return nil, true
	}
	return nf[len(nf)-1:], true
}

// mv: the source leaves its place, so every operand is a write.
func move(_ string, a []string) ([]string, bool) {
	return append(Positionals(a, `^(-t|--target-directory)$`), targetDir(a)...), true
}

// chmod, chown, chgrp: the first operand is the mode or the owner.
func afterFirst(_ string, a []string) ([]string, bool) {
	nf := Positionals(a, `^(--reference)$`)
	if len(nf) > 0 {
		nf = nf[1:]
	}
	return nf, true
}

func rsync(_ string, a []string) ([]string, bool) {
	nf := Positionals(a, `^(-e|--rsh|--exclude|--include|--filter|--files-from|--log-file)$`)
	if len(nf) > 0 {
		nf = nf[len(nf)-1:]
	}
	return nf, true
}

// ln [-s] target linkname: the link is what gets created; with one operand it
// lands in the working directory under the target's own name.
func link(_ string, a []string) ([]string, bool) {
	nf := Positionals(a, `^(-t|--target-directory|-S|--suffix)$`)
	switch {
	case len(nf) >= 2:
		return nf[len(nf)-1:], true
	case len(nf) == 1:
		return []string{nf[0][strings.LastIndex(nf[0], "/")+1:]}, true
	}
	return nil, true
}

func dd(_ string, a []string) ([]string, bool) {
	var out []string
	for _, x := range a {
		if strings.HasPrefix(x, "of=") {
			out = append(out, x[3:])
		}
	}
	return out, true
}

func download(cmd string, a []string) ([]string, bool) {
	var out []string
	named := false
	for k, x := range a {
		switch {
		case in(x, "-o", "--output", "-O", "--output-document"):
			out = append(out, at(a, k+1))
		case strings.HasPrefix(x, "--output=") || strings.HasPrefix(x, "--output-document="):
			out = append(out, x[strings.Index(x, "=")+1:])
		case strings.HasPrefix(x, "-o") && cmd == "curl":
			out = append(out, x[2:])
		case strings.HasPrefix(x, "-O") && cmd == "wget":
			out = append(out, x[2:])
		}
		if strings.HasPrefix(x, "-O") || strings.HasPrefix(x, "--output-document") {
			named = true
		}
	}
	if cmd == "wget" && !named {
		out = append(out, "./") // wget saves into the working directory
	}
	return out, true
}

func sortOut(_ string, a []string) ([]string, bool) {
	var out []string
	for k, x := range a {
		switch {
		case x == "-o" || x == "--output":
			out = append(out, at(a, k+1))
		case strings.HasPrefix(x, "--output="):
			out = append(out, x[9:])
		case strings.HasPrefix(x, "-o") && len(x) > 2:
			out = append(out, x[2:])
		}
	}
	return out, true
}

// tar, unzip: an extraction writes into -C DIR (unzip: -d DIR), else the working directory.
// tar's first argument may be a flag bundle with no dash (`tar xzf a.tgz`).
func extract(cmd string, a []string) ([]string, bool) {
	dir := ""
	for k, x := range a {
		if in(x, "-C", "--directory", "-d") {
			dir = at(a, k+1)
		} else if strings.HasPrefix(x, "--directory=") {
			dir = x[12:]
		}
	}
	extracting := cmd == "unzip"
	if cmd == "tar" {
		for k, x := range a {
			switch {
			case x == "--extract" || x == "--get":
				extracting = true
			case strings.HasPrefix(x, "--"):
			case strings.HasPrefix(x, "-") && strings.Contains(x, "x"):
				extracting = true
			case k == 0 && !strings.HasPrefix(x, "-") && strings.Contains(x, "x"):
				extracting = true
			}
		}
	}
	if !extracting {
		return nil, false
	}
	if dir == "" {
		dir = "./"
	}
	return []string{dir}, true
}

// sed -i (also -Ei, -ni, -i.bak, --in-place): the files are the operands after
// the script; with -e or -f every operand is a file.
func sedInPlace(_ string, a []string) ([]string, bool) {
	inplace, hasExpr := false, false
	for _, x := range a {
		switch {
		case strings.HasPrefix(x, "--in-place"):
			inplace = true
		case in(x, "-e", "--expression", "-f", "--file"):
			hasExpr = true
		case len(x) > 2 && (strings.HasPrefix(x, "-e") || strings.HasPrefix(x, "-f")):
			hasExpr = true
		case len(x) >= 2 && x[0] == '-' && letter(x[1]) && strings.Contains(x, "i"):
			inplace = true
		}
	}
	if !inplace {
		return nil, false
	}
	var out []string
	seenScript, expect := false, false
	for _, x := range a {
		switch {
		case expect:
			expect = false
		case x == "": // BSD `-i ''`
		case in(x, "-e", "--expression", "-f", "--file"):
			expect = true
		case strings.HasPrefix(x, "-"):
		case !hasExpr && !seenScript:
			seenScript = true
		default:
			out = append(out, x)
		}
	}
	return out, true
}

// perl -i / -pi / -i.bak edits its file operands in place. Without -i this
// entry declines and the caller reads the program text instead.
func perlInPlace(_ string, a []string) ([]string, bool) {
	inplace := false
	for _, x := range a {
		if x == "-e" || x == "-E" {
			continue
		}
		if strings.HasPrefix(x, "-i") || (len(x) >= 2 && x[0] == '-' && alnum(x[1]) && strings.Contains(x[2:], "i")) {
			inplace = true
		}
	}
	if !inplace {
		return nil, false
	}
	var out []string
	expect := false
	for _, x := range a {
		switch {
		case expect:
			expect = false
		case in(x, "-e", "-E", "-M", "-m"):
			expect = true
		case strings.HasPrefix(x, "-"):
		default:
			out = append(out, x)
		}
	}
	return out, true
}

// git rm / mv / restore / clean write their pathspecs; `git checkout [ref] -- paths` overwrites them.
func git(_ string, a []string) ([]string, bool) {
	switch at(a, 0) {
	case "rm", "mv", "restore", "clean":
		nf := Positionals(a[1:], `^(--source|--pathspec-from-file)$`)
		if a[0] == "clean" && len(nf) == 0 {
			nf = []string{"./"}
		}
		return nf, true
	case "checkout":
		var out []string
		after := false
		for _, x := range a[1:] {
			if after {
				out = append(out, x)
			} else if x == "--" {
				after = true
			}
		}
		return out, true
	}
	return nil, false
}

// find … -delete, or -exec with a writing tool: the search roots are what gets written.
func find(_ string, a []string) ([]string, bool) {
	writes := false
	for k, x := range a {
		if x == "-delete" {
			writes = true
		} else if in(x, "-exec", "-execdir", "-ok", "-okdir") {
			if c := at(a, k+1); Writer(c) || c == "sh" || c == "bash" {
				writes = true
			}
		}
	}
	if !writes {
		return nil, false
	}
	var roots []string
	for _, x := range a {
		if strings.HasPrefix(x, "-") || x == "(" || x == "!" {
			break
		}
		roots = append(roots, x)
	}
	if len(roots) == 0 {
		roots = []string{"./"}
	}
	return roots, true
}
