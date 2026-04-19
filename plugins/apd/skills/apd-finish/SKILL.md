---
name: apd-finish
description: Use after a successful APD pipeline commit on Codex — when apd_pipeline_state shows next_step='commit' and a commit was made. Verify tests from a clean state, show the pipeline report, present four options (push, push+PR, keep, discard), and execute only after the user picks.
---

# APD Finish (Codex)

**Use when:** the pipeline has closed — all four steps done,
`apd_pipeline_state()` reports `next_step: "commit"`, and you have just
committed. Run through this BEFORE push, PR, or moving to the next task.

## The Iron Law

```
NO PUSH WITHOUT USER DECISION FIRST
```

The pipeline produced a commit. The user — not you — decides what happens
next. Never auto-push, never assume.

## Process

### Step 1 — verify

Re-run the project verifier to confirm nothing slipped through:

```
apd_verify_step()   # runs .codex/bin/verify-all.sh
```

If it fails, stop — loop back into debug. Do NOT present finish options
on red tests.

### Step 2 — show what the pipeline did

Pull `apd_pipeline_state()` and summarize for the user:

- Task name (from spec)
- Which steps completed, timing if available
- Spec criteria count
- Adversarial outcome (total / accepted / dismissed) if present
- Reviewed files count

### Step 3 — present options

```
Pipeline complete. What would you like to do?

  1. Push to remote (current branch)
  2. Push and create a Pull Request
  3. Keep local (I'll handle it)
  4. Discard this work
```

Wait for the user's choice. Do not preemptively execute option 1.

### Step 4 — execute

#### Option 1 — push

```bash
APD_ORCHESTRATOR_COMMIT=1 git push -u origin <branch>
```

Codex does not yet ship a Git tool hook; run the push from a terminal
outside Codex, or have the user run it.

#### Option 2 — push and open a PR

```bash
APD_ORCHESTRATOR_COMMIT=1 git push -u origin <branch>
gh pr create --title "<feature>" --body "$(cat <<'EOF'
## Summary
<one-paragraph summary of the change>

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

Require typed confirmation: ask the user to type `discard` before any
destructive action.

```bash
git checkout <base-branch>
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
