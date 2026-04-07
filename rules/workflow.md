# Agent Pipeline Development (APD) — Workflow

## HARD GATE — TECHNICALLY ENFORCED

**Every implementation MUST go through all steps: Spec → Builder → Reviewer → Verifier → only then commit.**

This is not just a documented rule — **hooks technically block commits** if steps are not completed.

### Mechanism: Pipeline Flag System

```
.claude/.pipeline/
├── spec.done        # Orchestrator creates after approved spec
├── builder.done     # Orchestrator creates after Builder
├── reviewer.done    # Orchestrator creates after Review
└── verifier.done    # Orchestrator creates after Verifier
```

- `guard-git.sh` → calls `pipeline-gate.sh` → checks that ALL 4 files exist
- If any is missing → **commit is BLOCKED**
- After commit → `pipeline-advance.sh reset` automatically deletes flags

### Commands

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh spec "Task name"
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh builder
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh reviewer
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh verifier
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh status
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh reset
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh rollback           # Roll back one step
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh stats
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh skip "Reason"  # Only for urgent hotfixes
```

### Hard rules
- NEVER skip the Reviewer step
- NEVER batch multiple phases without a review between each
- Speed is NOT an excuse for skipping steps
- This rule is ABSOLUTE and inviolable

## 1. Spec card before code

Before EVERY task, create a mini-spec:

```
## [Task name]
**Goal:** One sentence.
**Effort:** max | high
**Out of scope:** What we are NOT doing.
**Acceptance criteria:** List of conditions for "done".
**Affected modules:** Files/layers being changed.
**Risks:** What can go wrong.
**Rollback:** How to revert if it breaks.
**Human gate:** Whether approval is required (API changes, migrations, auth, deploy).
```

The spec is shared with the user BEFORE implementation.

## 2. Three agent roles

### Builder
- Implements code according to the spec
- Custom agents in `.claude/agents/`
- Max 3-4 edit operations per dispatch
- Clear file ownership

### Reviewer
- Only finds risks, bugs, omissions
- Does NOT suggest style changes outside scope
- Runs AUTOMATICALLY after every Builder

### Verifier
- Build + test + contract check
- Runs AFTER Reviewer, BEFORE commit

### Orchestrator
- Creates the spec card
- Dispatches Builders (in parallel where possible)
- Runs Reviewer and Verifier
- Only one who commits and pushes
- Only one who communicates with the user

## 3. Micro-tasks

- Each task: one functional change
- Max 3-4 edit operations per agent
- One agent = clear file ownership
- If a task requires >5 files, split into 2+ agents

## 4. Verification before "done"

Before EVERY commit:
- [ ] Build passes (0 errors)
- [ ] Tests pass (0 failures)
- [ ] Frontend type check passes (if there are frontend changes)
- [ ] Cross-layer contract check (if task involves >1 layer)
- [ ] Review findings applied

Before EVERY push to staging/production:
- [ ] All of the above
- [ ] User explicitly approved the push

## 5. Human gate

User MUST approve before:
- API changes (new endpoints, signature changes)
- Database migrations
- Auth/role logic
- Deploy to staging/production

## 6. Session memory update

After EVERY completed task, append to `.claude/memory/session-log.md`:

```markdown
## [YYYY-MM-DD] [Task name]
**Status:** Completed | Partial | Blocked
**What was done:** [1-2 sentences]
**Issues:** [What went wrong, or "No issues"]
**Guardrail that helped:** [Which mechanism caught a problem, or "N/A"]
**New rule:** [What we are adding to the workflow, or "None"]
```

- **Rotation:** `rotate-session-log.sh` automatically archives entries older than 10

## 7. Cross-layer verification

When a task involves backend + frontend/mobile:
1. Backend DTO/response model is the **source of truth**
2. For each field, map the type to the frontend equivalent
3. Nullable fields must be nullable on all layers
4. NEVER create frontend types from the specification — always read the backend DTO

## 8. Reasoning effort

| Effort | When | Examples |
|--------|------|----------|
| **max** | Decisions that are expensive to reverse | Planning, architecture, review, spec, security |
| **high** | Implementation with a clear spec | Builder coding, tests, refactoring |

- Orchestrator always runs at **max**
- Builder agents at **high**
- Reviewer and Verifier at **max**
