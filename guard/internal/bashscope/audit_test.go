package bashscope

import (
	"strings"
	"testing"
	"time"
)

// Rows from the independent audit of the port (2026-11-16): each is a command
// the v7.5.3 guard refused and the first Go build let through.
func TestAuditReader(t *testing.T) {
	root := project(t)
	for _, c := range []struct {
		cmd  string
		want int
	}{
		// a substitution in a case pattern runs
		{"case x in $(touch out/a)) ;; esac", 2},
		{"case x in $(touch src/a)) ;; esac", 0},
		// a process substitution inside [[ … ]] or ${…} runs
		{"[[ -e <(touch out/a) ]]", 2},
		{"[[ -e <(touch src/a) ]]", 0},
		{"echo ${x:-<(touch out/a)}", 2},
		{"x=${y:-<(touch out/a)}", 2},
		// coproc CMD NAME=value: the command is CMD
		{"coproc dd of=out/a", 2},
		{"coproc dd if=/dev/zero of=out/a", 2},
		{"coproc dd of=src/a", 0},
		{"coproc W { cat > out/a; }", 2},
		// a here-string is the standard input of a shell
		{"sh <<< 'echo x > out/a'", 2},
		{"sh <<< 'echo x > src/a'", 0},
	} {
		if got := judgeIn(root, c.cmd, "src/"); got != c.want {
			t.Errorf("%q: rc=%d, want %d", c.cmd, got, c.want)
		}
	}
}

func TestAuditUnknownValueRuns(t *testing.T) {
	root := project(t)
	for _, cmd := range []string{
		`read l; eval "$l"`,
		`read l; bash -c "$l"`,
		`read l; $l`,
		`while read l; do eval "$l"; done < src/cmds`,
		`printf -v l '%s' "$1"; eval "$l"`,
		`getopts a l; eval "$l"`,
		`unset l; eval "$l"`,
	} {
		for _, scope := range [][]string{{"src/"}, nil} { // a scoped agent, and the orchestrator
			if got := judgeIn(root, cmd, scope...); got != 2 {
				t.Errorf("%q scope=%v: rc=%d, want 2", cmd, scope, got)
			}
		}
	}
	// a value the command gave is still read
	if got := judgeIn(root, `l='echo x > src/a'; eval "$l"`, "src/"); got != 0 {
		t.Errorf("a known value run through eval: rc=%d, want 0", got)
	}
}

func TestAuditEvalBehindAProgram(t *testing.T) {
	root := project(t)
	for _, c := range []struct {
		cmd  string
		want int
	}{
		// `nice eval …` is a program named eval: nothing it sets reaches this shell
		{"x=out; nice eval x=src; touch $x/a", 2},
		{"x=out; timeout 5 eval x=src; touch $x/a", 2},
		{"x=out; env eval x=src; touch $x/a", 2},
		{"cd out; nohup eval 'cd " + root + "/src'; touch a", 2},
		// the builtin, also behind `command` and `builtin`, does
		{"x=out; eval x=src; touch $x/a", 0},
		{"x=out; command eval x=src; touch $x/a", 0},
		{"x=out; builtin eval x=src; touch $x/a", 0},
	} {
		if got := judgeIn(root, c.cmd, "src/"); got != c.want {
			t.Errorf("%q: rc=%d, want %d", c.cmd, got, c.want)
		}
	}
}

func TestAuditFunctionThroughAVariable(t *testing.T) {
	root := project(t)
	for _, c := range []struct {
		cmd  string
		want int
	}{
		{"cd src; f() { cd ../out; }; g=f; $g; touch a", 2},
		{`cd src; f() { cd ../out; }; g=f; "$g"; touch a`, 2},
		{"cd src; f() { cd ../out; }; for g in f; do $g; done; touch a", 2},
		{"x=src; f() { x=out; }; g=f; $g; touch $x/a", 2},
		{"cd out; f() { cd ../src; }; g=f; $g; touch a", 0},
		// the shell splits an expanded value into words, it does not read syntax in it
		{"x=out; g='x=src'; $g; touch $x/a", 2},
		{"x=out; g='eval x=src'; $g; touch $x/a", 0}, // eval is a command: it does read its arguments
		{"cd out; g='cd ../src'; $g; touch a", 0},
		{"g='echo x > out/a'; $g", 0}, // prints `x > out/a`: nothing is written
		{"g='touch out/a'; $g", 2},
		// the arguments stay the words they were, and an unresolved one stays unresolved
		{`cd src; g=touch; $g $1`, 2},
		{`cd src; g=touch; $g "$UNSET/x"`, 2},
		{`cd src; g=touch; $g "a b"`, 0},
		{`cd src; g=touch; $g a ../out/b`, 2},
		{`g=touch; $g "src/a b"`, 0},
		{`cd src; g=touch; $g "a ; touch /etc/b"`, 0}, // one odd file name under src, not two commands
		{`cd src; g=touch; $g "a > /etc/b"`, 0},
		// a value with a quote in it does not change how the rest is read
		{`cd src; v='" #'; g=touch; $g "$v" ../out/b`, 2},
		{`cd src; v='"; : "'; g=cp; $g x "$v" ../out/b`, 2},
		// a prefix assignment is not what the arguments expand to
		{`cd src; X=../out/b; g=touch; X=a $g $X`, 2},
		{`cd src; X=a; g=touch; X=../out/b $g $X`, 0},
		// a function that may not have been defined: the name may be the program
		{`if false; then touch(){ :; }; fi; g=touch; $g out/a`, 2},
		{`touch(){ :; }; g=touch; $g out/a`, 0}, // certainly the function: it writes nothing
		// xargs in front of the variable: stdin still supplies arguments
		{`g=rm; ls | xargs $g`, 2},
		{`g=cat; ls | xargs $g`, 0},
		// env inside the value reaches the command
		{`g='env D=out sh -c'; $g 'touch $D/a'`, 2},
		{`g='env D=src sh -c'; $g 'touch $D/a'`, 0},
		// a wrapper inside the value
		{`g='sudo touch'; $g out/a`, 2},
		{`g='env touch'; $g src/a`, 0},
	} {
		if got := judgeIn(root, c.cmd, "src/"); got != c.want {
			t.Errorf("%q: rc=%d, want %d", c.cmd, got, c.want)
		}
	}
}

// On a case-insensitive volume `.APD/Pipeline` is the pipeline directory.
func TestAuditFenceInAnotherCase(t *testing.T) {
	root := project(t)
	for _, cmd := range []string{
		"touch .Apd/Pipeline/builder.done",
		"echo x > .APD/pipeline/spec.done",
		"rm -rf .APD/pipeline",
		"cd .APD && touch pipeline/x",
		`python3 -c "open('.APD/pipeline/x','w')"`,
		"touch ~/.claude/PLUGINS/cache/mp/claude-apd/7.5.3/x",
		"rm -rf ~/.claude/PLUGINS/cache",
	} {
		if got := judgeIn(root, cmd); got != 2 { // the orchestrator: only the fences apply
			t.Errorf("%q: rc=%d, want 2", cmd, got)
		}
	}
	// an agent whose scope is the whole project: only the text rules stand between it and the fence
	for _, cmd := range []string{"echo x > .APD/pipeline/spec.done", "cp src/a .Apd/Pipeline/builder.done"} {
		if got := judgeIn(root, cmd, "./"); got != 2 {
			t.Errorf("%q with scope ./: rc=%d, want 2", cmd, got)
		}
	}
	if got := judgeIn(root, "touch notes/Pipeline.md"); got != 0 {
		t.Errorf("an ordinary orchestrator write: rc=%d, want 0", got)
	}
}

// A brace expansion in code that never runs must not make the guard outlast
// the hook's timeout: a timed-out hook is cancelled and the call goes through.
func TestAuditBraceExpansionIsBounded(t *testing.T) {
	root := project(t)
	cmd := "if false; then " + strings.Repeat(": {1..3000000}; ", 6) + "fi; touch out/a"
	start := time.Now()
	got := judgeIn(root, cmd, "src/")
	if d := time.Since(start); d > 3*time.Second {
		t.Errorf("judged in %v, want well under the 30 s hook timeout", d)
	}
	if got != 2 {
		t.Errorf("rc=%d, want 2", got)
	}
	for _, c := range []struct {
		cmd  string
		want int
	}{
		{"touch src/{a,b,c}", 0},
		{"touch {src,out}/a", 2},
		{"touch src/f{1..20}", 0},
		{"touch out/f{1..3000000}", 2},
		{"touch out/f{1..99999999999999999999}", 2},                                        // a bound too large to count
		{"touch out/" + strings.Repeat("{a,b}", 70), 2},                                    // more groups than are counted
		{"touch src/" + strings.Repeat("{x}", 64) + strings.Repeat("{a,b}", 13), 2},        // … with the first sixty-four adding nothing
		{"touch src/{a,b}{c,d}{e,f}{g,h}{i,j}{k,l}{m,n}{o,p}{q,r}{s,t}{u,v}{w,x}{y,z}", 2}, // 8192 words: not followed
	} {
		if got := judgeIn(root, c.cmd, "src/"); got != c.want {
			t.Errorf("%q: rc=%d, want %d", c.cmd, got, c.want)
		}
	}
}
