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
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh init "Description"  # Initial setup (no review needed)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh skip "Reason"      # Only for urgent hotfixes
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

## 2. Four roles — strict model and effort enforcement

### Orchestrator (you — main session)
- **Model:** opus | **Effort:** max
- Creates the spec card and gets user approval
- **Dispatches Builder agents — NEVER implements code directly**
- Dispatches Reviewer after each Builder
- Runs Verifier before commit
- Only one who commits and pushes (`APD_ORCHESTRATOR_COMMIT=1`)
- Only one who communicates with the user
- **If you find yourself writing code: STOP. Dispatch an agent instead.**

### Builder (dispatched agent)
- **Model:** sonnet | **Effort:** high
- Implements code according to the spec
- Defined in `.claude/agents/` with scope guards
- Max 3-4 edit operations per dispatch
- Clear file ownership — no overlap between agents
- **Must not** commit, push, or modify files outside its scope

### Reviewer (dispatched agent)
- **Model:** opus | **Effort:** max
- Finds risks, bugs, omissions in Builder's work
- Does NOT suggest style changes outside scope
- Runs AUTOMATICALLY after every Builder — **never skip**
- Reports findings to orchestrator who decides action

### Verifier (script, not agent)
- Runs `verify-all.sh` (build + test)
- Triggered by `pipeline-advance.sh verifier`
- Blocks commit if build or tests fail

### Model and effort summary

| Role | Model | Effort | Why |
|------|-------|--------|-----|
| Orchestrator | opus | max | Decisions, planning, coordination — expensive to reverse |
| Builder | sonnet | high | Implementation following clear spec — fast, focused |
| Reviewer | opus | max | Finding bugs, security issues — must be thorough |
| Verifier | — | — | Script, not a model — runs build + test |

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

## 8. Model and effort discipline

**This is NOT optional. Every dispatch MUST specify the correct model and effort.**

| Role | Model | Effort | Dispatch example |
|------|-------|--------|-----------------|
| Orchestrator | opus | max | (main session — always opus max) |
| Builder | sonnet | high | `dispatch backend-builder` (model: sonnet, effort: high in frontmatter) |
| Reviewer | opus | max | `dispatch code-reviewer` (model: opus, effort: max in frontmatter) |

- **Never use sonnet for review** — it misses subtle bugs
- **Never use opus for building** — it's slower and not needed for spec-driven work
- **Never use effort: low or medium** — APD only uses high and max
