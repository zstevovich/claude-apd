# APD Finish (Codex)

**Read this file when:** a pipeline cycle has completed successfully — all
four steps done, `apd_pipeline_state()` shows `next_step: "commit"`, and a
commit has been made. Run through this checklist BEFORE pushing, opening a
PR, or moving on to the next task.

## The Iron Law

```
NO PUSH WITHOUT USER DECISION FIRST
```

The pipeline produced a commit. The user — not you — decides what happens
next. Never auto-push, never assume.

## Process

```
1. Verify (tests pass from a clean state)
      ↓
2. Show pipeline report (what was done)
      ↓
3. Present 4 options and wait
      ↓
4. Execute the user's choice
```

### Step 1 — verify

Run the project's verifier one more time from a clean state to confirm
nothing slipped through:

```
apd_verify_step()   # runs .codex/bin/verify-all.sh
```

If it fails, stop — loop back into debug (`.apd/rules/debug.md`). Do NOT
present finish options on red tests.

### Step 2 — show what the pipeline did

Pull `apd_pipeline_state()` and summarize for the user:

- Task name (from spec)
- Which steps completed, timing if available
- Spec criteria count
- Adversarial outcome (total / accepted / dismissed) if present
- Reviewed files count

This is the user's chance to see the work before approving a push.

### Step 3 — present options

```
Pipeline complete. What would you like to do?

  1. Push to remote (current branch)
  2. Push and create a Pull Request
  3. Keep local (I'll handle it)
  4. Discard this work
```

Wait for the user's choice. Do not preemptively execute option 1.

### Step 4 — execute the choice

#### Option 1 — push

```bash
APD_ORCHESTRATOR_COMMIT=1 git push -u origin <branch>
```

(Codex does not yet ship a Git tool hook; run the push from a terminal
outside Codex — or have the user run it.)

#### Option 2 — push and open a PR

```bash
APD_ORCHESTRATOR_COMMIT=1 git push -u origin <branch>
gh pr create --title "<feature>" --body "$(cat <<'EOF'
## Summary
<what changed in one paragraph>

## APD Pipeline
- Runtime: Codex
- Spec: approved by user
- Builder: orchestrator (Codex inline)
- Reviewer: orchestrator (Codex inline)
- Adversarial: <total>/<accepted>/<dismissed> or "skipped"
- Verifier: all tests pass
- Duration: <time>

## Test plan
- [ ] <verification steps the reviewer should run>
EOF
)"
```

#### Option 3 — keep local

Print the branch name and current status. Stop. Let the user handle it.

#### Option 4 — discard

**Require typed confirmation:** ask the user to type `discard` before any
destructive action.

```bash
git checkout main        # or the branch they started from
git branch -D <branch>
```

## Red flags — STOP

| Thought | Reality |
|---------|---------|
| "User probably wants me to push" | Never assume. Ask. |
| "I'll push and create the PR in one go" | User might want to review locally first. |
| "Skip verification, we just ran tests" | Verify again. Something might have changed. |
| "Force push to fix the branch" | Never force push. APD blocks it anyway. |

## Rules

- Never push without user approval
- Never force-push (the destructive-git guard blocks it)
- Always verify tests before presenting options
- PR body MUST include the APD pipeline summary — proves the work was reviewed
