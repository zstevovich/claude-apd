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

type row struct {
	cmd  string
	want int
}

func check(t *testing.T, root string, rows []row, scope ...string) {
	t.Helper()
	for _, c := range rows {
		if got := judgeIn(root, c.cmd, scope...); got != c.want {
			t.Errorf("%q: rc=%d, want %d", c.cmd, got, c.want)
		}
	}
}

// What a subshell, a substitution, a pipeline element or a background job
// changes does not reach the commands after it; the guard must not believe it does.
func TestStateDoesNotLeak(t *testing.T) {
	root := project(t)
	check(t, root, []row{
		// variables
		{"X=out/a; (X=src/a); echo hi > $X", 2},
		{"X=out/a; echo $(X=src/a); echo hi > $X", 2},
		{"X=out/a; X=src/a | cat; echo hi > $X", 2},
		{"X=out/a; X=src/a & echo hi > $X", 2},
		{"X=src/a; (X=out/a); echo hi > $X", 0},
		{"X=src/a; echo hi > $X", 0},
		// the working directory
		{"(cd src); echo hi > a", 2},
		{"cd src | cat; echo hi > a", 2},
		{"cd src & echo hi > a", 2},
		{"cd src; echo hi > a", 0},
		{"(cd src; echo hi > a)", 0},
		{"cd src && echo hi | tee a", 0},
	}, "src/")
}

// `X=v cmd` puts X in cmd's environment only: the line's own redirection was
// expanded with the old value, and the next command does not see the new one.
func TestPrefixAssignment(t *testing.T) {
	root := project(t)
	check(t, root, []row{
		{"X=out/a; X=src/a true; echo hi > $X", 2},
		{"X=out/a; X=src/a echo hi > $X", 2},
		{"X=src/a true; echo hi > $X", 2}, // X is unset afterwards: unresolved, refused
		{"X=src/a; echo hi > $X", 0},
		{"export X=src/a; echo hi > $X", 0},
		{"X=src/a; command export X=out/a; echo hi > $X", 2},
		{"X=out/a; builtin declare X=src/a; echo hi > $X", 0},
		{"X=out/a sh -c 'echo hi > $X'", 2},
		{"X=src/a sh -c 'echo hi > $X'", 0},
		{"env X=out/a sh -c 'echo hi > $X'", 2},
	}, "src/")
}

// A variable filled from input, appended to an unknown value, or held in an
// array has a value the guard cannot know.
func TestUnknownValues(t *testing.T) {
	root := project(t)
	check(t, root, []row{
		{"X=src/a; read X; echo hi > $X", 2},
		{"X=src/a; read -r X < list; echo hi > $X", 2},
		{"X=src/a; printf -v X %s out/a; echo hi > $X", 2},
		{"X=src/a; unset X; echo hi > $X", 2},
		{"X=src/; X+=../out/a; echo hi > $X", 2},
		{"X=src/; X+=a; echo hi > $X", 0},
		{"X+=src/a; echo hi > $X", 2},
		{"X=(src/a out/a); echo hi > $X", 2},
		{"cd src; X=(../out/a); echo hi > $X", 2},
	}, "src/")
}

// A function body runs where it is called, in the caller's shell.
func TestFunctions(t *testing.T) {
	root := project(t)
	check(t, root, []row{
		{"f() { echo hi > out/a; }", 2}, // judged where it is defined, called or not
		{"f() { echo hi > src/a; }; f", 0},
		{"f() { cd out; }; f; echo hi > a", 2},
		{"f() { cd out; }; echo hi > src/a", 0},
		{"f() { X=out/a; }; X=src/a; f; echo hi > $X", 2},
		{"f() { cd out; }; \"f\"; echo hi > a", 2},
		{"f() { cd out; }; \\f; echo hi > a", 2},
		{"f() { cd out; }; eval f; echo hi > a", 2},
		{"f() { f; }; cd src; f; echo hi > a", 2}, // the reader gave up following: nothing relative is placed
		// a function defined in a subshell does not exist after it
		{"(f() { cd src; }); f; echo hi > a", 2},
		{"f() { cd ../out; }; (f() { :; }); cd src; f; echo hi > a", 2},
		{"f() { cd src; }; unset -f f; f; echo hi > a", 2},
		{"f() { cd src; }; unset f; f; echo hi > a", 2},
		// a function named like a builtin runs instead of it
		{"cd() { builtin cd out; }; cd src; echo hi > a", 2},
		{"cd() { builtin cd src; }; cd out; echo hi > a", 0},
		{"rm() { :; }; rm out/a", 0},
		// `X=v f`: in effect for the body, gone after it
		{"X=src/a; f() { echo hi > $X; }; X=out/a f", 2},
		{"X=src/a; f() { echo hi > $X; }; X=src/b f", 0},
		{"X=out/a; f() { echo hi > $X; }; X=src/a f", 2}, // the body is also judged where it is defined, with X as it was there
		{"X=src/a; f() { :; }; X=out/a f; echo hi > $X", 0},
		{"f() { :; }; X=src/a f; echo hi > $X", 2},
	}, "src/")
}

// Text handed to a shell is a command line.
func TestShellText(t *testing.T) {
	root := project(t)
	check(t, root, []row{
		{"sh -c 'echo hi > out/a'", 2},
		{"bash -c 'echo hi > src/a'", 0},
		{"eval 'echo hi > out/a'", 2},
		{"eval 'echo hi > src/a'", 0},
		{"cd src; eval 'cd ../out'; echo hi > a", 2},
		{"eval 'cd src'; echo hi > a", 0},
		{"X=src/a; eval 'X=out/a'; echo hi > $X", 2},
		{"eval 'f() { cd out; }'; f; echo hi > a", 2},
		{"X=out/a eval 'echo hi > $X'", 2},
		{"X=src/a eval 'echo hi > $X'", 0},
		{"sh <<X\necho hi > out/a\nX", 2},
		{"cat <<X | sh\necho hi > out/a\nX", 2},
		{"cat <<X | bash\necho hi > src/a\nX", 0},
		{"cat <<X | python3\nopen('out/a','w').write('x')\nX", 2},
		{"cat <<X > src/a\nrm out/a\nX", 0}, // a heredoc written to a file is data
		{"CMD='rm out/a'; $CMD", 2},
		{"$UNKNOWN out/a", 2},
		{"echo \"$(rm out/a)\"", 2},
		{"echo \"$(cat out/a)\" > src/b", 0},
	}, "src/")
}

func TestTools(t *testing.T) {
	root := project(t)
	check(t, root, []row{
		{"tar xf a.tar -C out", 2},
		{"tar xzf a.tgz", 2}, // extracts into the project root, outside src/
		{"cd src && tar xzf ../a.tgz", 0},
		{"tar -xf a.tar -C src", 0},
		{"tar tf box.tar -C out", 0},
		{"tar czf out/a.tgz src", 2},
		{"tar czf src/a.tgz src", 0},
		{"curl -sSLo out/x https://example.org", 2},
		{"curl -sSLo src/x https://example.org", 0},
		{"curl -fsSLO https://example.org/x", 2},
		{"cd src && curl -fsSLO https://example.org/x", 0},
		{"cp -rt out src/a", 2},
		{"cp -rt src/dest src/a", 0},
		{"sort -uo out/sorted src/a", 2},
		{"find out -name '*.tmp' -delete", 2},
		{"find src -name '*.tmp' -delete", 0},
		{"ls | xargs rm", 2},
		{"sed -i '' s/a/b/ out/a", 2},
		{"sed -n s/a/b/p out/a", 0},
		{"\\rm out/a", 2},
		{"$'\\u0074ee' out/a", 2},
		{"$'\\u0074ee' src/a", 0},
	}, "src/")
}

// The orchestrator has no scope: only the pipeline directory is fenced for it.
// APD's own tools are exempt for their own statement — the real ones, by where
// they live.
func TestPipelineFence(t *testing.T) {
	root := project(t)
	apd := filepath.Join(root, "plug/plugins/apd")
	fake := filepath.Join(root, "evil/plugins/apd")
	for _, d := range []string{apd, fake} {
		os.MkdirAll(filepath.Join(d, "bin/core"), 0o755)
	}
	j := func(cmd string) int {
		rc, _ := Judge(Options{Command: cmd, ProjectDir: root, Cwd: root, ApdRoot: apd, Home: filepath.Join(root, "home")})
		return rc
	}
	rows := []row{
		{"echo hi > out/a", 0},
		{"rm -rf .apd/pipeline", 2},
		{"cd .apd && rm pipeline/.agents", 2},
		{"cd .apd/pipeline; rm .agents", 2},
		{"rm -rf $'.apd\\x2fpipeline'", 2},
		{"rm -rf $'.apd\\57pipeline'", 2},
		{"rm -rf '.apd'/\"pipeline\"", 2},
		{"bash -c 'rm -rf .apd/pipeline'", 2},
		{"echo ok > .apd/pipeline/.guide-marker", 0},
		{apd + "/bin/core/pipeline-advance spec x 2> .apd/pipeline/err.log", 0},
		{"bash " + apd + "/bin/core/pipeline-gate > .apd/pipeline/out.log", 0},
		{fake + "/bin/core/pipeline-advance > .apd/pipeline/.agents", 2},
		{"bash " + fake + "/bin/core/pipeline-gate > .apd/pipeline/spec.done", 2},
		{apd + "/bin/core/pipeline-advance spec x; rm -rf .apd/pipeline", 2},
		{"bash \"${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/pipeline-advance\" builder > .apd/pipeline/log", 0},
		{"bash $APD_PLUGIN_ROOT/bin/core/pipeline-gate > .apd/pipeline/log", 0},
		{"CLAUDE_PLUGIN_ROOT=" + filepath.Join(root, "evil") + "; bash \"${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/pipeline-advance\" > .apd/pipeline/log", 2},
		{"APD_PLUGIN_ROOT=" + fake + "; bash $APD_PLUGIN_ROOT/bin/core/pipeline-gate > .apd/pipeline/log", 2},
		{"bash /x/$APD_PLUGIN_ROOT/bin/core/pipeline-gate > .apd/pipeline/log", 2},
	}
	for _, c := range rows {
		if got := j(c.cmd); got != c.want {
			t.Errorf("%q: rc=%d, want %d", c.cmd, got, c.want)
		}
	}
}
