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
	// Unknown, when set, says why the files this invocation writes cannot be
	// read off its arguments (they are named in a config file, for one).
	Unknown string
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
		if strings.HasPrefix(p, unknown) {
			targets = append(targets, Target{Unknown: p[len(unknown):]})
			continue
		}
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

// unknown prefixes an entry's result that is a reason, not a path.
const unknown = "\x00unknown:"

var table map[string]entry

func init() {
	table = map[string]entry{
		"cp": copyLike, "install": copyLike,
		"mv":    move,
		"mkdir": operands("m", "mode"),
		"touch": operands("trd", "date", "reference"),
		"rm":    operands(""), "rmdir": operands(""), "unlink": operands(""),
		"tee":   operands(""),
		"shred": operands("ns", "iterations", "size", "random-source"),
		"chmod": afterFirst, "chown": afterFirst, "chgrp": afterFirst,
		"truncate": operands("sr", "size", "reference"),
		"rsync":    rsync,
		"ln":       link,
		"dd":       dd,
		"curl":     curl,
		"wget":     wget,
		"sort":     sortOut,
		"tar":      tar,
		"unzip":    unzip,
		"sed":      sedInPlace,
		"perl":     perlInPlace,
		"git":      git,
		"find":     find,
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
// consumes the argument after it; `--` ends the flags; `-` alone is data. It
// reads each argument whole — for the shell builtins the guard steps over.
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

// opts is a command line read the way getopt reads it.
type opts struct {
	val   map[string][]string // "-o" / "--output" → the values given
	flags map[string]bool     // every option seen, valued or not
	pos   []string            // the operands
}

func (o opts) last(names ...string) string {
	v := ""
	for _, n := range names {
		if l := o.val[n]; len(l) > 0 {
			v = l[len(l)-1]
		}
	}
	return v
}

func (o opts) all(names ...string) []string {
	var out []string
	for _, n := range names {
		out = append(out, o.val[n]...)
	}
	return out
}

// parse reads short options in bundles: in `-sSo out`, `s` and `S` are flags and
// `o` — a letter in short — takes the rest of the bundle or the next argument
// as its value. long names the long options that take a value (`--name v` or
// `--name=v`). `--` ends the options.
func parse(a []string, short string, long ...string) opts {
	o := opts{val: map[string][]string{}, flags: map[string]bool{}}
	valued := map[string]bool{}
	for _, l := range long {
		valued[l] = true
	}
	for i := 0; i < len(a); i++ {
		x := a[i]
		switch {
		case x == "--":
			o.pos = append(o.pos, a[i+1:]...)
			return o
		case strings.HasPrefix(x, "--"):
			name, v, eq := strings.Cut(x[2:], "=")
			o.flags["--"+name] = true
			if eq {
				o.val["--"+name] = append(o.val["--"+name], v)
			} else if valued[name] {
				i++
				o.val["--"+name] = append(o.val["--"+name], at(a, i))
			}
		case len(x) >= 2 && x[0] == '-':
			for k := 1; k < len(x); k++ {
				c := string(x[k])
				o.flags["-"+c] = true
				if strings.Contains(short, c) {
					v := x[k+1:]
					if v == "" {
						i++
						v = at(a, i)
					}
					o.val["-"+c] = append(o.val["-"+c], v)
					break
				}
			}
		default:
			o.pos = append(o.pos, x)
		}
	}
	return o
}

func operands(short string, long ...string) entry {
	return func(_ string, a []string) ([]string, bool) { return parse(a, short, long...).pos, true }
}

// cp, install: the destination is the last operand, or the -t directory.
func copyLike(cmd string, a []string) ([]string, bool) {
	short := "tS"
	if cmd == "install" {
		short = "tSmogB"
	}
	o := parse(a, short, "target-directory", "suffix", "mode", "owner", "group")
	if d := o.last("-t", "--target-directory"); d != "" {
		return []string{d}, true
	}
	if len(o.pos) == 0 {
		return nil, true
	}
	return o.pos[len(o.pos)-1:], true
}

// mv: the source leaves its place, so every operand is a write.
func move(_ string, a []string) ([]string, bool) {
	o := parse(a, "tS", "target-directory", "suffix")
	return append(o.pos, o.all("-t", "--target-directory")...), true
}

// chmod, chown, chgrp: the first operand is the mode or the owner.
func afterFirst(_ string, a []string) ([]string, bool) {
	o := parse(a, "", "reference")
	if len(o.val["--reference"]) > 0 || len(o.pos) == 0 {
		return o.pos, true
	}
	return o.pos[1:], true
}

func rsync(_ string, a []string) ([]string, bool) {
	o := parse(a, "efTBM", "rsh", "exclude", "include", "filter", "files-from", "log-file", "exclude-from", "include-from",
		"temp-dir", "backup-dir", "partial-dir", "compare-dest", "copy-dest", "link-dest", "block-size", "max-size",
		"min-size", "timeout", "port", "password-file", "write-batch", "only-write-batch", "read-batch", "suffix",
		"chmod", "chown", "usermap", "groupmap", "out-format", "log-file-format", "bwlimit", "rsync-path", "remote-option",
		"info", "debug", "max-delete", "modify-window", "contimeout", "address", "sockopts", "iconv", "checksum-choice",
		"compress-choice", "compress-level", "skip-compress", "stop-after", "stop-at", "protocol", "checksum-seed", "outbuf")
	out := o.all("--log-file", "--write-batch", "--only-write-batch")
	dest := ""
	if len(o.pos) > 0 {
		dest = o.pos[len(o.pos)-1]
		out = append(out, dest)
	}
	// rsync takes a relative backup, temp or partial directory from the destination
	for _, d := range o.all("--backup-dir", "--temp-dir", "-T", "--partial-dir") {
		switch {
		case strings.HasPrefix(d, "/") || strings.HasPrefix(d, "~"):
			out = append(out, d)
		case dest == "":
			out = append(out, unknown+"rsync directory relative to a destination that is not named")
		default:
			out = append(out, strings.TrimSuffix(dest, "/")+"/"+d)
		}
	}
	return out, true
}

// ln [-s] target linkname: the link is what gets created; with one operand it
// lands in the working directory under the target's own name.
func link(_ string, a []string) ([]string, bool) {
	o := parse(a, "tS", "target-directory", "suffix")
	if d := o.last("-t", "--target-directory"); d != "" {
		return []string{d}, true
	}
	switch {
	case len(o.pos) >= 2:
		return o.pos[len(o.pos)-1:], true
	case len(o.pos) == 1:
		return []string{o.pos[0][strings.LastIndex(o.pos[0], "/")+1:]}, true
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

// curl writes where -o says, and with -O / -J under the remote's own name in
// the working directory (or --output-dir); headers, cookies and traces are files too.
func curl(_ string, a []string) ([]string, bool) {
	o := parse(a, "AbcCdDeEFHhKmoPQrtTuUwxXyYz",
		"output", "dump-header", "cookie-jar", "trace", "trace-ascii", "stderr", "etag-save", "hsts", "alt-svc",
		"output-dir", "libcurl", "config", "data", "header", "request", "user", "user-agent", "cookie", "form", "url",
		"data-raw", "data-binary", "data-urlencode", "max-time", "connect-timeout", "retry", "proxy", "cert", "key",
		"cacert", "range", "referer", "upload-file", "write-out", "resolve", "limit-rate")
	var out []string
	if o.flags["-K"] || o.flags["--config"] {
		out = append(out, unknown+"curl reads its options, output file included, from a config file")
	}
	dir := o.last("--output-dir")
	if dir != "" && (o.flags["--next"] || o.flags["-:"]) {
		// each transfer after --next has its own options: which -o the directory applies to is not read
		out = append(out, unknown+"curl --output-dir together with --next")
	}
	for _, v := range o.all("-o", "--output") {
		switch {
		case v == "-":
		case dir != "" && !strings.HasPrefix(v, "/"):
			out = append(out, strings.TrimSuffix(dir, "/")+"/"+v) // -o is taken relative to --output-dir
		default:
			out = append(out, v)
		}
	}
	for _, v := range o.all("-D", "--dump-header", "-c", "--cookie-jar", "--trace", "--trace-ascii",
		"--stderr", "--etag-save", "--hsts", "--alt-svc", "--libcurl") {
		if v != "-" {
			out = append(out, v)
		}
	}
	if o.flags["-O"] || o.flags["--remote-name"] || o.flags["--remote-name-all"] || o.flags["-J"] || o.flags["--remote-header-name"] {
		if dir == "" {
			dir = "./"
		}
		out = append(out, dir)
	}
	return out, true
}

// wget saves under the remote's name in the working directory (or -P DIR)
// unless -O names the file; its logs are files too.
func wget(_ string, a []string) ([]string, bool) {
	o := parse(a, "OoaPiTtwQUeBARDIXl", "output-document", "output-file", "append-output", "directory-prefix",
		"input-file", "tries", "timeout", "wait", "quota", "user-agent", "execute", "base", "accept", "reject",
		"domains", "level", "header", "post-data", "post-file", "user", "password", "load-cookies", "save-cookies")
	var out []string
	if o.flags["-e"] || o.flags["--execute"] || o.flags["--config"] {
		out = append(out, unknown+"wget takes settings, output file included, from -e or a config file")
	}
	for _, v := range o.all("-O", "--output-document", "-o", "--output-file", "-a", "--append-output", "--save-cookies") {
		if v != "-" {
			out = append(out, v)
		}
	}
	if len(o.all("-O", "--output-document")) == 0 {
		if d := o.last("-P", "--directory-prefix"); d != "" {
			out = append(out, d)
		} else {
			out = append(out, "./")
		}
	}
	return out, true
}

func sortOut(_ string, a []string) ([]string, bool) {
	o := parse(a, "okStT", "output", "key", "buffer-size", "field-separator", "temporary-directory", "parallel")
	return o.all("-o", "--output"), true
}

// tar: an extraction writes into -C DIR, else the working directory; creating
// an archive writes the archive. The first argument may be a flag bundle with
// no dash (`tar xzf a.tgz`), whose valued letters take the arguments after it in order.
func tar(_ string, a []string) ([]string, bool) {
	const valued = "fCbTXKNV"
	if len(a) > 0 && !strings.HasPrefix(a[0], "-") {
		// old style: rewrite `xzf a.tgz` as `-x -z -f a.tgz`
		rest := a[1:]
		var b []string
		for k := 0; k < len(a[0]); k++ {
			c := string(a[0][k])
			b = append(b, "-"+c)
			if strings.Contains(valued, c) && len(rest) > 0 {
				b = append(b, rest[0])
				rest = rest[1:]
			}
		}
		a = append(b, rest...)
	}
	o := parse(a, valued, "file", "directory", "exclude", "files-from", "exclude-from", "transform", "strip-components")
	dir := o.last("-C", "--directory")
	switch {
	case o.flags["-x"] || o.flags["--extract"] || o.flags["--get"]:
		if dir == "" {
			dir = "./"
		}
		return []string{dir}, true
	case o.flags["-c"] || o.flags["--create"] || o.flags["-r"] || o.flags["--append"] || o.flags["-u"] || o.flags["--update"]:
		if f := o.last("-f", "--file"); f != "" && f != "-" {
			return []string{f}, true
		}
	}
	return nil, false
}

func unzip(_ string, a []string) ([]string, bool) {
	o := parse(a, "dP")
	if o.flags["-l"] || o.flags["-t"] || o.flags["-p"] || o.flags["-Z"] || o.flags["-v"] {
		return nil, false // list, test, to stdout
	}
	if d := o.last("-d"); d != "" {
		return []string{d}, true
	}
	return []string{"./"}, true
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
		nf := Positionals(a[1:], `^(--source|--pathspec-from-file|-s|-e)$`)
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
	var out []string
	for k, x := range a {
		switch {
		case x == "-delete":
			writes = true
		case in(x, "-exec", "-execdir", "-ok", "-okdir"):
			if c := at(a, k+1); Writer(c) || c == "sh" || c == "bash" {
				writes = true
			}
		case in(x, "-fprint", "-fprint0", "-fls", "-fprintf"):
			out = append(out, at(a, k+1)) // find's own output files
		}
	}
	if !writes {
		return out, len(out) > 0
	}
	roots := 0
	for _, x := range a {
		if strings.HasPrefix(x, "-") || x == "(" || x == "!" {
			break
		}
		out = append(out, x)
		roots++
	}
	if roots == 0 {
		out = append(out, "./")
	}
	return out, true
}
