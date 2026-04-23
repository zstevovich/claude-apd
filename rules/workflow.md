# Agent Pipeline Development (APD) — Workflow

## THE FLOW — follow this EXACTLY for every task

```
1. RECEIVE TASK from user
   → If task is vague or complex → MANDATORY: /apd-brainstorm first
   ↓
2. ANALYZE & WRITE SPEC — create spec card with goal, scope, criteria, risks
   → bash .claude/bin/apd pipeline spec "Task name"
   ↓
3. PRESENT SPEC TO USER — wait for approval or correction
   → DO NOT proceed until user says "ok" / "approved" / "go ahead"
   → If user requests changes → update spec → present again
   ↓
4. WRITE IMPLEMENTATION PLAN
   → Analyze codebase, write .apd/pipeline/implementation-plan.md
   → List files to create/modify with concrete change descriptions
   → bash .claude/bin/apd pipeline builder validates plan exists before advancing
   ↓
5. DISPATCH BUILDER AGENT(S) — one agent per domain, max 3-4 edits each
   → Builder agents MUST use /apd-tdd skill for implementation
   → bash .claude/bin/apd pipeline builder (after agent completes)
   ↓
6. DISPATCH REVIEWER AGENT — opus/max, read-only, finds bugs
   → bash .claude/bin/apd pipeline reviewer (after reviewer completes)
   → If reviewer finds critical issues → dispatch builder to fix → re-review
   ↓
6b. DISPATCH ADVERSARIAL REVIEWER (Full mode only)
   → Dispatch adversarial-reviewer agent (sonnet/max, read-only, no spec context)
   → Agent sees only git diff + touched files, finds issues blind
   → Orchestrator evaluates findings: accept or dismiss each
   → Write ADVERSARIAL:total:accepted:dismissed to .apd/pipeline/.adversarial-summary
   → If accepted findings → fix via builder → re-review
   → Lean mode skips this step — see "Lean vs Full" below
   ↓
7. RUN VERIFIER — build + test
   → bash .claude/bin/apd pipeline verifier
   → If verifier FAILS → MANDATORY: /apd-debug before re-dispatching builder
   ↓
8. ONE COMMIT for the entire feature
   → APD_ORCHESTRATOR_COMMIT=1 git commit
   → Before the next task: bash .claude/bin/apd pipeline reset
     (archives metrics + agent history, writes session-log summary;
     skipping this causes telemetry loss)
   ↓
9. FINISH — /apd-finish for push/PR/keep decision
```

**Every step is mechanically enforced. You cannot skip ahead.**
**Do NOT use superpowers:subagent-driven-development or ask the user which approach to use. APD defines the approach — just follow the flow.**

### ONE FEATURE = ONE COMMIT

Do NOT commit after each micro-task. Accumulate all changes and commit
once at the end, after the verifier passes. The git history should read
like a feature log, not a step-by-step diary.

```
WRONG:                              RIGHT:
  abc123 Add migration                abc123 feat: add delete button for posts
  def456 Add validator
  ghi789 Add route
  jkl012 Add template
  mno345 Add JS
```

---

## HARD GATE — TECHNICALLY ENFORCED

**Every implementation MUST go through all steps: Spec → Builder → Reviewer → Verifier → only then commit.**

This is not just a documented rule — **hooks technically block commits** if steps are not completed.

### Mechanism: Pipeline Flag System

```
.apd/pipeline/
├── spec.done        # Orchestrator creates after approved spec
├── builder.done     # Orchestrator creates after Builder
├── reviewer.done    # Orchestrator creates after Review
└── verifier.done    # Orchestrator creates after Verifier
```

- `guard-git` → calls `pipeline-gate` → checks that ALL 4 files exist
- If any is missing → **commit is BLOCKED**
- After commit, before the next task → run `bash .claude/bin/apd pipeline reset` manually (archives metrics + agent history, writes session-log summary, then deletes flags)

### Commands

**Use the project shortcut** — never guess plugin paths:

```bash
bash .claude/bin/apd pipeline spec "Task name"
bash .claude/bin/apd pipeline builder
bash .claude/bin/apd pipeline reviewer
bash .claude/bin/apd pipeline verifier
bash .claude/bin/apd pipeline status
bash .claude/bin/apd pipeline reset
bash .claude/bin/apd pipeline rollback
bash .claude/bin/apd pipeline stats
```

### Hard rules
- NEVER skip the Reviewer step
- NEVER batch multiple phases without a review between each
- Speed is NOT an excuse for skipping steps
- This rule is ABSOLUTE and inviolable
- If a pipeline step fails, do NOT rollback code — fix the issue and retry. Builder work is preserved in the working tree.
- NEVER use superpowers: or feature-dev: agents for pipeline steps. Pipeline BLOCKS non-project agents. Use: `Agent({ subagent_type: "code-reviewer", prompt: "..." })`
- NEVER use SendMessage to continue a builder/reviewer agent. SendMessage does NOT trigger SubagentStart/Stop hooks — the agent dispatch will not be recorded and `apd pipeline` will BLOCK. Always dispatch a NEW agent with `Agent()`.
- When an agent hits maxTurns limit and stops mid-work: check what was done (`git diff`), then dispatch a NEW agent with specific instructions for the remaining work. Do NOT attempt to finish the work directly — you are the orchestrator, not the builder.
- Max 7 acceptance criteria per spec. Large features MUST be decomposed into smaller pipeline cycles.
- **NEVER write, edit, or create project source files** (code, templates, CSS, JS, tests, configs). You are the ORCHESTRATOR — you write ONLY pipeline files (spec-card.md, implementation-plan.md, .adversarial-summary) and memory files. ALL code changes go through dispatched Builder agents. `guard-orchestrator` mechanically blocks this — every failed attempt wastes tokens.
- **NEVER read code files after a reviewer finishes** to "verify" or "double-check" the review. Trust the reviewer's findings. If the reviewer missed something, dispatch the reviewer again — do not replicate its work.
- **DO verify review findings that cite an external standard** — API format, protocol spec, library contract, vendor docs — against the primary source (official documentation) before accept/dismiss. `WebFetch` or reading a checked-in spec file is NOT the same as re-reading the code under review. Reviewers are agents; they can have knowledge gaps and hallucinate. Evidence-based dismissal ("Postmark docs show `ContentID: cid:...` — finding is false positive, dismiss") is engineering; feeling-based dismissal ("I think it's fine") is negligence. Document the source in the dismissal so the audit trail is reviewable.

## 0. Lean vs Full mode

Every pipeline cycle runs in one of two modes. Pick at spec time:

- **Full** (default): spec → builder → reviewer → adversarial → verifier
  → commit. Use whenever the work touches a migration, auth or session
  handling, a public API or wire protocol, a security-sensitive path
  (input validation, crypto, secrets), or a cross-module refactor.
- **Lean**: spec → builder → reviewer → verifier → commit. Adversarial
  is skipped. Only available for a genuinely small, contained change —
  fewer than 5 files in scope AND none of the Full-only categories apply.

Default to Full. Pick Lean only when ALL of these are true: single narrow
change, no migration, no auth, no public-API change, no security surface,
no cross-module refactor. When in doubt, pick Full — adversarial is cheap
insurance against the regressions it catches.

### Opting into Lean

Add this line anywhere in `.apd/pipeline/spec-card.md`:

```
adversarial: skip — <one-sentence reason>
```

The reviewer step then advances straight to verifier without creating
`.adversarial-pending`. **Mechanical cap: the opt-out is only honored
when the spec has ≤ 2 `R*:` criteria.** A 3+ criterion spec is
substantial enough that adversarial stays required; the opt-out line is
ignored in that case. The cap is a deliberate nudge — if the spec
doesn't fit in 2 criteria, it's not a Lean task.

## 1. Spec card before code

Before EVERY task, create a mini-spec:

```
## [Task name]
**Goal:** One sentence.
**Effort:** max | high
**Out of scope:** What we are NOT doing.
**Acceptance criteria:**
- R1: [first condition for "done"]
- R2: [second condition]
- RN: [last condition]
**Affected modules:** Files/layers being changed.
**Risks:** What can go wrong.
**Rollback:** How to revert if it breaks.
**Human gate:** Whether approval is required (API changes, migrations, auth, deploy).
```

The spec is shared with the user BEFORE implementation.

### Spec persistence

The orchestrator MUST write the spec card to `.apd/pipeline/spec-card.md` before calling `bash .claude/bin/apd pipeline spec "Task name"`. This enables mechanical traceability verification.

## 2. Five roles — strict model and effort enforcement

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
- **Dispatch:** `Agent({ subagent_type: "code-reviewer", prompt: "Review..." })` — NEVER use superpowers:code-reviewer

### Adversarial Reviewer (dispatched agent)
- **Model:** sonnet | **Effort:** max
- Context-free — sees only code changes, not the spec or task
- Finds bugs that contextual reviewers miss by not knowing intent
- Findings are advisory — orchestrator decides what to act on
- Runs AFTER regular reviewer, BEFORE verifier
- Orchestrator tracks hit rate: accepted vs dismissed findings

### Verifier (script, not agent)
- Runs `verify-all.sh` (build + test)
- Triggered by `bash .claude/bin/apd pipeline verifier`
- Blocks commit if build or tests fail

### Model and effort summary

| Role | Model | Effort | Why |
|------|-------|--------|-----|
| Orchestrator | opus | max | Decisions, planning, coordination — expensive to reverse |
| Builder | sonnet | xhigh | Implementation following clear spec — deep reasoning for coding tasks |
| Reviewer | opus | max | Finding bugs, security issues — must be thorough |
| Adversarial Reviewer | sonnet | max | Fresh eyes, different model = different blind spots |
| Verifier | — | — | Script, not a model — runs build + test |

## 3. Micro-tasks

- Each task: one functional change
- Max 3-4 edit operations per agent
- One agent = clear file ownership
- If a task requires >5 files, split into 2+ agents

## 3b. Spec traceability

Builders MUST add `@trace R*` comments in test files for every acceptance criterion from `.apd/pipeline/spec-card.md`.

```
// Single requirement
// @trace R1

// Multiple requirements on one line
// @trace R2 R3
```

**Rules:**
- Each R* from spec-card.md must appear in at least one test file
- Use the comment syntax appropriate for the language (`//`, `#`, `--`, etc.)
- Markers in code files (non-test) are optional and informational
- `verify-trace` runs during the verifier step and blocks commit if any R* is missing test coverage

## 3c. Implementation plan

Before dispatching the builder, the orchestrator MUST write `.apd/pipeline/implementation-plan.md`. The plan bridges the gap between spec (what to build) and builder (how to build it).

### Format

```
## Implementation Plan: [Task name]

### Files to modify
- `path/to/file.ext` — description of what to change (1-2 sentences)
- `path/to/other.ext` — description of what to change

### Files to create
- `path/to/new-file.ext` — purpose and what it contains

### Agents
- backend-api
- database
- code-reviewer

### Notes
- Any relevant context the builder needs
```

**Rules:**
- List every file the builder will touch
- 1-2 sentences per file — enough context to avoid searching, not code snippets
- **`### Agents` section is mandatory** — list all project agents needed for this task
- `apd pipeline builder` warns if planned agents were not dispatched
- Orchestrator reads relevant code BEFORE writing the plan
- `apd pipeline builder` blocks if the plan does not exist

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

- **Rotation:** `rotate-session-log` automatically archives entries older than 10

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
| Builder | sonnet | xhigh | `dispatch backend-builder` (model: sonnet, effort: xhigh in frontmatter) |
| Reviewer | opus | max | `dispatch code-reviewer` (model: opus, effort: max in frontmatter) |
| Adversarial Reviewer | sonnet | max | `dispatch adversarial-reviewer` (model: sonnet, effort: max in frontmatter) |

- **Never use sonnet for review** — it misses subtle bugs (exception: adversarial reviewer uses sonnet intentionally for perspective diversity)
- **Never use opus for building** — it's slower and not needed for spec-driven work
- **Never use effort: low or medium** — APD uses high, xhigh (builder), and max
- **`effort: xhigh` on Sonnet 4.6** falls back to `high` automatically — it takes effect when Sonnet 4.7 is available. Forward-compatible configuration.

### MaxTurn sizing — counterintuitive but important

Raising `maxTurns` makes pipelines **faster**, not slower. When an agent hits the limit mid-work, the orchestrator dispatches a new agent — that agent re-reads the spec, plan, `.reviewed-files`, and source files from scratch, burning 10+ turns before doing new work. Context discontinuity between runs also produces test/implementation mismatches that the reviewer catches, forcing another fix cycle.

APD defaults (v4.7.13+):
- Builders (backend, frontend, mobile, database, devops, testing): **`maxTurns: 40`**
- Code reviewer: **`maxTurns: 30`**
- Adversarial reviewer: **`maxTurns: 30`**

- Raise per-project if you see recurring exhaust in `apd report`. Edit `.claude/agents/<name>.md` frontmatter directly — `apd init --quick` only bumps the exact legacy defaults (20/15), custom values are preserved.
- Real-world example: BambiProject runs builders at 60 and code-reviewer at 45, eliminated exhaust, dropped adversarial hit rate from 25 % to 0 % across two consecutive runs.
- **Do NOT lower maxTurns to "save tokens".** Lower values cause more re-dispatches, which cost MORE tokens and produce WORSE code.

## 9. Mandatory skills

These skills are NOT optional. They MUST be used at the specified points in the pipeline.

| Skill | When | Who | Trigger |
|-------|------|-----|---------|
| `/apd-brainstorm` | Before spec, when task is vague or complex | Orchestrator | User gives unclear/broad task |
| `/apd-tdd` | During implementation | Builder agents | Every builder dispatch |
| `/apd-debug` | When verifier fails or reviewer finds bugs | Orchestrator → Builder | Test failure, build failure, critical review finding |
| `/apd-finish` | After successful commit | Orchestrator | Pipeline completes and commit succeeds |

### Skill enforcement rules

- **`/apd-brainstorm`** — If the user's task description is more than one sentence, involves multiple components, or has ambiguous scope → you MUST invoke `/apd-brainstorm` before writing the spec. Do NOT skip this to save time.
- **`/apd-tdd`** — Every Builder agent MUST follow TDD: write failing test → implement → verify pass. The `/apd-tdd` skill defines the exact process. Builders that skip TDD produce untestable code.
- **`/apd-debug`** — When the verifier fails or the reviewer reports a critical issue, do NOT re-dispatch the builder with "fix the bug". FIRST invoke `/apd-debug` to systematically identify the root cause, THEN dispatch the builder with specific fix instructions.
- **`/apd-finish`** — After a successful commit, ALWAYS invoke `/apd-finish` to present the user with options: push, PR, keep local, or discard. Do NOT push without this step.

### Optional skills

| Skill | When |
|-------|------|
| `/apd-github` | If the project uses GitHub Projects for task tracking |
| `/apd-miro` | If the project uses a Miro board for visualization |
