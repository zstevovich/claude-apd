package specblind

import (
	"os"
	"path/filepath"
	"testing"
)

func fixture(t *testing.T) Options {
	t.Helper()
	d, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	for _, sub := range []string{".apd/pipeline", ".claude/memory", "src/app", "proj2"} {
		if err := os.MkdirAll(filepath.Join(d, sub), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(d+"/.apd/pipeline/spec-card.md", []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	for link, to := range map[string]string{"lnk": ".apd", "src/deep": "../.apd/pipeline", "src/rootlnk": "..", "src/ok": "app", "src/up": "../..", "src/etc": "/etc"} {
		if err := os.Symlink(to, d+"/"+link); err != nil {
			t.Fatal(err)
		}
	}
	return Options{AgentType: "adversarial-reviewer", ProjectDir: d, PipelineDir: d + "/.apd/pipeline",
		MemoryDir: d + "/.claude/memory", Home: "/home/u", Cwd: d}
}

func TestCaller(t *testing.T) {
	o := fixture(t)
	o.Command = "cat .apd/pipeline/spec-card.md"
	for agent, want := range map[string]bool{"adversarial-reviewer": true, "my-adversarial": true, "": false,
		"code-reviewer": false, "backend-builder": false} {
		o.AgentType = agent
		if got := Judge(o).Blocked(); got != want {
			t.Errorf("agent %q: blocked=%v, want %v", agent, got, want)
		}
	}
}

func TestFilePath(t *testing.T) {
	o := fixture(t)
	cases := []struct {
		tool, path string
		blocked    bool
	}{
		{"Read", ".apd/pipeline/spec-card.md", true},
		{"Read", ".apd/pipeline/implementation-plan.md", true},
		{"Read", ".apd/pipeline/.adversarial-rationale.md", true},
		{"Read", ".claude/memory/status.md", true},
		{"Glob", ".apd/pipeline", true},
		{"Glob", ".apd", true},
		{"Glob", ".claude", true},
		{"Grep", ".", true},
		{"Read", ".apd/pipeline/../pipeline/spec-card.md", true},
		{"Read", ".APD/Pipeline/spec-card.md", true},
		{"Read", "lnk/pipeline/spec-card.md", true},
		{"Read", "src/deep/spec-card.md", true},
		{"Glob", "lnk", true},
		{"Read", "src/ok/main.go", false},
		{"Read", ".apd/./pipeline/spec-card.md", true},
		{"Read", ".apd//pipeline/spec-card.md", true},
		{"Read", o.ProjectDir + "/.apd/pipeline/spec-card.md", true},
		{"Read", o.ProjectDir, true},
		{"Read", "missing/../../x", true}, // a `..` that survives resolution
		{"Grep", "", true},                // no path: the whole project
		{"Glob", "", true},
		{"Read", "", false},
		{"Read", ".apd/pipeline/.reviewed-files", false},
		{"Read", "src/app/main.go", false},
		{"Read", "src", false},
		{"Read", ".apd-notes.md", false},
		{"Read", ".claude/agents/x.md", false},
		{"Read", "/etc/hosts", false},
	}
	for _, c := range cases {
		o.Tool, o.FilePath = c.tool, c.path
		if got := Judge(o); got.Blocked() != c.blocked {
			t.Errorf("%s %q: got %+v, want blocked=%v", c.tool, c.path, got, c.blocked)
		}
	}
}

func TestBash(t *testing.T) {
	o := fixture(t)
	o.Tool = "Bash"
	deny := []string{
		// named
		"cat .apd/pipeline/spec-card.md",
		"cat .apd/pipeline/*",
		"grep -r 'Human gate' .apd/pipeline/",
		"git show HEAD:.apd/pipeline/spec-card.md",
		"git diff; cat .apd/pipeline/spec-card.md",
		"cat .claude/memory/status.md",
		"cat '.apd/pipeline/spec-card.md'",
		"cat .apd/./pipeline/spec-card.md",
		"cat .apd//pipeline/spec-card.md",
		"cat < .apd/pipeline/spec-card.md",
		"python3 - <<'EOF'\nprint(open('.apd/pipeline/spec-card.md').read())\nEOF",
		"cat src/../.claude/memory/status.md;.apd/pipeline/.reviewed-files",
		"python3 -c \"open('.claude/memory/status.md')\"",
		`php -r 'echo file_get_contents(".apd\/pipeline\/spec-card.md");'`,
		`php -r 'readfile( ".apd/pipeline/a/.apd/pipeline/.reviewed-files" );'`,
		"a=.apd; b=pipeline; cat < $a/$b/spec-card.md",
		"for d in src .; do grep -rn x $d; done",
		"echo \"$(find . -name x)\"",
		"eval \"find . -name x\"",
		"sh -c \"find . 'x\"",
		"cat <<EOF | script -q /dev/null sh\nfind . -name x\nEOF",
		"sh -s -- x <<EOF\nfind . -name x\nEOF",
		"python3 -c \"os.system('apd pipeline show spec')\"",
		"python3 -c \"open( '.apd/./pipeline/spec-card.md' )\"",
		"python3 -c \"open('.APD/pipeline/spec-card.md')\"",
		"a=x/.apd; b=pipeline; cat $a/$b/y",
		"a=x/.apd; b=pipeline; wc -l < $a/$b/y",
		"ln -s src /tmp/y",
		"env a=.apd b=pipeline sh -c 'cat $a/$b/spec-card.md'",
		"sudo a=.claude b=memory bash -c 'cat $a/$b/status.md'",
		"grep -rn foo src/up",
		`php -r 'echo file_get_contents(".APD\/pipeline\/spec-card.md");'`,
		"python3 -c \"x='.APD/pipeline/spec-card.md'>y\"",
		"cat $'x/.apd/pipe\\x6cine/y'",
		"wc -l < $'x/.apd/pipe\\x6cine/y'",
		"ls $PWD/.a*",
		`cp -r "$PWD"/.c* /tmp/x`,
		"cat $PWD/.a*/p*/s*",
		"source /dev/stdin <<EOF\nfind . -name x\nEOF",
		"git grep --no-exclude-standard foo",
		"git ls-files --ignored --exclude-standard",
		"rgrep foo",
		"docker build .",
		"python3 -c \"import os; print(os.listdir(os.getcwd()))\"",
		"python3 -c \"from pathlib import Path; print(list(Path('.').rglob('*')))\"",
		"python3 -c \"import subprocess; c=['find','.']; subprocess.run(c)\"",
		"awk 'BEGIN{while((\"find . -type f\" | getline f)>0) print f}'",
		". ./env.sh",
		"python3 -c \"open('.apd/pipeline/spec-card.md')#.apd/pipeline/.reviewed-files\"",
		"a=.apd; cat src/../$a/pipeline/x < src/../$a/pipeline/y",
		"a=.apd; cat x/$a/pipeline/y",
		"a=.apd; wc -l < src/../$a/pipeline/y",
		"for d in .apd .claude; do echo hi; done",
		"for f in .a*/p*/s*; do :; done",
		"a=.apd; b=$a/*; cat $b/*",
		"echo . | xargs cat",
		"git -c alias.x='!cat secret' x",
		"ls .c*",
		"dd if=.a*/p*/s*",
		// case: the same directory on a case-insensitive volume
		"cat .APD/pipeline/spec-card.md",
		"cat .Apd/Pipe*/spec-card.md",
		"ls .CLAUDE",
		"head .Claude/Memory/status.md",
		// through a symbolic link
		"cat lnk/pipeline/spec-card.md",
		"cat lnk/p*/s*",
		"cd lnk",
		"cat src/deep/spec-card.md",
		"cat src/deep/*",
		"wc -l < src/deep/spec-card.md",
		"grep -rn foo src/rootlnk",
		"ln -s .a* /tmp/x",
		// the dispatcher's aliases, spacing and quoting
		"apd pl show spec",
		"apd rp",
		"apd pipeline  show spec",
		"apd \"pipeline\" show spec",
		"p=pipeline; apd $p show spec",
		"apd pipeline stats",
		"apd pipeline $what",
		"bash plugins/apd/bin/core/pipeline-advance show spec",
		"bash plugins/apd/bin/core/pipeline-report",
		// sanctioned read paths
		"bash .claude/bin/apd pipeline show spec",
		"bash .claude/bin/apd report",
		"apd pipeline status",
		// what the shell makes of a word
		"cat .apd/pipe*/spec-card.md",
		"cat .apd/pipelin[e]/spec-card.md",
		"cat .apd/{pipeline,x}/spec-card.md",
		`cat .ap\d/pipeline/spec-card.md`,
		"cat .apd/pipe${x}line/spec-card.md",
		"cat .a*/p*/s*",
		"cat {.apd,.claude}/*/*",
		"d=.apd; cat $d/pipeline/spec-card.md",
		"head -5 .claude/mem*/session-log.md",
		"cat $'.apd/pipe\\x6cine/spec-card.md'",
		// loop lists and redirections
		"for f in .a*/p*/*; do cat $f; done",
		"for d in .apd .claude; do cat $d/*/*; done",
		"while read l; do echo $l; done < .a*/p*/s*",
		"cat <(echo x) .a*/p*/s*",
		// variables the command itself assigned
		"x=.a*/p*/s*; cat $x",
		"d=.apd; cat $d/*/*",
		"a=.apd; b=pipeline; cat $a/$b/spec-card.md",
		"d=.; grep -rn TODO $d",
		// ancestors
		"ls .apd",
		"cat .claude/*",
		"cd .apd && ls",
		"cd .a* && ls",
		// the project root
		"find . -name '*.md'",
		"grep -rn foo .",
		"grep -rn foo ./",
		"ls -R .",
		"env find . -name x",
		"sudo find . -name x",
		"FOO=1 find . -name x",
		"echo x;find . -name x",
		"wc -l $(find . -name '*.go')",
		"echo x\nfind . -name y",
		"command -p find . -name x",
		"exec -a NAME find . -name x",
		"grep -rn foo " + o.ProjectDir,
		"grep -rn foo $PWD",
		`rg foo "$(pwd)"`,
		"rg foo $(pwd)",
		`grep -rn foo "$CLAUDE_PROJECT_DIR"`,
		`grep -rn foo "$(git rev-parse --show-toplevel)"`,
		"grep -rn foo $(git rev-parse --show-toplevel)",
		"grep -rn foo src/..",
		"grep -rn foo ..",
		"grep -rn foo /",
		"grep -rn foo ~+",
		"find $(echo .) -name x",
		"$(which find) . -name x",
		"echo . | xargs find",
		"watch \"find . -name x\"",
		"sh -c 'find . -name x'",
		"cat <<EOF | sh\nfind . -name x\nEOF",
		"bash <<'EOF'\ngrep -rn foo .\nEOF",
		// no path at all
		"grep -rn foo",
		"rg foo",
		"find -name x",
		"ls -R",
		"tree",
		"du -sh",
		"fd spec",
		"rg --files",
		"grep -d recurse foo",
		// git past the index
		"git grep --no-index foo",
		"git grep --untracked foo",
		"git grep --untr foo",
		"git diff --no-index /dev/null x",
		"git add -f .",
		"git stage x",
		"git -c alias.x='!cat .apd/pipeline/spec-card.md' x",
		"git config alias.x status",
		"git update-index --add x",
		"git ls-files -o",
		"git ls-files --others",
		"git ls-files -i --exclude-standard",
		"git $sub x",
		"git diff /dev/null .a*/p*/s*",
		// settings
		"shopt -s dotglob; cat */pipeline/spec-card.md",
		"bash -O extglob -c 'echo x'",
		"GLOBIGNORE=x cat *",
		"GREP_OPTIONS=-r grep foo x",
		// programs that walk or shell out
		"python3 -c \"import os; [print(p) for p in os.walk('.')]\"",
		"python3 -c \"import subprocess; subprocess.run(['find', '.', '-name', 'x'])\"",
		"node -e \"require('fs').readdirSync('.', {recursive: true})\"",
		"sed -n '1e find . -name x' src/a",
	}
	allow := []string{
		"cat .apd/pipeline/.reviewed-files",
		"f=.apd/pipeline/.reviewed-files; cat $f",
		"git diff",
		"git diff .",
		"git diff HEAD~1 -- src",
		"git log --oneline -5",
		"git show HEAD:src/app/main.go",
		"git grep -n foo",
		"git ls-files",
		"git ls-files -o --exclude-standard",
		"git status --short",
		"cat src/app/main.go",
		"grep -rn foo src",
		"grep -rn '.*' src",
		"grep -n extglob src/x.sh",
		"grep -c . src/app/main.go",
		"find src -name '.*'",
		"find src -name '*.go' | xargs wc -l",
		"wc -l $(find src -name '*.go')",
		"cat $(git diff --name-only)",
		"ls src",
		"ls -la src/app",
		"rg foo src",
		"rg -g '*.go' foo src",
		"cd src && rg main app",
		"for f in src/*.go; do cat \"$f\"; done",
		"while read f; do cat \"$f\"; done < .apd/pipeline/.reviewed-files",
		"cat \"$f\"",
		"cat $a/$b",
		"ls $dir/*",
		"go test ./...",
		"rg --files src",
		"cat src/etc/hosts",
		"echo src/up",
		`cat "$PWD/.apd/pipeline/.reviewed-files"`,
		"ls $PWD/src/*",
		"cat nonexistent/file.txt",
		"rg foo -g '.a*' src",
		"echo .a*",
		"git log --oneline -- .claude",
		"cat src/ok/main.go",
		"ls src/ok",
		"apd doctor",
		"apd pipeline",
		"fd '.*' src",
		"cd src && ls",
		"grep -rn foo ~/other",
		"npm test",
		"echo done",
		"cat > /tmp/probe.php <<'EOF'\n<?php echo 'a' . 'b';\nEOF",
		"php -r \"echo 'a' . 'b';\"",
		"python3 -c \"import subprocess; subprocess.run(['pytest', '.'])\"",
		"cat ../shared/config.json",
		"grep -rn foo ../shared",
		"jq '.[] | .name' package.json",
		"awk '{print $1}' src/app/main.go",
		"sed -n '1,20p' src/app/main.go",
		"cat /etc/hosts",
		"head -20 ~/notes.txt",
	}
	for _, c := range deny {
		o.Command = c
		if v := Judge(o); !v.Blocked() {
			t.Errorf("ALLOWED, want refused: %q", c)
		}
	}
	for _, c := range allow {
		o.Command = c
		if v := Judge(o); v.Blocked() {
			t.Errorf("REFUSED (%s | %s), want allowed: %q", v.Detail, v.What, c)
		}
	}
}

func TestHome(t *testing.T) {
	o := fixture(t)
	o.Home = filepath.Dir(o.ProjectDir)
	name := filepath.Base(o.ProjectDir)
	for c, want := range map[string]bool{
		"grep -rn foo ~/" + name:               true,
		"grep -rn foo $HOME/" + name:           true,
		"grep -rn foo ${HOME}/" + name:         true,
		"cat $HOME/" + name + "/.apd/Pipeline": true,
		"grep -rn foo $HOME":                   true, // an ancestor of the project
		"grep -rn foo $HOME/" + name + "/src":  false,
		"grep -rn foo $HOMEWORK/" + name:       false, // another variable
	} {
		o.Command = c
		if got := Judge(o); got.Blocked() != want {
			t.Errorf("%q: got %+v, want blocked=%v", c, got, want)
		}
	}
}

func TestCallDirectory(t *testing.T) {
	o := fixture(t)
	o.Cwd = o.ProjectDir + "/src"
	for c, want := range map[string]bool{"cat deep/spec-card.md": true, "cat app/main.go": false, "cat ok/main.go": false} {
		o.Command = c
		if got := Judge(o); got.Blocked() != want {
			t.Errorf("%q: got %+v, want blocked=%v", c, got, want)
		}
	}
}

func TestHomeVar(t *testing.T) {
	for a, want := range map[string]int{"$HOME": 5, "$HOME/x": 5, "${HOME}/x": 7, "$HOMEWORK/x": -1, "x$HOME": -1} {
		if got := homeVar(a); got != want {
			t.Errorf("homeVar(%q) = %d, want %d", a, got, want)
		}
	}
}

func TestUnreadable(t *testing.T) {
	o := fixture(t)
	deny := []string{
		"cat 'unclosed .",
		"find 'unclosed",
		"grep -r foo 'x",
		"git add 'x",
		"cat .a*/p*/s* 'x",
		"shopt -s dotglob 'x",
		"ls .apd 'x",
		"ls .APD 'x",
		"cat `echo .apd`/pipeline/x 'u",
	}
	allow := []string{"cat src/a 'x", "git diff . 'x", "echo 'x"}
	for _, c := range deny {
		o.Command = c
		if !Judge(o).Blocked() {
			t.Errorf("ALLOWED, want refused: %q", c)
		}
	}
	for _, c := range allow {
		o.Command = c
		if v := Judge(o); v.Blocked() {
			t.Errorf("REFUSED (%s), want allowed: %q", v.Detail, c)
		}
	}
}

func TestGlobReaches(t *testing.T) {
	const b = ".apd/pipeline"
	for tok, want := range map[string]string{
		".a*/p*/s*":             "full",
		".apd/pipe*":            "full",
		"../.apd/pipe*/x":       "full",
		".a*":                   "anc",
		".*":                    "anc",
		"*/pipeline/x":          "", // a leading wildcard does not match a dot name
		"src/*.go":              "",
		anyText:                 "", // no literal text: proves nothing
		anyText + "/" + anyText: "",
		anyText + "/pipeline/x": "full", // an expansion can supply the dot
		"src/.a*":               "",     // an ancestor only at the start
		".apd/[!p]*":            "",
		".apd/[op]ipeline":      "full",
	} {
		if got := globReaches(tok, b); got != want {
			t.Errorf("globReaches(%q) = %q, want %q", tok, got, want)
		}
	}
}
