package bashscope

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zstevovich/claude-apd/guard/internal/paths"
)

// scratch makes a directory shaped like a session scratchpad
// (/tmp/claude-<uid>/<project>/<session>/scratchpad) and removes its own
// project directory afterwards — never the claude-<uid> directory itself.
func scratch(t *testing.T) string {
	t.Helper()
	top := fmt.Sprintf("/tmp/claude-%d", os.Getuid())
	proj := filepath.Join(top, fmt.Sprintf("apd-guard-test-%d-%s", os.Getpid(), strings.ReplaceAll(t.Name(), "/", "_")))
	sp := filepath.Join(proj, "session", "scratchpad")
	if err := os.MkdirAll(sp, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(proj) })
	r := paths.Real(sp)
	if !paths.IsScratchpad(r) {
		t.Fatalf("fixture is not a scratchpad: %s", r)
	}
	return r
}

type caller struct {
	name  string
	scope []string
	deny  bool
}

var (
	builder      = caller{"builder", []string{"src"}, false}
	reviewer     = caller{"reviewer", nil, true}
	orchestrator = caller{"orchestrator", nil, false}
	everyone     = []caller{builder, reviewer, orchestrator}
)

func opts(root, cwd, cmd string, c caller) Options {
	return Options{Command: cmd, ProjectDir: root, Cwd: cwd, Scope: c.scope, DenyAllWrites: c.deny, Home: filepath.Join(root, "home")}
}

func must(t *testing.T, err error) {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
}

// same: with the rule and without it the verdict is the same — the command is
// judged exactly as it was before the rule existed.
func same(t *testing.T, root, cwd string, who []caller, cmds ...string) {
	t.Helper()
	for _, c := range who {
		for _, cmd := range cmds {
			on := Judge(opts(root, cwd, cmd, c))
			off, _ := judge1(opts(root, cwd, cmd, c), true)
			if on.Code != off.Code {
				t.Errorf("%s in %s: %q with the rule, %q without\n  %s", c.name, cwd, on.Code, off.Code, cmd)
			}
		}
	}
}

// refused: the caller may not run it — and that is no change.
func refused(t *testing.T, root, cwd string, who []caller, cmds ...string) {
	t.Helper()
	for _, c := range who {
		for _, cmd := range cmds {
			if v := Judge(opts(root, cwd, cmd, c)); !v.Blocked() {
				t.Errorf("%s in %s: allowed\n  %s", c.name, cwd, cmd)
			}
		}
	}
	same(t, root, cwd, everyone, cmds...)
}

// The target of a redirection, or of mkdir / touch / tee, that is a scratchpad
// directory plus ONE component built around `$(basename …)` or `$(date +digits)`
// is placed there.
func TestNameInScratchpadAllowed(t *testing.T) {
	root, sp := project(t), scratch(t)
	must(t, os.MkdirAll(sp+"/have", 0o755))
	must(t, os.WriteFile(sp+"/have/p-old.txt", nil, 0o644))
	cases := []string{
		`S=` + sp + `; for t in src/a.php src/b*Test.php; do n=$(basename $t .php); echo x > $S/$n.txt 2>&1; done`,
		`for t in src/a.php; do echo x > ` + sp + `/base-$(basename $t .php).txt; done`,
		`t=src/a.php; echo x > ` + sp + `/base-$(basename ${t} .php).txt`,
		`echo x > "` + sp + `/pre-$(basename "$f")"`,
		`n="$(basename "$f" .php)"; echo x > ` + sp + `/have/p-$n.txt`,
		`D=` + sp + `/rv-$(date +%H%M); [ ! -e "$D" ] && mkdir -p "$D" && echo "$D"; date`,
		`D=` + sp + `/rv-$(date -u +%Y%m%d-%H%M%S); mkdir -p "$D" && echo x > "$D/out.txt"`,
		`cd ` + sp + ` && echo x > k-$(basename a.json .json).json 2>k.err`,
		`echo x > ` + sp + `/new/dir/p-$(basename "$f").txt`,
		`echo x > ` + sp + `/have/p-$(basename "$f").txt; echo y > ` + sp + `/have/q.txt; mkdir -p ` + sp + `/have/sub; touch ` + sp + `/have/t; echo z | tee ` + sp + `/have/u`,
		"echo x > " + sp + "/b-`basename \"$f\"`.txt",
		`echo x > ` + sp + `/a-$(basename "$f")-$(date +%s).log`,
		`touch "` + sp + `/t-$(basename "$f").txt"`,
		`mkdir -p ` + sp + `/m-$(date +%s)/sub`,
		`echo x | tee "` + sp + `/tee-$(basename "$f").log"`,
		`set -e; echo x > ` + sp + `/s-$(date +%s).txt`,
		`n=$(basename "$f"); (n=x; echo hi); echo x > ` + sp + `/sub-$n.txt`,
	}
	for _, c := range everyone {
		for _, cmd := range cases {
			if v := Judge(opts(root, root, cmd, c)); v.Blocked() {
				t.Errorf("%s: blocked (%s: %s)\n  %s", c.name, v.Code, v.Detail, cmd)
			}
		}
	}
	// what the rule changed: each of these was refused before it existed
	for _, cmd := range cases {
		if v, _ := judge1(opts(root, root, cmd, builder), true); !v.Blocked() {
			t.Errorf("allowed with the rule off — the row does not test the rule:\n  %s", cmd)
		}
	}
}

// Everything the rule does not cover is judged exactly as before.
func TestNameRuleBounds(t *testing.T) {
	root, sp := project(t), scratch(t)
	out := root + "/out/victim"
	must(t, os.MkdirAll(sp+"/d", 0o755))
	must(t, os.MkdirAll(sp+"/real-1", 0o755))
	must(t, os.MkdirAll(sp+"/q-", 0o755))
	must(t, os.MkdirAll(sp+"/g1", 0o755))
	must(t, os.Symlink(out, sp+"/d/p-evil.txt"))
	must(t, os.Symlink(out, sp+"/d/W-Evil.LOG"))
	must(t, os.Symlink(root+"/out", sp+"/rv-9"))
	must(t, os.Symlink(out, sp+"/real-1/out.txt"))
	must(t, os.Symlink(out, sp+"/q-/.txt"))
	must(t, os.Symlink(out, sp+"/dangling-1"))
	must(t, os.WriteFile(sp+"/afile", nil, 0o644))
	refused(t, root, root, []caller{builder, reviewer},
		// not a name
		`echo x > `+sp+`/p-$(cat f).txt`,
		`echo x > `+sp+`/p-$(basename a; echo ../x).txt`,
		`echo x > `+sp+`/p-$(basename a | tr a /).txt`,
		`echo x > `+sp+`/p-$(LC_ALL=C basename a).txt`,
		`echo x > `+sp+`/p-$(basename a 2>/dev/null).txt`,
		`echo x > `+sp+`/p-$(dirname a).txt`,
		`echo x > `+sp+`/p-$(date).txt`,
		`echo x > `+sp+`/p-$(date +%D).txt`,
		`echo x > `+sp+`/p-$(date +%H/%M).txt`,
		`echo x > `+sp+`/p-$(date +%e).txt`,
		`echo x > `+sp+`/p-$(date +..).txt`,
		`echo x > `+sp+`/p-$(date -r /etc/passwd +%s).txt`,
		`echo x > "`+sp+`/p-$(basename "a/b")"`,
		`echo x > `+sp+`/p-$n.txt`,
		`echo x > `+sp+`/p-$(basename a)-$x.txt`,
		`echo x > `+sp+`/$x/p-$(basename a).txt`,
		// basename with anything that may be an option or several operands
		`echo x > `+sp+`/p-$(basename).txt`,
		`echo x > `+sp+`/p-$(basename -a x /)x`,
		`echo x > `+sp+`/p-$(basename -az .. / .. / tmp /)x`,
		`echo x > `+sp+`/p-$(basename a b c).txt`,
		`echo x > `+sp+`/p-$(basename -- a).txt`,
		`echo x > `+sp+`/p-$(basename \-z).txt`,
		`echo x > `+sp+`/p-$(basename *).txt`,
		`echo x > `+sp+`/p-$(basename $t .php).txt`,
		`t='-az .. /'; echo x > `+sp+`/p-$(basename $t).txt`,
		`t=-z; echo x > `+sp+`/p-$(basename $t).txt`,
		`t='*'; echo x > `+sp+`/p-$(basename $t).txt`,
		`t=$(cat f); echo x > `+sp+`/p-$(basename $t).txt`,
		`for t in a -az; do echo x > `+sp+`/p-$(basename $t).txt; done`,
		`for t in $(ls); do echo x > `+sp+`/p-$(basename $t).txt; done`,
		`for t in a 'b c'; do echo x > `+sp+`/p-$(basename $t).txt; done`,
		`for t in a -z; do :; done; t=ok; echo x > `+sp+`/p-$(basename $t).txt`,
		`echo x > `+sp+`/p-$(basename ${t:-x}).txt`,
		`echo x > `+sp+`/p-$(basename $t$u).txt`,
		`t=a; echo x > `+sp+`/p-$(basename $t$u).txt`,
		`echo x > `+sp+`/p-$(basename $"a").txt`,
		// one basename in a component, and never alone
		`echo x > `+sp+`/$(basename ..)$(basename /)x`,
		`u=$(basename ..); s=$(basename /); echo x > `+sp+`/$u$s$u${s}x`,
		`mkdir -p `+sp+`/q; echo x > `+sp+`/q$(basename /)$(basename ..)$(basename /)$(basename ..)$(basename /)x`,
		`echo x > "`+sp+`/a$(basename "$p")b$(basename "$q")c"`,
		`echo x > `+sp+`/$(basename a)`,
		`echo x > `+sp+`/$(basename a)/x`,
		`echo x > `+sp+`/..$(basename a)/x`,
		`echo x > `+sp+`/.$(basename "$e")./x`,
		`n=$(basename a); echo x > `+sp+`/$n/../../../x`,
		// not in the scratchpad, or leaving it
		`echo x > out/p-$(basename a).txt`,
		`echo x > src/p-$(basename a).txt`,
		`echo x > src/$(basename a).zzz`,
		`echo x > out/$(basename a).zzz`,
		`echo x > /tmp/p-$(basename a).txt`,
		`echo x > `+sp+`/../p-$(basename a).txt`,
		`echo x > "`+sp+`/p-$(basename a)/../../x"`,
		`echo x > `+sp+`/d-$(date +%H)/p-$(basename a).txt`,
		`cd $(pwd) && echo x > p-$(basename a).txt`,
		`cd `+sp+` && cd $(pwd) && echo x > p-$(basename a).txt`,
		// the written part is the shell's to expand
		`echo x > `+sp+`/*/victim$(basename a)`,
		`echo x > `+sp+`/g?/p-$(basename a)`,
		`echo x > `+sp+`/p-$(basename a)*`,
		`echo x > `+sp+`/é-$(basename a).txt`,
		`echo x > "`+sp+`/a b-$(basename a).txt"`,
		`echo x > `+sp+`/afile/p-$(basename a).txt`,
		// a name the substitution can produce is a link out of the scratchpad
		`echo x > `+sp+`/d/p-$(basename a).txt`,
		`echo x > `+sp+`/d/w-$(basename a).log`,
		`mkdir -p `+sp+`/rv-$(date +%H)/x`,
		`D=`+sp+`/real-$(date +%H); echo x > "$D/out.txt"`,
		`echo x > `+sp+`/q-$(basename a).txt`,
		`echo x > `+sp+`/dangling-$(date +%s)`,
		// only a redirection, mkdir, touch and tee
		`cp src/a "`+sp+`/have/copy-$(basename "$f")"`,
		`ln -s `+root+`/out `+sp+`/o-$(date +%Y); echo x > `+sp+`/o-2026/x`,
		`ln -s `+root+`/out "`+sp+`/o-$(basename "$f")"`,
		`mv src/a `+sp+`/m-$(date +%s)`,
		`tar -xf a.tar -C `+sp+`/x-$(date +%s)`,
		`sed -i '' s/a/b/ `+sp+`/x-$(date +%s)`,
		`rm -rf `+sp+`/x-$(date +%s)`,
		// unquoted in an argument a basename may be several words, the rest stays on the last
		`touch `+sp+`/p-$(basename a).txt`,
		`touch `+sp+`/o-$(basename -a x /)tmp/evil`,
		`mkdir -p `+sp+`/o-$(basename a)/out/x`,
		`n=$(basename a); touch `+sp+`/p-$n.txt`,
		`n="$(basename "$f")"; touch `+sp+`/p-$n.txt`,
		`echo x | tee `+sp+`/o-$(basename a)/x`,
		// the same command can plant the link
		`ln -s `+out+` `+sp+`/n/p-a.txt; echo x > `+sp+`/n/p-$(basename a).txt`,
		`ln -s `+root+`/out `+sp+`/n; echo x > `+sp+`/n/p-$(basename a).txt`,
		`cp -P src/l `+sp+`/n/p-a.txt && echo x > `+sp+`/n/p-$(basename a).txt`,
		`mv src/l `+sp+`/n/ ; echo x > `+sp+`/n/p-$(basename a).txt`,
		`cp -RP src/dir `+sp+`/n; echo x > `+sp+`/n/sub/p-$(basename a).txt`,
		`sh -c "ln -s `+out+` `+sp+`/n/p-a.txt"; echo x > `+sp+`/n/p-$(basename a).txt`,
		`python3 -c 'print(1)'; echo x > `+sp+`/p-$(basename a).txt`,
		`php -r 'symlink("a","b");'; echo x > `+sp+`/p-$(basename a).txt`,
		"echo x > "+sp+"/p-$(basename a).txt\npython3 - arg <<'EOF'\nimport os\nEOF",
		"echo x > "+sp+"/p-$(basename a).txt\nperl - arg <<'EOF'\nsymlink 1, 2;\nEOF",
		// … or change what `basename` and `date` are, or how a word is split
		`PATH=`+sp+`/bin:$PATH; echo x > `+sp+`/p-$(basename a).txt`,
		`export P"A"TH=`+sp+`:/usr/bin; echo x > `+sp+`/p-$(basename a).txt`,
		`x=ATH; export P$x=`+sp+`; echo x > `+sp+`/p-$(basename a).txt`,
		`declare -n r=x; r=`+sp+`; echo x > `+sp+`/p-$(basename a).txt`,
		`command declare -n r=x; r=`+sp+`; echo x > `+sp+`/p-$(basename a).txt`,
		`command export P"A"TH=`+sp+`; echo x > `+sp+`/p-$(basename a).txt`,
		`read -r "$v" < f; echo x > `+sp+`/p-$(basename a).txt`,
		`printf -v "$v" %s x; echo x > `+sp+`/p-$(basename a).txt`,
		`: ${!v:=x}; echo x > `+sp+`/p-$(basename a).txt`,
		`IFS=1; mkdir -p `+sp+`/o-$(date +%s)/x`,
		`hash -p `+sp+`/evil basename; echo x > `+sp+`/p-$(basename a).txt`,
		`alias basename=evil; echo x > `+sp+`/p-$(basename a).txt`,
		"shopt -s expand_aliases\nBASH_ALIASES[basename]='echo a/../..;:'\necho x > "+sp+"/p-$(basename a)/y",
		`enable -f `+sp+`/b.so basename; echo x > `+sp+`/p-$(basename a).txt`,
		`trap 'basename() { echo a/../..; }' DEBUG; echo x > `+sp+`/p-$(basename a).txt`,
		`. `+sp+`/defs.sh; echo x > `+sp+`/p-$(basename a).txt`,
		`source `+sp+`/defs.sh; echo x > `+sp+`/p-$(basename a).txt`,
		`eval "$defs"; echo x > `+sp+`/p-$(basename a).txt`,
		`$run; echo x > `+sp+`/p-$(basename a).txt`,
		`$(echo hash) -p `+sp+`/evil basename; echo x > `+sp+`/p-$(basename a).txt`,
		`c=hash; $c -p `+sp+`/evil basename; echo x > `+sp+`/p-$(basename a).txt`,
		`command hash -p `+sp+`/evil basename; echo x > `+sp+`/p-$(basename a).txt`,
		`eval 'basename() { echo ../../x; }'; echo x > `+sp+`/p-$(basename a).txt`,
		`eval 'hash -p `+sp+`/evil basename'; echo x > `+sp+`/p-$(basename a).txt`,
		`basename() { echo ../../x; }; echo x > `+sp+`/p-$(basename a).txt`,
		`date() { echo ../../x; }; echo x > `+sp+`/p-$(date +%s).txt`,
		`for i in 1 2; do echo x > `+sp+`/p-$(basename a).txt; basename() { echo ../../x; }; done`,
		`f() { basename() { echo ../x; }; }; f; echo x > `+sp+`/p-$(basename a).txt`,
		// the marked value of a variable is its value only while nothing else has written it
		`n=$(basename a); n=/../../etc/x; echo x > `+sp+`/p-$n`,
		`(n=$(basename a)); echo x > `+sp+`/p-$n.txt`,
		`n=$(basename a); if x; then f() { :; }; fi; f; echo x > `+sp+`/p-$n.txt`,
		`n=/../../; n+=$(basename a); echo x > `+sp+`/p-$n.txt`,
		`n+=$(basename a); echo x > `+sp+`/p-$n.txt`,
		`f() { echo x > `+sp+`/p-$V.txt; }; V=$(basename a) f`,
		`for f in $(basename a); do echo x > `+sp+`/p-$f.txt; done`,
		`n=(/../../x $(basename a)); echo x > `+sp+`/p-$n.txt`,
		`readonly n=/../../x; n=$(basename a); echo x > `+sp+`/p-$n.txt`,
		`n=/../../x; readonly n; n=$(basename a); echo x > `+sp+`/p-$n.txt`,
		`n=/../../x; declare -r n; n=$(basename a); echo x > `+sp+`/p-$n.txt`,
		`n=/../../x; command readonly n; n=$(basename a); echo x > `+sp+`/p-$n.txt`,
		`n=$(basename a); read -r n < f; echo x > `+sp+`/p-$n.txt`,
		`n=/../../x; if c; then n=$(basename a); fi; echo x > `+sp+`/p-$n.txt`,
		`n=/../../x; n=$(basename a); echo x > `+sp+`/p-$n.txt`,
		`n=$(basename "$e"); : ${n:=/../../x}; echo x > `+sp+`/p-$n.txt`,
		`n=$(basename "$e"); : ${n=/../../x}; echo x > `+sp+`/p-$n.txt`,
		`n=$(basename a); select n in /../../x; do break; done; echo x > `+sp+`/p-$n.txt`,
		// a mark never reaches text that is read again as a command
		`sh -c touch\ `+sp+`/p-$(basename a)`,
		`eval touch `+sp+`/p-$(basename a)`,
		`sh -c echo\ x\ \>\ `+sp+`/p-$(basename a)`,
		`eval echo x \> `+sp+`/p-$(basename a)`,
	)
}

// What the first cut of the rule changed without meaning to: a mark is not part
// of any word a rule other than the name rule reads.
func TestNameMarksLeaveEverythingElseAlone(t *testing.T) {
	root, sp := project(t), scratch(t)
	// a substitution followed by letters was read as a variable of that name
	same(t, root, root, everyone,
		`OUT=src/gen; mkdir -p $OUT && echo x > $OUT/$(date +%s)OUT.log`,
		`S=src; mkdir -p $(date +%Y)S`,
		`cd src && echo x > $(basename a)PWD/x`,
		`HOME=src; echo x > $(date +%s)HOME/x`,
		`cd $(basename a)OUT && echo x > y`,
		`for f in $(basename a)X; do echo x > $f; done`,
		`x=$(date +%s)OUT; echo x > $x`,
		`OUT='echo hi > out/x'; bash <<< $(date +%s)OUT`,
		`f() { echo x > $V; }; OUT=src/y V=$(date +%s)OUT f`,
		`OUT=src/y; cat < $(date +%s)OUT > src/z`,
	)
	same(t, root, root+"/src", everyone,
		`T=src/a.php; cp $T $(basename $T)T`,
		`S=src; touch $(basename x)S`,
		`D=src; cp a.php $(date +%Y)D`,
	)
	// in command position it is what a bare `$(…)` there always was
	same(t, root, root, everyone,
		`$(basename x) arg`,
		`$(date +%s)`,
		`$(basename x) > `+sp+`/out.txt`,
		`n=$(basename x); $n arg`,
	)
	// the orchestrator inside the pipeline directory
	same(t, root, root+"/.apd/pipeline", everyone,
		`for f in *.md; do cp $f `+sp+`/$(basename $f).bak; done`,
		`tar -cf `+sp+`/snap-$(basename $PWD).tar .`,
		`ls | while read f; do cp $f `+sp+`/k-$(basename $f); done`,
		`for f in *; do cat $f | tee `+sp+`/$(basename $f).txt; done`,
		`touch `+sp+`/o-$(basename x)`,
	)
}

// The orchestrator's fence around the pipeline directory is where it was.
func TestNameRuleAndThePipelineFence(t *testing.T) {
	root, sp := project(t), scratch(t)
	must(t, os.Symlink(root+"/.apd/pipeline/verifier.done", sp+"/p-evil.txt"))
	same(t, root, root, everyone,
		`echo x > `+sp+`/p-$(basename a).txt`,
		`ln -s `+root+`/.apd/pipeline/verifier.done `+sp+`/n/p-a.txt; echo x > `+sp+`/n/p-$(basename a).txt`,
		`echo x > `+sp+`/$(basename ..)$(basename /)$(basename ..)$(basename /)proj$(basename /).apd$(basename /)pipeline$(basename /)spec-card.md`,
	)
}

// A caller whose every target is placed may READ the list of reviewed files —
// as the source of an input redirection or through cat; writing it, or naming
// it in any other way, is refused as before.
func TestReviewedFilesListRead(t *testing.T) {
	root, sp := project(t), scratch(t)
	must(t, os.WriteFile(root+"/.apd/pipeline/.reviewed-files", []byte("src/a\n"), 0o644))
	reads := []string{
		`while IFS= read -r f; do cmp -s "$f" "` + sp + `/og/$f" || echo D; done < .apd/pipeline/.reviewed-files; git status --porcelain > ` + sp + `/status.txt`,
		`mkdir -p ` + sp + `/rv && for f in $(cat .apd/pipeline/.reviewed-files); do shasum -a 256 "$f"; done > ` + sp + `/rv/sha.txt`,
		`wc -l < .apd/pipeline/.reviewed-files > ` + sp + `/n.txt; cat "` + root + `/.apd/pipeline/.reviewed-files" > ` + sp + `/list.txt`,
		`mkdir -p ` + sp + `/a; cat .apd/pipeline/.reviewed-files; cat .apd/pipeline/.reviewed-files | sort > ` + sp + `/a/s.txt`,
		`echo hi > ` + sp + `/x; sort <.apd/pipeline/.reviewed-files`,
		`echo hi > ` + sp + `/x; cat .apd/pipeline/.reviewed-files;cat .apd/pipeline/.reviewed-files > ` + sp + `/twice.txt`,
	}
	for _, c := range []caller{builder, reviewer} {
		for _, cmd := range reads {
			if v := Judge(opts(root, root, cmd, c)); v.Blocked() {
				t.Errorf("%s: blocked (%s: %s)\n  %s", c.name, v.Code, v.Detail, cmd)
			}
		}
	}
	// the orchestrator's unplaced targets pass, so its substring test stays
	for _, cmd := range reads[1:] {
		if v := Judge(opts(root, root, cmd, orchestrator)); v.Code != PipelineState {
			t.Errorf("orchestrator: %q, want %q\n  %s", v.Code, PipelineState, cmd)
		}
	}
	// any other way of naming the list, and any other name, keeps the substring test for every caller
	for _, c := range everyone {
		for _, cmd := range []string{
			`echo hi > ` + sp + `/x; cat .apd/pipeline/.reviewed-files.bak`,
			`echo hi > ` + sp + `/x; cat .apd/pipeline/.reviewed-files .apd/pipeline/spec-card.md`,
			`echo hi > ` + sp + `/x; cat .apd/pipeline/.reviewed-files/x`,
			`echo hi > ` + sp + `/x; cat .apd/pipeline/.reviewed-files-old`,
			`echo hi > ` + sp + `/x; cat src/a .apd/pipeline/.reviewed-files`,
			`echo hi > ` + sp + `/x; concat .apd/pipeline/.reviewed-files`,
			`echo hi > ` + sp + `/x; cat .apd/pipeline/.reviewed-files$x`,
			`echo hi > ` + sp + `/x; cat $x/.apd/pipeline/.reviewed-files`,
			`echo hi > ` + sp + `/x; cat .apd/pipeline/.reviewed-files*`,
			`awk '{print > ".apd/pipeline/.reviewed-files"}' src/a.php`,
			`cat src/a.php 2>/dev/null | sed -n 'w .apd/pipeline/.reviewed-files'`,
			`perl -e 'truncate(".apd/pipeline/.reviewed-files",0); print $x' > /dev/null`,
			`git add -A 2>/dev/null; git checkout .apd/pipeline/.reviewed-files`,
			`echo hi > ` + sp + `/x; gzip .apd/pipeline/.reviewed-files`,
			`echo hi > ` + sp + `/x; dos2unix .apd/pipeline/.reviewed-files`,
			`cp ` + root + `/.apd/pipeline/.reviewed-files ` + sp + `/list.txt`,
			`exec 3<> .apd/pipeline/.reviewed-files; echo x >&3`,
			`echo x > .apd/pipeline/.reviewed-files`,
			`echo x >> ` + root + `/.apd/pipeline/.reviewed-files`,
			`sed -i '' s/a/b/ .apd/pipeline/.reviewed-files`,
			`echo x > .APD/Pipeline/.reviewed-files`,
			`cat .apd/pipeline/.reviewed-files > /dev/null; echo x > .apd/pipeline/verifier.done`,
			`rm -f .apd/pipeline/.reviewed-files`,
		} {
			if v := Judge(opts(root, root, cmd, c)); v.Code != PipelineState {
				t.Errorf("%s: %q, want %q\n  %s", c.name, v.Code, PipelineState, cmd)
			}
		}
	}
	// read, and then acted on: what the parser cannot place is refused for a caller with a scope or with none
	for _, c := range []caller{builder, reviewer} {
		for _, cmd := range []string{
			`echo hi > ` + sp + `/x; xargs rm < .apd/pipeline/.reviewed-files`,
			`echo hi > ` + sp + `/x; while read -r f; do rm "$f"; done < .apd/pipeline/.reviewed-files`,
			`echo hi > ` + sp + `/x; eval "$(cat .apd/pipeline/.reviewed-files)"`,
			`d=$(dirname .apd/pipeline/.reviewed-files); touch $d/verifier.done`,
			`cat .apd/pipeline/.reviewed-files; cd .apd/pipeline && touch verifier.done`,
		} {
			if v := Judge(opts(root, root, cmd, c)); !v.Blocked() {
				t.Errorf("%s: allowed\n  %s", c.name, cmd)
			}
		}
	}
}
