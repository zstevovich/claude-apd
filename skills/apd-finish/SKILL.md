---
name: apd-finish
description: Complete a development branch after APD pipeline. Verify tests, present merge/PR/keep/discard options, clean up.
effort: high
---

# APD Finish Branch

Use after the APD pipeline is complete (all steps passed, committed).

## Process

### Step 1: Verify

```bash
# Confirm pipeline completed and commit exists
git log --oneline -1
# Run tests one more time
bash .claude/scripts/verify-all.sh
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

## Within APD Pipeline

This skill runs AFTER the pipeline completes:

```
spec → builder → reviewer → verifier → commit → /apd-finish
```

The orchestrator invokes this skill to decide what happens with the committed work. The pipeline is already done — this is about integration.

## Rules

- **Never push without asking the user first**
- **Never force-push** (guard-git.sh blocks this anyway)
- **Always verify tests** before presenting options
- **PR body must include APD pipeline summary** — proves the work was reviewed
