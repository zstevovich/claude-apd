// Package paths turns the path a command names into the physical path it would
// touch, and answers where that path lies: inside a scope, the session
// scratchpad, or a plugin cache. One implementation for every guard.
package paths

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// Env is what path resolution needs from the caller's environment.
type Env struct {
	Home string
}

func IsDir(p string) bool { st, err := os.Stat(p); return err == nil && st.IsDir() }
func IsLink(p string) bool {
	st, err := os.Lstat(p)
	return err == nil && st.Mode()&os.ModeSymlink != 0
}
func Exists(p string) bool { _, err := os.Stat(p); return err == nil }

// Real is the physical form of p, or "" when a component of p does not exist.
func Real(p string) string {
	r, err := filepath.EvalSymlinks(p)
	if err != nil {
		return ""
	}
	return r
}

// dirname and basename as the shell tools compute them: no cleaning, so a `..`
// stays where it was written.
func dirname(p string) string {
	if p == "" {
		return "."
	}
	q := strings.TrimRight(p, "/")
	if q == "" {
		return "/"
	}
	i := strings.LastIndex(q, "/")
	if i < 0 {
		return "."
	}
	d := strings.TrimRight(q[:i], "/")
	if d == "" {
		return "/"
	}
	return d
}

func basename(p string) string {
	q := strings.TrimRight(p, "/")
	if q == "" {
		if p == "" {
			return ""
		}
		return "/"
	}
	return q[strings.LastIndex(q, "/")+1:]
}

// Absolutize joins a relative path to base and expands a leading `~`. Nothing
// is resolved or cleaned.
func (e Env) Absolutize(p, base string) string {
	switch {
	case strings.HasPrefix(p, "/"):
		return p
	case p == "~":
		return e.Home
	case strings.HasPrefix(p, "~/"):
		return e.Home + "/" + p[2:]
	}
	return base + "/" + p
}

// CanonAbs is the physical absolute form of p. A path that does not exist yet
// still resolves: the deepest existing ancestor is resolved and the missing
// tail re-attached as written, so a `..` inside that tail survives for the
// caller's traversal check. A dangling symlink is followed by hand unless
// nofollow is set.
func (e Env) CanonAbs(p, base string, nofollow bool) string {
	if p == "" {
		return ""
	}
	p = e.Absolutize(p, base)
	abs := Real(p)
	if abs == "" && !nofollow && IsLink(p) {
		for hops := 0; IsLink(p) && hops < 40; hops++ {
			t, err := os.Readlink(p)
			if err != nil || t == "" {
				break
			}
			if strings.HasPrefix(t, "/") {
				p = t
			} else {
				p = dirname(p) + "/" + t
			}
		}
		abs = Real(p)
	}
	if abs == "" {
		anc, tail := dirname(p), basename(p)
		for !IsDir(anc) && anc != "/" && anc != "." {
			tail = basename(anc) + "/" + tail
			anc = dirname(anc)
		}
		if IsDir(anc) {
			if r := Real(anc); r != "" {
				abs = strings.TrimRight(r, "/") + "/" + tail
			}
		}
	}
	if abs == "" {
		abs = p
	}
	return abs
}

// Canon resolves a write target. The directory is resolved physically; the last
// component is followed when it is a symlink, unless nofollow is set (rm,
// unlink and rmdir act on the link itself).
func (e Env) Canon(p, base string, nofollow bool) string {
	p = e.Absolutize(p, base)
	if strings.HasSuffix(p, "/..") || strings.Contains(p, "/../") || strings.HasSuffix(p, "/.") ||
		strings.Contains(p, "/./") || strings.Contains(p, "//") {
		return e.CanonAbs(p, "/", false)
	}
	i := strings.LastIndex(p, "/")
	d, b := p[:i], p[i+1:]
	if d == "" {
		d = "/"
	}
	abs := strings.TrimRight(e.CanonAbs(d, "/", false), "/") + "/" + b
	if !nofollow && IsLink(abs) {
		return e.CanonAbs(abs, "/", false)
	}
	return abs
}

// HasTraversal reports a `..` segment that survived canonicalisation.
func HasTraversal(p string) bool {
	q := "/" + p + "/"
	return strings.Contains(q, "/../")
}

var scratchRe = regexp.MustCompile(`^(/private)?/tmp/claude-[0-9]+/[^/]+/[^/]+/scratchpad(/.*)?$`)

// IsScratchpad reports the session scratchpad Claude Code hands each session:
// claude-<uid>/<project>/<session>/scratchpad, exactly, and never through `..`.
func IsScratchpad(p string) bool { return !HasTraversal(p) && scratchRe.MatchString(p) }

// IsPluginCache reports a path inside a Claude Code plugin cache.
func IsPluginCache(p string) bool {
	p = strings.ToLower(p) // a case-insensitive volume opens `PLUGINS/cache` as the same directory
	return strings.Contains(p, "/plugins/cache/") || strings.HasSuffix(p, "/plugins/cache")
}

// InScope reports whether the canonical path p is the scratchpad or lies at or
// under one of the canonical roots.
func InScope(p string, roots []string) bool {
	if IsScratchpad(p) {
		return true
	}
	for _, r := range roots {
		if p == r || strings.HasPrefix(p+"/", r+"/") {
			return true
		}
	}
	return false
}
