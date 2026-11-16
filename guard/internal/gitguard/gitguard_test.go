package gitguard

import "testing"

type row struct {
	cmd    string
	want   string // the refusal code, "" = allowed
	commit bool   // a signed commit that still has to pass the gate
}

func check(t *testing.T, agent string, rows []row) {
	t.Helper()
	for _, c := range rows {
		v := Judge(Options{Command: c.cmd, AgentType: agent})
		if v.Code != c.want || v.Commit != c.commit {
			t.Errorf("%q [%s]: code=%q commit=%v, want %q %v", c.cmd, agent, v.Code, v.Commit, c.want, c.commit)
		}
	}
}

const sign = Marker + "=1 "

// Text that mentions git is not a git statement.
func TestDataIsNotAStatement(t *testing.T) {
	check(t, "builder", []row{
		{`grep -rn "git commit" src/`, "", false},
		{`git log | grep "git push --force"`, "", false},
		{`echo "run git reset --hard to undo"`, "", false},
		{`git log --grep=--no-verify`, "", false}, // not the word itself
		{`git fetch --no-verify`, NoVerify, false},
		{`git log --grep="x --no-verify y"`, "", false},
		{`cat <<EOF > notes.md
git commit -a
EOF`, "", false},
		{`git status && git diff --stat`, "", false},
	})
}

func TestCommit(t *testing.T) {
	check(t, "", []row{
		{`git commit -m x`, CommitNoPrefix, false},
		{sign + `git commit -m x`, "", true},
		{sign + `git commit -m "mentions --no-verify and -a"`, "", true},
		{sign + `git commit -am x`, CommitAll, false},
		{sign + `git commit --all -m x`, CommitAll, false},
		{sign + `git commit -ma`, "", true},   // -m takes the rest of the word as its value
		{sign + `git commit -m -a`, "", true}, // and the next word when it stands alone
		{sign + `git push -o --force origin main`, "", false},
		{sign + `git commit -n -m x`, NoVerify, false},
		{sign + `git commit -qn -m x`, NoVerify, false},
		{sign + `git commit --no-verify -m x`, NoVerify, false},
		{sign + `git -c core.hooksPath=/dev/null commit -m x`, NoVerify, false},
		{sign + `git -ccore.hookspath=/x commit -m x`, NoVerify, false},
		{sign + "git commit -m 'x\n\nCo-Authored-By: someone'", AISignature, false},
		{sign + `git -C sub commit -m x`, "", true},
		{`git add a b && git status --short && ` + sign + `git commit -m x`, "", true},
		{`git add a && git commit -m x # ` + sign, CommitNoPrefix, false}, // a comment signs nothing
		{`echo "` + sign + `" && git commit -m x`, CommitNoPrefix, false},
		{`sh -c "git commit -m x"`, CommitNoPrefix, false},
		{`sudo git commit -m x`, CommitNoPrefix, false},
		{`/usr/bin/git commit -m x`, CommitNoPrefix, false},
		{`eval 'git commit -m x'`, CommitNoPrefix, false},
		{`echo "$(git commit -m x)"`, CommitNoPrefix, false},
		{`env ` + sign + `git commit -m x`, "", true},
		{Marker + `=0 git commit -m x`, CommitNoPrefix, false},
		{`true; ` + Marker + `=yes git commit -m x`, CommitNoPrefix, false},
	})
}

func TestAdd(t *testing.T) {
	check(t, "", []row{
		{`git add src/a.go src/b.go`, "", false},
		{`git add src/*.go`, "", false},
		{`git add .`, MassStaging, false},
		{`git add -A`, MassStaging, false},
		{`git add --all`, MassStaging, false},
		{`git add -u`, MassStaging, false},
		{`git add -vA`, MassStaging, false},
		{`git add '*'`, MassStaging, false},
		{`git add :/`, MassStaging, false},
		{`git add .claude/settings.json`, ClaudeDirPrefix, false},
		{sign + `git add .claude/settings.json`, "", false},
		{`git add --chmod +x script.sh`, "", false},
	})
}

func TestPush(t *testing.T) {
	check(t, "", []row{
		{`git push`, PushNoPrefix, false},
		{sign + `git push origin main`, "", false},
		{sign + `git push --force`, ForcePush, false},
		{sign + `git push -f`, ForcePush, false},
		{sign + `git push -uf origin x`, ForcePush, false},
		{sign + `git push --force-with-lease=main`, ForcePush, false},
		{sign + `git push origin +main`, ForcePush, false},
		{sign + `git push -o ci.skip origin main`, "", false},
		{sign + `git push -of`, "", false}, // -o takes the rest of the word
		{`sudo -u me git push --force`, ForcePush, false},
	})
}

func TestDestructive(t *testing.T) {
	check(t, "", []row{
		{`git reset --hard HEAD~1`, Destructive, false},
		{`git reset --soft HEAD~1`, "", false},
		{`git clean -fd`, Destructive, false},
		{`git clean -n`, "", false},
		{`git clean -nfd`, "", false},
		{`git clean --dry-run -fd`, "", false},
		{`git checkout -- src/a.go`, Destructive, false},
		{`git checkout .`, Destructive, false},
		{`git checkout main`, "", false},
		{`git restore src/a.go`, Destructive, false},
		{`git restore --staged src/a.go`, "", false},
		{`git restore --staged --worktree src/a.go`, Destructive, false},
		{`git restore -SW src/a.go`, Destructive, false},
		{`git restore -S src/a.go`, "", false},
		{`git tag -d v1`, Destructive, false},
		{`git branch -D feature`, ForceDelete, false},
		{`git branch -d feature`, "", false},
		{`git stash drop`, Destructive, false},
		{`git stash clear`, Destructive, false},
	})
}

// The orchestrator owns the working tree; a pipeline agent may only look at the stash.
func TestStash(t *testing.T) {
	check(t, "", []row{{`git stash`, "", false}, {`git stash pop`, "", false}, {`git stash list`, "", false}})
	check(t, "builder", []row{
		{`git stash`, StashFromAgent, false},
		{`git stash push -m wip`, StashFromAgent, false},
		{`git stash pop`, StashFromAgent, false},
		{`git stash list`, "", false},
		{`git stash show -p`, "", false},
		{`git stash --help`, "", false},
		{`git stash show; echo "$(git stash)"`, StashFromAgent, false},
		{`git -C sub stash`, StashFromAgent, false},
	})
}

// A command the parser cannot read is judged by its text: it may refuse more, never less.
func TestUnreadable(t *testing.T) {
	check(t, "builder", []row{
		{`git commit -m "unclosed`, CommitNoPrefix, false},
		{`echo "unclosed`, "", false},
		{`git push --force "unclosed`, ForcePush, false},
		{`git stash "unclosed`, StashFromAgent, false},
	})
	check(t, "", []row{{sign + `git commit -m "unclosed`, "", true}})
}
