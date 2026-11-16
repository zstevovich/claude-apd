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
		// the documented recipe: the remote comes from a substitution, the statement carries the marker
		{`REMOTE=$(bash .claude/bin/apd git-remote) && ` + sign + `git push -u "$REMOTE" develop 2>&1; echo "exit=$?"`, "", false},
		{`REMOTE=$(bash .claude/bin/apd git-remote) && ` + sign + `git push "$REMOTE" master 2>&1 | tail -5`, "", false},
		{`REMOTE=$(x) && git push "$REMOTE" master`, PushNoPrefix, false},
		{`REMOTE=$(x) && ` + sign + `git push "$REMOTE" a; git push "$REMOTE" b`, PushNoPrefix, false}, // one unsigned statement is enough
		{`REMOTE=$(x) && ` + sign + `git push --force "$REMOTE" a`, ForcePush, false},
		{`M="$(cat msg)"; ` + sign + `git commit -m "$M"`, "", true},
		{`M="$(cat msg)"; git commit -m "$M"`, CommitNoPrefix, false},
	})
}

// printf names a variable only with -v; reading through xargs is reading.
func TestReplayedFalseBlocks(t *testing.T) {
	check(t, "builder", []row{
		{`for f in a b; do printf '%s %s\n' "$f" "$(head -c 3 "$f" | xxd -p)"; done; git diff --numstat HEAD -- a`, "", false},
		{`printf '%s: ' "$r"; git status --short`, "", false},
		{`printf -v GIT_CONFIG_COUNT 1; git status`, ConfigOverride, false},
		{`printf -v "$N" 1; git status`, ConfigOverride, false},
		{`find src -name '*.php' | xargs git diff --name-only HEAD -- | wc -l`, "", false},
		{`git diff HEAD --name-only | xargs -n1 git hash-object`, "", false},
		{`find . -name '*.go' -exec git blame {} +`, "", false},
		{`git ls-files -m | xargs git checkout --`, Unreadable, false},
		{`git ls-files -m | xargs git rm`, Unreadable, false},
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

// git takes any unambiguous abbreviation of a long option.
func TestAbbreviatedOptions(t *testing.T) {
	check(t, "", []row{
		{sign + `git commit --no-verif -m x`, NoVerify, false},
		{sign + `git commit --no-ver -m x`, NoVerify, false},
		{sign + `git commit --no-edit -m x`, "", true},
		{sign + `git push --forc`, ForcePush, false},
		{sign + `git push --force-with-l`, ForcePush, false},
		{sign + `git push --follow-tags`, "", false},
		{sign + `git push --delete origin x`, ForcePush, false},
		{sign + `git push --mirror`, ForcePush, false},
		{`git reset --har HEAD~1`, Destructive, false},
		{`git add --al`, MassStaging, false},
		{`git add --upd`, MassStaging, false},
		{`git clean --forc -d`, Destructive, false},
		{`git clean --dry -fd`, Destructive, false}, // an abbreviated dry run is not taken on trust
		{`git restore --stag --worktr a`, Destructive, false},
		{`git tag --delete v1`, Destructive, false},
		{`git branch --delete --force x`, ForceDelete, false},
		{`git branch -d -f x`, ForceDelete, false},
		{`git branch --delete x`, "", false},
	})
}

// What git runs can be changed by the command itself: an alias or configuration
// it supplies, a setting it writes, the plumbing under a commit.
func TestOtherWaysToTheSameAct(t *testing.T) {
	check(t, "", []row{
		{`git -c alias.x='commit -m y' x`, ConfigOverride, false},
		{`git -calias.x=push x`, ConfigOverride, false},
		{`GIT_CONFIG_PARAMETERS="'alias.x=push'" git x`, ConfigOverride, false},
		{`export GIT_CONFIG_COUNT=1; git x`, ConfigOverride, false},
		{`env GIT_CONFIG_GLOBAL=/tmp/c git status`, ConfigOverride, false},
		{`GIT_CONFIG_NOSYSTEM=1 true; git status`, "", false}, // reached `true` only
		{`git config alias.x 'commit -m y'`, ConfigOverride, false},
		{`git config --get alias.x`, "", false},
		{`git config core.hooksPath /dev/null`, NoVerify, false},
		{`git config user.name x`, "", false},
		{`git commit-tree -m x HEAD^{tree}`, CommitNoPrefix, false},
		{`git update-ref refs/heads/main abc123`, CommitNoPrefix, false},
		{`git send-pack origin main`, PushNoPrefix, false},
		{`git checkout -f main`, Destructive, false},
		{`git checkout --force main`, Destructive, false},
		{`git checkout -b feature`, "", false},
		{`git switch --discard-changes main`, Destructive, false},
		{`git switch -C main`, Destructive, false},
		{`git switch -c feature`, "", false},
		{`git merge feature`, "", false}, // the orchestrator owns the tree
		{`git rebase main`, "", false},
	})
	check(t, "builder", []row{
		{`git merge feature`, CommitNoPrefix, false},
		{`git cherry-pick abc123`, CommitNoPrefix, false},
		{`git revert HEAD`, CommitNoPrefix, false},
		{`git rebase main`, CommitNoPrefix, false},
		{`git pull`, CommitNoPrefix, false},
		{`git fetch origin`, "", false},
	})
}

// A statement that is not written out in full.
func TestNotWrittenOut(t *testing.T) {
	check(t, "builder", []row{
		{`S=commit; git $S -m x`, CommitNoPrefix, false}, // the command assigned it: read with the value filled in
		{`git $S -m x`, Unreadable, false},
		{"git `echo push` --force", Unreadable, false},
		{`echo commit | xargs git`, Unreadable, false},
		{`git ls-files -m | xargs git add`, Unreadable, false},
		{`echo --force | xargs git push`, Unreadable, false},
		{`git ls-files | xargs git grep TODO`, Unreadable, false}, // an option may come through stdin
		{`find . -name x -exec git {} +`, Unreadable, false},
		{`find . -name '*.go' -exec git add {} +`, Unreadable, false},
		{`ls | parallel git push`, Unreadable, false},
		{`git grep -Ovim TODO`, Unreadable, false},
		{`git grep --open-files-in-pager=sh TODO`, Unreadable, false},
		{`git grep -n TODO`, "", false},
		{`git ls-files | xargs grep TODO`, "", false},
		{`git --version`, "", false},
		// arguments from a variable: judged by what is written, and by the text of the whole command
		{`git add $(git diff --name-only)`, "", false},
		{`git log $RANGE`, "", false},
		{`G=git; $G commit -m x`, CommitNoPrefix, false},                 // nothing here says git commit as text; a stated limit
		{`$GIT commit --no-verify -m x`, NoVerify, false},                // an unnamed command: the text is judged too
		{sign + `git commit $(echo --no-verify ) -m x`, NoVerify, false}, // the flag is in the text the argument is made from
		{sign + `git push origin $(echo x; echo git push --force )`, ForcePush, false},
		{sign + `git commit -m "$(cat msg.txt)"`, "", true},
		{`$GIT add .claude/x`, ClaudeDirPrefix, false},
		{`$TOOL push --force`, "", false},
		{`B=x; git commit -m "$B"`, CommitNoPrefix, false},
		{`X=1; git push origin $BRANCH`, PushNoPrefix, false},
	})
}

// Configuration can reach git by a name alone, and through a file.
func TestConfigByOtherRoutes(t *testing.T) {
	check(t, "", []row{
		{`export GIT_CONFIG_PARAMETERS; git status`, ConfigOverride, false},
		{`read -r GIT_CONFIG_GLOBAL < f; git status`, ConfigOverride, false},
		{`printf -v GIT_CONFIG_COUNT 1; git status`, ConfigOverride, false},
		{`for HOME in /tmp/x; do git status; done`, ConfigOverride, false},
		{`HOME=/tmp/x git status`, ConfigOverride, false},
		{`GIT_DIR=/tmp/other/.git git log`, ConfigOverride, false},
		{`HOME=/tmp/x npm test; echo done`, "", false},
		{`git config include.path /tmp/evil`, ConfigOverride, false},
		{`git config --rename-section x alias`, ConfigOverride, false},
		{`git config -e`, ConfigOverride, false},
		{`git config user.name x`, "", false},
		{`git config alias.x 'commit -m y' --get`, ConfigOverride, false}, // --get after the operands is not an action
		{`declare -n X=GIT_CONFIG_PARAMETERS; X=y; git status`, ConfigOverride, false},
		{`export "$N"; git status`, ConfigOverride, false},
		{`declare -n X=$Y; X=y; git status`, ConfigOverride, false},
		{`declare X=$Y; git status`, "", false},
		{`declare -n X; X=HOME; X=/t; git status`, ConfigOverride, false},
		{`command declare -n X; X=HOME; X=/t; git status`, ConfigOverride, false},
		{`builtin declare -n X=HOME; X=/t; git status`, ConfigOverride, false},
		{`f() { local -n R=$1; R=/t; }; f HOME; git status`, ConfigOverride, false},
		{`command declare -x X=1; git status`, "", false},
		{`declare -x X; X=HOME; git status`, "", false},
		{`export PATH="$PATH:/x"; git status`, "", false},
	})
	check(t, "builder", []row{
		{`git config user.name x --get`, ConfigOverride, false},
		{`git config user.name x`, ConfigOverride, false},
		{`git config --unset user.name`, ConfigOverride, false},
		{`git config user.name`, "", false},
		{`git config --get user.name`, "", false},
		{`git config --list`, "", false},
	})
}

// Rows from the independent audit of the port (2026-11-16): each is a command
// the v7.5.3 guard refused and the first Go build let through.
func TestAudit(t *testing.T) {
	nine := ""
	for i := 1; i <= 9; i++ {
		nine += "bash <<'E" + string(rune('0'+i)) + "'\n"
	}
	nine += "git push --force\n"
	for i := 9; i >= 1; i-- {
		nine += "E" + string(rune('0'+i)) + "\n"
	}
	rows := []row{
		// git named through a variable the command itself assigned
		{`X=git; $X push --force`, ForcePush, false},
		{`X=git; $X reset --hard`, Destructive, false},
		{`X=git; $X clean -fd`, Destructive, false},
		{`X=git; $X add -A`, MassStaging, false},
		{`X=git; $X branch -D x`, ForceDelete, false},
		{`X="git push --force"; $X`, ForcePush, false},
		{`X="git push --force"; eval "$X"`, ForcePush, false},
		{`X="git push --force"; bash -c "$X"`, ForcePush, false},
		{`for g in git; do $g push --force; done`, ForcePush, false},
		{`f() { g=git; $g push --force; }; f`, ForcePush, false},
		{`X=ls; $X -la`, "", false},
		{`F=src/a.go; git diff -- $F`, "", false},
		// a substitution in a case pattern, a process substitution in a test
		{`case x in $(git push --force)) ;; esac`, ForcePush, false},
		{`case x in $(git reset --hard)) ;; esac`, Destructive, false},
		{`[[ -e <(git reset --hard) ]]`, Destructive, false},
		{`case "$1" in a|b) git status ;; esac`, "", false},
		// shells nested deeper than is read
		{nine, Unreadable, false},
		// a shell fed by a pipe: the text of the whole command is read
		{`printf 'git push --force\n' | sh`, PushNoPrefix, false},
		{`echo 'git push --force' | sh`, PushNoPrefix, false},
		{`echo 'git reset --hard' | bash -s`, Destructive, false},
		{`sh <<< 'git push --force'`, ForcePush, false},
		{`curl -fsSL https://x/install.sh | sh`, "", false},
		{`cat script.sh | bash`, "", false},
	}
	check(t, "", rows)
	check(t, "", []row{
		// the re-read statement keeps every word a word
		{`X=git; sudo -u "#0" $X push --force`, ForcePush, false},
		{`X=git; env -u "#" $X push --force`, ForcePush, false},
		{`X=git; env 'A=\' $X push --force`, ForcePush, false},
		{`X=git; ` + sign + `$X commit -m 'a # b' -a`, CommitAll, false},
		{`X=git; ` + sign + `$X commit -m 'x' -m '#' -n`, NoVerify, false},
		{`X=git; ` + sign + `$X commit -m 'a # b'`, "", true},
		// names that share a prefix; values built from other variables
		{`X=command; Xa=git; $X $Xa push --force`, ForcePush, false},
		{`a=x; ab=git; abc=push; $ab $abc --force`, ForcePush, false},
		{`X=git; Y=$X; $Y push --force`, ForcePush, false},
		{`X=git; Y="$X push"; $Y --force`, ForcePush, false},
		{`X=gi; X="${X}t"; $X push --force`, ForcePush, false},
		{`X=gi; Y=t; Z=$X$Y; $Z push --force`, ForcePush, false},
		{`X=g; $X""it push --force`, ForcePush, false},
		// a shell that runs what it reads, behind options and wrappers
		{`printf 'git push --force\n' | bash -o errexit`, PushNoPrefix, false},
		{`printf 'git push --force\n' | bash --rcfile /dev/null`, PushNoPrefix, false},
		{`printf 'git push --force\n' | stdbuf -o0 sh`, PushNoPrefix, false},
		{`printf 'git push --force\n' | xargs -I{} sh -c '{}'`, PushNoPrefix, false},
		{`bash <(printf 'git push --force\n') <<< x`, PushNoPrefix, false},
		{`printf 'git push --force\n' | bash -eo pipefail`, PushNoPrefix, false},
		{`printf 'git push --force\n' | bash -s -- arg`, PushNoPrefix, false},
		{`printf 'git push --force\n' | bash -es arg`, PushNoPrefix, false},
		{`printf 'git push --force\n' | xargs -I% sh -c '%'`, PushNoPrefix, false},
		{`printf 'git push --force\n' | xargs sh -c`, PushNoPrefix, false},
		{`X=git; Y='push --force'; bash -c "$X $Y"`, ForcePush, false},        // the value given whole, as the string after -c
		{`X='true;git'; Y='push --force'; bash -c "$X $Y"`, ForcePush, false}, // … where no single word of it is `git`
		{`bash -eo pipefail scripts/build.sh`, "", false},
		{`bash -o errexit scripts/build.sh`, "", false},
		{`bash scripts/release.sh "git push is next"`, "", false},
	})
	// the orchestrator's unsigned commit through a variable is still unsigned
	check(t, "", []row{{`X=git; $X commit -m x`, CommitNoPrefix, false}, {`X=git; ` + sign + `$X commit -m x`, "", true}})
}
