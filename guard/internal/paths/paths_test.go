package paths

import (
	"os"
	"path/filepath"
	"testing"
)

func TestScratchpad(t *testing.T) {
	cases := map[string]bool{
		"/tmp/claude-501/proj/sess/scratchpad":                 true,
		"/private/tmp/claude-501/proj/sess/scratchpad/out.txt": true,
		"/tmp/out.txt":                                        false,
		"/tmp/scratchpad/evil.txt":                            false,
		"/tmp/claude-5evil/proj/sess/scratchpad/x":            false,
		"/tmp/claude-501/proj/scratchpad/x":                   false,
		"/tmp/claude-501/proj/sess/deeper/scratchpad/x":       false,
		"/tmp/claude-501/proj/sess/scratchpad/../../../etc/x": false,
		"/tmp/claude-501/proj/sess/scratchpad-other/x":        false,
	}
	for p, want := range cases {
		if got := IsScratchpad(p); got != want {
			t.Errorf("IsScratchpad(%q) = %v, want %v", p, got, want)
		}
	}
}

func TestPluginCache(t *testing.T) {
	cases := map[string]bool{
		"/home/u/.claude/plugins/cache/apd/7.5.3/hooks.json": true,
		"/home/u/.claude/plugins/cache":                      true,
		"/home/u/.claude/plugins/cached/x":                   false,
		"/home/u/project/plugins/apd/bin/apd":                false,
	}
	for p, want := range cases {
		if got := IsPluginCache(p); got != want {
			t.Errorf("IsPluginCache(%q) = %v, want %v", p, got, want)
		}
	}
}

func TestInScope(t *testing.T) {
	roots := []string{"/p/src", "/p/tests"}
	cases := map[string]bool{
		"/p/src":        true,
		"/p/src/a/b.go": true,
		"/p/src/":       true,
		"/p/srcs/a.go":  false,
		"/p/tests/x":    true,
		"/p/README.md":  false,
		"/etc/passwd":   false,
		"/p":            false,
	}
	for p, want := range cases {
		if got := InScope(p, roots); got != want {
			t.Errorf("InScope(%q) = %v, want %v", p, got, want)
		}
	}
	if InScope("/p/src/x", nil) {
		t.Error("no roots: nothing but the scratchpad is in scope")
	}
}

func TestTraversal(t *testing.T) {
	cases := map[string]bool{
		"/a/b/../c": true, "/a/..": true, "../x": true, "/a/..b/c": false, "/a/b": false, "a..b": false,
	}
	for p, want := range cases {
		if got := HasTraversal(p); got != want {
			t.Errorf("HasTraversal(%q) = %v, want %v", p, got, want)
		}
	}
}

// The filesystem cases run in a temp dir resolved physically first, because the
// temp root itself is a symlink on macOS.
func TestCanon(t *testing.T) {
	root := Real(t.TempDir())
	mk := func(p string) { os.MkdirAll(filepath.Join(root, p), 0o755) }
	mk("proj/src")
	mk("outside")
	os.WriteFile(filepath.Join(root, "outside/secret.txt"), []byte("x"), 0o644)
	os.Symlink(filepath.Join(root, "outside/secret.txt"), filepath.Join(root, "proj/src/link"))
	os.Symlink(filepath.Join(root, "outside/missing.txt"), filepath.Join(root, "proj/src/dangling"))
	os.Symlink(filepath.Join(root, "outside"), filepath.Join(root, "proj/src/dirlink"))
	e := Env{Home: filepath.Join(root, "home")}
	base := filepath.Join(root, "proj")

	cases := []struct {
		name, p  string
		nofollow bool
		want     string
	}{
		{"existing file's directory resolves, new name kept", "src/new.txt", false, "proj/src/new.txt"},
		{"missing directories keep their tail", "src/a/b/c.txt", false, "proj/src/a/b/c.txt"},
		{"dot-dot through an existing directory is resolved", "src/../README.md", false, "proj/README.md"},
		{"a symlink as the last component is followed", "src/link", false, "outside/secret.txt"},
		{"rm acts on the link itself", "src/link", true, "proj/src/link"},
		{"a dangling symlink is followed by hand", "src/dangling", false, "outside/missing.txt"},
		{"a symlinked directory is resolved", "src/dirlink/x.txt", false, "outside/x.txt"},
		{"absolute path", filepath.Join(root, "outside/y"), false, "outside/y"},
		{"tilde", "~/notes.txt", false, "home/notes.txt"},
	}
	for _, c := range cases {
		if got, want := e.Canon(c.p, base, c.nofollow), filepath.Join(root, c.want); got != want {
			t.Errorf("%s: Canon(%q) = %q, want %q", c.name, c.p, got, want)
		}
	}

	// a `..` after a segment that does not exist cannot be resolved: it must survive
	got := e.Canon("src/nope/../../../etc/x", base, false)
	if !HasTraversal(got) {
		t.Errorf("unresolvable traversal lost: %q", got)
	}
	// a trailing slash is kept; scope comparison still places it
	if got := e.Canon("src/", base, false); !InScope(got, []string{filepath.Join(root, "proj/src")}) {
		t.Errorf("trailing slash fell out of scope: %q", got)
	}
}
