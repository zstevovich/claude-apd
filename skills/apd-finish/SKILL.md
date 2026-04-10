---
name: apd-finish
description: Use when a successful APD pipeline commit has just completed and a push/PR/keep decision is needed. MANDATORY after every pipeline commit.
effort: high
---

# APD Finish

## The Iron Law

```
NO PUSH WITHOUT USER DECISION FIRST
```

The pipeline produced a commit. Now the user decides what happens with it. Never auto-push, never assume.

## Process

```dot
digraph finish {
    VERIFY [label="1. Verify\ntests pass"];
    OPTIONS [label="2. Present options"];
    PUSH [label="Push to remote"];
    PR [label="Push + Create PR"];
    KEEP [label="Keep local"];
    DISCARD [label="Discard (confirm)"];

    VERIFY -> OPTIONS;
    OPTIONS -> PUSH [label="1"];
    OPTIONS -> PR [label="2"];
    OPTIONS -> KEEP [label="3"];
    OPTIONS -> DISCARD [label="4"];
}
```

### Step 1: Verify

```bash
git log --oneline -1
bash "$(git rev-parse --show-toplevel)/.claude/scripts/verify-all.sh"
```

If tests fail → fix before proceeding.

### Step 2: Present Options

```
Pipeline complete. What would you like to do?

1. Push to remote (current branch)
2. Push and create a Pull Request
3. Keep local (I'll handle it)
4. Discard this work
```

### Step 3: Execute

#### Option 1: Push
```bash
APD_ORCHESTRATOR_COMMIT=1 git push -u origin <branch>
```

#### Option 2: Push + PR
```bash
APD_ORCHESTRATOR_COMMIT=1 git push -u origin <branch>
gh pr create --title "<feature>" --body "$(cat <<'EOF'
## Summary
<what changed>

## APD Pipeline
- Spec: approved
- Builder: <agents used>
- Reviewer: code-reviewer (opus/max) — verdict: PASS
- Verifier: all tests pass
- Pipeline duration: <time>

## Test Plan
- [ ] <verification steps>
EOF
)"
```

#### Option 3: Keep
Report branch name and status. Done.

#### Option 4: Discard
**Require typed confirmation:** "Type 'discard' to confirm."
```bash
git checkout main
git branch -D <branch>
```

## Red Flags — STOP

| Thought | Reality |
|---------|---------|
| "User probably wants me to push" | Never assume. Ask. |
| "I'll push and create PR in one go" | User might want to review locally first. |
| "Skip verification, we just ran tests" | Verify again. Something might have changed. |
| "Force push to fix the branch" | Never force push. guard-git blocks it anyway. |

## Rules

- **Never push without asking the user first**
- **Never force-push** (guard-git blocks this anyway)
- **Always verify tests** before presenting options
- **PR body must include APD pipeline summary** — proves the work was reviewed

## Integration

- **Called by:** Orchestrator after successful commit (workflow.md step 9)
- **Follows:** Pipeline complete → commit → `/apd-finish`
- **Terminal state:** User decision made (push/PR/keep/discard)
