package bashscope

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/zstevovich/claude-apd/guard/internal/paths"
)

// project builds a throwaway project: src/ is the scope, out/ lies outside it.
func project(t *testing.T) string {
	t.Helper()
	root := paths.Real(t.TempDir())
	for _, d := range []string{"src", "out", ".apd/pipeline"} {
		if err := os.MkdirAll(filepath.Join(root, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func judgeIn(root, cmd string, scope ...string) int {
	rc, _ := Judge(Options{Command: cmd, ProjectDir: root, Cwd: root, Scope: scope, Home: filepath.Join(root, "home")})
	return rc
}

// Every form of output redirection names a write target; descriptor
// duplication and input redirection do not.
func TestRedirections(t *testing.T) {
	root := project(t)
	cases := []struct {
		cmd  string
		want int
	}{
		{"echo x > src/a", 0},
		{"echo x >> src/a", 0},
		{"echo x &> src/a", 0},
		{"echo x >| src/a", 0},
		{"echo x >& src/a", 0},
		{"echo x 1<> src/a", 0},
		{"echo x > out/a", 2},
		{"echo x >> out/a", 2},
		{"echo x &> out/a", 2},
		{"echo x &>> out/a", 2},
		{"echo x >| out/a", 2},
		{"echo x >& out/a", 2},
		{"echo x 1<> out/a", 2},
		{"echo x <> out/a", 2},
		{"echo x 2>&1", 0},
		{"echo x >&2", 0},
		{"echo x 2>&-", 0},
		{"echo x 3>&1-", 0},
		{"cat < out/a", 0},
		{"cat <<< out/a", 0},
		{"echo x 2>/dev/null", 0},
	}
	for _, c := range cases {
		if got := judgeIn(root, c.cmd, "src/"); got != c.want {
			t.Errorf("%q: rc=%d, want %d", c.cmd, got, c.want)
		}
	}
}
