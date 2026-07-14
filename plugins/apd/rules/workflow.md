# Agent Pipeline Development (APD) — Workflow

## THE FLOW — follow this EXACTLY for every task

```
1. RECEIVE TASK from user
   → **MANDATORY load `/apd-pipeline-guide` skill BEFORE writing spec-card.md.**
     Unconditional, every new task, NO skip flag (v6.15). The guide is the APD
     operating manual: gate at each advance, plan **Implements:** header
     contract, adversarial rationale .md contract, common BLOCKs + recovery,
     `apd pipeline show` read path. It writes `.guide-marker`; the spec gate
     hard-BLOCKS without it. "The task is already clear" is NOT a reason to
     skip — the guide is not a brainstorm, it is the contract.
   → **If the task scope is vague** (broad, "improve X", multiple reasonable
     interpretations) → load `/apd-brainstorm` FIRST: interactive one-question-
     at-a-time clarification that converges on a user-approved design. Optional
     when scope is already aligned (1:1 mirror, fully specified task, approved
     informal design) — skipping brainstorm never skips the guide.
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
   → **Mandatory finalization clause in EVERY builder dispatch prompt:**
     "When the build passes AND the tests you wrote pass, STOP IMMEDIATELY.
     Do NOT re-verify. Do NOT search 'one more time' to confirm.
     Verification of completeness is the reviewer's job, not yours."
     (Counters the 2026-05-11 intra-dispatch overrun pattern: 1 builder,
     23 min, 15 min of post-success verification loop without code changes.
     `track-agent` SubagentStop will flag this via the v6.7.2 F2 telemetry,
     but the dispatch-prompt rule is the upstream fix.)
   → bash .claude/bin/apd pipeline builder (after agent completes)
   → Safety net: if the gate BLOCKs "no Builder agent dispatched" but an agent
     DID run (CC SubagentStart/Stop hooks can silently not fire for background
     dispatches), the BLOCK now detects the on-disk transcripts and points you at
     the recovery — run `apd pipeline reconstruct-agents`, then re-run builder.
     (The gate never auto-applies transcripts — they're orchestrator-writable —
     so recovery stays an explicit, visible step.)
   ↓
6. DISPATCH REVIEWER AGENT — opus/max, read-only, finds bugs
   → bash .claude/bin/apd pipeline reviewer (after reviewer completes)
   → If reviewer finds critical issues → dispatch builder to fix → re-review
   ↓
6b. DISPATCH ADVERSARIAL REVIEWER (Full mode only)
   → ORDER GATE: only after reviewer.done is signed AND .adversarial-pending exists.
     Pipeline-advance reviewer writes the .adversarial-pending marker as the green light.
     Dispatching adversarial-reviewer earlier is mechanically blocked (CC: track-agent
     hook exits 2; Codex: apd:apd_adversarial_pass refuses).
   → Dispatch adversarial-reviewer agent (sonnet/max, read-only, no spec context)
   → Agent sees only git diff + touched files, finds issues blind. Each finding
     gets a `Status:` field — `active` (real defect) or `self-dismissed`
     (reviewer concluded inline it's not actionable, with `Note:` reason).
   → Orchestrator processes each finding. Three dispositions — accept / dismiss / SPINOFF:
     - `active` in scope → accept (dispatch builder fix) or dismiss (with rationale).
     - `self-dismissed` → copy reviewer's Note as rationale text.
     - **spinoff** — real BUT out of THIS task's declared scope (especially the
       ones that surface AT the cycle cap). Do NOT expand the task and do NOT
       `apd toggle off` to cram it in. Record a follow-up task seed and continue
       in scope: `bash .claude/bin/apd pipeline spinoff-finding <id> "<why out of scope + follow-up>"`.
       In `.adversarial-rationale.md` a spun-off finding is still `**Status:** accepted`
       (it's real — counts in summary `A`); `spinoff-finding` is the deferral record,
       NOT a rationale status (don't invent a `spinoff` status — it BLOCKs at verifier).
       The spun-off finding becomes its own APD task (spec + fresh adversarial +
       red-green) — the full treatment a real (often rule-1) defect deserves.
       **If you ask the user what to do about an out-of-scope finding at the cap,
       list spinoff FIRST and recommend it.**
   → Write ADVERSARIAL:total:accepted:dismissed to .apd/pipeline/.adversarial-summary
     where `dismissed` = orchestrator-dismissed + reviewer-self-dismissed (sum kept
     in summary for backward compat; rationale file disambiguates).
   → **MANDATORY** — write .apd/pipeline/.adversarial-rationale.md BEFORE
     attempting verifier advance. ONE block per finding, T blocks total:
     ```
     ## Finding N — <one-line title>
     **Severity:** critical | important | minor
     **Status:** accepted | dismissed | reviewer-self-dismissed
     **Rationale:** <text; ≥40 chars required for dismissed/reviewer-self-dismissed>
     ```
     **Do NOT skip this file.** Verifier hard-BLOCKS without it (v7.1) and
     hard-BLOCKS again on the 100%-orchestrator-dismiss pattern (T≥3 && A==0 &&
     Do≥1, v7.6 — orchestrator must accept at least one finding OR reclassify
     to reviewer-self-dismissed with reviewer's Note inline). Common mistake:
     orchestrator finishes adversarial dispatch, jumps directly to verifier,
     hits v7.1 BLOCK. Saves 1-2 min by writing rationale BEFORE running verifier.
   → If accepted findings → fix via builder → re-review
   → Lean mode skips this step — see "Lean vs Full" below
   ↓
6b. SUPERVISION (v6.30 — ONLY when the model profile has a supervisor row; v1: eco, Full mode)
   → AFTER all adversarial findings are triaged and fixed — the supervisor judges
     the FINAL diff, not the pre-fix state.
   → Dispatch supervisor agent (frontier model, memory: none). Its scope is ONLY:
     R-criteria still met by the final diff / fix-of-findings collateral /
     Regression-surface claims vs diff / commit verdict. NOT a second bug hunt.
   → Write SUPERVISION:total:accepted:dismissed to .apd/pipeline/.supervision-summary
     (Write/Edit tool). If T>0: .apd/pipeline/.supervision-rationale.md — SAME
     per-finding contract as adversarial (Severity/Status/Rationale, spinoff
     disposition available). Accepted → builder fix → ONE re-check (cap: 2 completed passes; an exhausted dispatch doesn't count).
   → NO spec-card opt-out (by design). Ways out: reset, or switch profile BEFORE spec.
   → Rollout: verifier WARNS now; becomes a hard BLOCK in a future release.
   ↓
7. RUN VERIFIER — build + test
   → **Sanity check FIRST:** does `.apd/pipeline/.adversarial-rationale.md` exist
     with one `## Finding N` block per adversarial finding? If not, go back to
     step 6 — verifier will BLOCK otherwise (v7.1).
   → bash .claude/bin/apd pipeline verifier
   → SEVERITY GATE (v6.1 B2) — **DEPRECATED as of v6.9, will be removed in v7.0.**
     Blocks when adversarial dismissed-defect count (D in ADVERSARIAL:T:A:D)
     exceeds spec-card.md `adversarial: max_defects=N`. **Default = unlimited
     (no field).** Field continues to function in v6.9 for graceful transition
     (verifier gate + immutability check both active), but emits a deprecation
     warn + INFO entry to guard-audit.log on every spec advance.
     **DO NOT write `adversarial: max_defects=...` in new specs.** Rationale gate
     (v6.7) structurally covers misuse pattern (per-finding rationale ≥40 chars
     + 100%-Do hard-block + bulk-accept rationale validation). Empirical evidence
     (Test 33-min run 2026-05-22): `max_defects=0` triggered cascade od 3 guard
     block-a + 2 reset-a. v6.8 chain validated rationale gate as sufficient
     standalone enforcement — max_defects became redundant. v7.0 will remove
     the field parser entirely.
   → RATIONALE GATE (v6.7): blocks on missing/malformed .adversarial-rationale.md,
     status/A/D drift between summary and rationale, and the 100%-orchestrator
     dismissal pattern. Soft warns on rationale text <40 chars or lazy patterns
     (`ok`, `n/a`, `false positive`, etc.). Per-task opt-out:
     `adversarial: rationale_gate=off` in spec-card.md.
   → SUPERVISION GATE (v6.30): when the declared profile carries a supervisor row
     (v1: eco) and adversarial ran, the verifier checks .supervision-summary +
     .supervision-rationale.md (same structural contract as adversarial, plus a
     dispatch-backed check, a finality check (supervisor stop must be the last
     agent activity) and a 2-completed-passes churn cap). Currently WARN (rollout);
     flips to hard BLOCK in a future release. NO spec-card opt-out.
   → If verifier FAILS → MANDATORY: /apd-debug before re-dispatching builder
   ↓
8. ONE COMMIT for the entire feature
   → APD_ORCHESTRATOR_COMMIT=1 git commit
   → Before the next task: bash .claude/bin/apd pipeline reset [learning]
     (archives metrics + agent history, writes session-log summary;
     pass an optional learning string to populate "New rule"
     — defaults to "None"; skipping the reset causes telemetry loss)
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
- After commit, before the next task → run `bash .claude/bin/apd pipeline reset [learning]` manually (archives metrics + agent history, writes session-log summary; optional learning arg populates "New rule" entry, defaults to "None"; then deletes flags)

### Commands

**Use the project shortcut** — never guess plugin paths:

```bash
bash .claude/bin/apd pipeline spec "Task name"
bash .claude/bin/apd pipeline builder
bash .claude/bin/apd pipeline reviewer
bash .claude/bin/apd pipeline verifier
bash .claude/bin/apd pipeline status
bash .claude/bin/apd pipeline show [spec|plan|state]   # read-only state inspection
bash .claude/bin/apd pipeline reset
bash .claude/bin/apd pipeline rollback
bash .claude/bin/apd pipeline stats
```

### Inspecting pipeline state
To see what's in `.apd/pipeline/` (current phase, reviewed-files count, adversarial summary, rationale status, spec/plan), use `apd pipeline status` or `apd pipeline show`. **Do NOT `cat`/`ls` files under `.apd/pipeline/` directly — guard-bash-scope blocks bash access to protected pipeline state** (it cannot tell a read from a fabrication attempt). `apd pipeline show spec|plan` echoes your own spec-card/plan; `apd pipeline show state` prints a digest of the generated state.

### Hard rules
- NEVER skip the Reviewer step
- NEVER batch multiple phases without a review between each
- Speed is NOT an excuse for skipping steps
- This rule is ABSOLUTE and inviolable
- If a pipeline step fails, do NOT rollback code — fix the issue and retry. Builder work is preserved in the working tree.
- NEVER use superpowers: or feature-dev: agents for pipeline steps. Pipeline BLOCKS non-project agents. Use: `Agent({ subagent_type: "code-reviewer", prompt: "..." })`
- NEVER use SendMessage to continue a builder/reviewer agent. SendMessage does NOT trigger SubagentStart/Stop hooks — the agent dispatch will not be recorded and `apd pipeline` will BLOCK. Always dispatch a NEW agent with `Agent()`.
- When an agent stops mid-work (incomplete output): check what was done (`git diff`), then dispatch a NEW agent with specific instructions for the remaining work. Do NOT attempt to finish the work directly — you are the orchestrator, not the builder.
- Max 7 acceptance criteria per spec. Large features MUST be decomposed into smaller pipeline cycles.
- **NEVER write, edit, or create project source files** (code, templates, CSS, JS, tests, configs). You are the ORCHESTRATOR — you write ONLY pipeline files (spec-card.md, implementation-plan.md, .adversarial-summary) and memory files. ALL code changes go through dispatched Builder agents. `guard-orchestrator` mechanically blocks this — every failed attempt wastes tokens.
- **NEVER read code files after a reviewer finishes** to "verify" or "double-check" the review. Trust the reviewer's findings. If the reviewer missed something, dispatch the reviewer again — do not replicate its work.
- **DO verify review findings that cite an external standard** — API format, protocol spec, library contract, vendor docs — against the primary source (official documentation) before accept/dismiss. `WebFetch` or reading a checked-in spec file is NOT the same as re-reading the code under review. Reviewers are agents; they can have knowledge gaps and hallucinate. Evidence-based dismissal ("Postmark docs show `ContentID: cid:...` — finding is false positive, dismiss") is engineering; feeling-based dismissal ("I think it's fine") is negligence. Document the source in the dismissal so the audit trail is reviewable.

## 0a. Communication discipline

You are the orchestrator. Lines you write between tool calls reach the user — keep them sparse and concrete.

**Do NOT write at end-of-turn:**
- Lessons-learned bullet lists ("Plus I saved a feedback memo so future work doesn't repeat the mistake…" / "Key takeaways:")
- "What I did + what I'll do next" multi-bullet recaps after the work is already visible in the diff
- Self-narration of intent ("I'll wait for X then commit" — just do Y)
- Restating the user's command before executing it
- Multi-paragraph wrap-ups after a single fix

**Do write:**
- One-line state updates during long work ("Builder dispatched, waiting on stop event.")
- One-sentence end-of-turn — what changed and the next step. Nothing more.
- A question when you genuinely need a user decision

If you have a lesson worth keeping, write it to memory — do NOT narrate it in the conversation. Memory exists for that.

This rule applies to the orchestrator. Dispatched agents already output structured findings — see agent templates.

## 0. Lean vs Full mode

Not every task needs every gate. Pick the mode at spec time:

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

## 0b. Phase cycle caps

`pipeline-advance builder` and `pipeline-advance reviewer` each track how many times that phase has advanced for the current task and block runaway re-dispatch loops. Default cap = 2 per phase (one initial + one re-dispatch). Every `pipeline-advance <phase>` call costs a cycle, including re-advances after rollback — the counter increments per advance, not per agent dispatch. `pipeline-advance reset` wipes them. Spec re-advance for a new task also wipes them (different task = fresh budget).

Override per spec via line in `.apd/pipeline/spec-card.md`:

```
builder: max_cycles=3         # explicit higher cap with rationale
reviewer: max_cycles=3        # same — independent of builder
builder: max_cycles=unlimited # no cap (use only with strong reason)
```

When blocked, ways forward: STOP and review (is the plan complete? scope drift? same issue flagged repeatedly?), decompose into smaller tasks and reset, or raise the cap with explicit rationale via rollback + re-advance. If the blocker is an accepted finding that is genuinely **out of this task's scope**, do NOT raise the cap and do NOT `apd toggle off` — **spin it off** to a follow-up task and continue in scope: `bash .claude/bin/apd pipeline spinoff-finding <id> "<reason>"`. When you surface this choice to the user, spinoff is the first, recommended option.

### Polish mode

Polish iterations — typo fixes, copy tweaks, small UI polish — should NOT need re-dispatch. Mark them up front:

```
pipeline_mode: polish
```

This lowers both builder and reviewer default caps to 1 (no re-dispatch). Explicit `builder: max_cycles=N` / `reviewer: max_cycles=N` still take precedence. Distinct from the `adversarial: skip` opt-out below — polish mode runs the full builder → reviewer → adversarial → verifier sequence, just once.

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
**Regression surface:** What this task touches INDIRECTLY that must not regress (see below). 'none — <reason>' if self-contained.
**Risks:** What can go wrong.
**Rollback:** How to revert if it breaks.
**Human gate:** Whether approval is required (API changes, migrations, auth, deploy).
```

The spec is shared with the user BEFORE implementation.

### Regression surface (v6.17+)

`**Affected modules:**` is what you change on purpose. `**Regression surface:**` is the
*negative space* — the surrounding behaviour you touch only because the task reaches into a
shared module, which must stay intact. A clean adversarial pass means "this pass found
nothing", not "nothing broke"; the surface makes the must-not-break set explicit and
mechanically checkable (gate: `verify-regression-surface`).

```
**Regression surface:**
- RS1: profile address edit path — **Cover:** existing ProfileAddressTests
- RS2: GDPR consent read on order import — **Cover:** new ConsentUnaffectedTest
```

- Every `- RS<N>:` item needs a `**Cover:**` value: an existing test, `new <name>`, or `none: <reason>`.
- Touches no shared state? State it: `**Regression surface:** none — <reason>`. Declare it; do not leave it blank.
- **Human gate = Yes** (API / migration / auth / deploy) escalates: each RS item also needs
  `**Evidence:**` (≥40 chars) attesting the surrounding module's tests are green before AND
  after — e.g. `**Evidence:** ProfileSuite green before+after, 14 tests unchanged`. The gate
  checks the attestation is present; the builder runs the tests.
- Mode: `regression_gate: strict|warn|off` in spec-card.md (default `warn`; `off` is ignored
  on a Human-gate path — the sensitive path cannot opt out).

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

**MANDATORY** — every `### Section` MUST start with `**Implements:** R<N>, R<M>` (or `**Implements:** none` for scaffolding sections like Files to modify / Files to create / Agents / Notes). `verify-plan-spec` strict mode (v6.8.1+ default) hard-BLOCKS `apd pipeline builder` otherwise. Common mistake: write plan without **Implements:** headers → BLOCK → go back and add. Saves 60s by writing headers from the start.

### Format

```
## Implementation Plan: [Task name]

### Files to modify
**Implements:** none

- `path/to/file.ext` — description of what to change (1-2 sentences)
- `path/to/other.ext` — description of what to change

### Files to create
**Implements:** none

- `path/to/new-file.ext` — purpose and what it contains

### Backend
**Implements:** R1, R3

- `src/api/...` — endpoint changes

### Frontend
**Implements:** R2, R4

- `src/ui/...` — view changes

### Agents
**Implements:** none

- backend-api
- frontend-react
- code-reviewer

### Notes
**Implements:** none

- Any relevant context the builder needs
```

**Rules:**
- List every file the builder will touch
- 1-2 sentences per file — enough context to avoid searching, not code snippets
- **`### Agents` section is mandatory** — list all project agents needed for this task
- `apd pipeline builder` warns if planned agents were not dispatched
- Orchestrator reads relevant code BEFORE writing the plan
- `apd pipeline builder` blocks if the plan does not exist
- **`**Implements:**` header is mandatory on EVERY `### Section`** (v6.8.0+) — **NO RESERVED NAMES**. Declare which `R*` criteria from spec-card.md the section implements (`**Implements:** R1, R3`), or set to `none` for scaffolding sections. **The rule is uniform** — applies to functional sections (Backend, Frontend, Database, Tests) AND scaffolding (Files to modify, Files to create, Agents, Notes, Documentation). Empirical evidence (v6.8.7): orchestrator-i generalizuju iz format primera asymmetric — naucio za Files-to-mod/create ali zaboravio za Agents/Notes → BLOCK. Treat EVERY `###` section the same way: declare R-ids OR `none`.
- `verify-plan-spec` enforces bidirectional consistency: every spec `R*` must be referenced by ≥1 section; every section must have a valid `**Implements:**`. Mode is read from spec-card.md `plan_consistency_gate: strict|warn|off`. v6.8.0 default: `warn` (issues emit WARN, no block). v6.8.1+ default: `strict` (BLOCK on missing/unknown R-ids). Opt-out: `plan_consistency_gate: off` in spec-card.md.

## 3d. Platform portability (macOS/BSD vs Linux)

You are most likely on **macOS (Darwin, BSD userland)**, NOT Linux. GNU/Linux-isms fail here — often **silently** (a backgrounded `timeout` that never starts, an empty `sed -i` edit). `guard-bash-portability` hard-blocks the worst on macOS; know them up front. Run `apd env` for the full table.

| GNU/Linux | macOS/BSD |
|---|---|
| `timeout N cmd` | `gtimeout` (brew coreutils), or `( cmd & p=$!; sleep N; kill $p 2>/dev/null )` |
| `tac` / `nproc` | `tail -r` / `sysctl -n hw.ncpu` |
| `date -d` / `stat -c` | `date -v` or `date -j -f` / `stat -f` |
| `grep -P` / `readlink -f` | `grep -E` or `perl -ne` / `realpath` |
| `find … -printf` | `find … -exec stat -f …` |
| `sed -i 's/…'` | `sed -i '' 's/…'` (empty backup arg REQUIRED) |

**Never pipe the build/verifier through `head`/`tail`.** The pipeline's exit code is the *tail's*, not the command's — a real failure is masked as success — and you lose the output. Capture to a file and read it; use `set -o pipefail`. When something looks stuck, poll the pipeline's own signal (`.done` files / `apd pipeline status`), don't eyeball hidden output and re-run blindly.

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

### Agent turn budget (there is no `maxTurns` knob)

The `maxTurns` frontmatter field is a **no-op** for CC subagents (controlled test 2026-07-09: a subagent with `maxTurns: 3` ran 34 turns and finished; only the CLI `--max-turns` main-loop flag binds, which APD never sets). Subagents run until they finish — there is no turn ceiling to size. Do not add or tune `maxTurns` in `.claude/agents/*.md`; it does nothing.

Observe real turn/duration usage with **`apd report turns`** (turns, wall-clock, tok/s per agent type). tok/s is the API/infra-stall discriminator. An agent that starts but has no stop event is a dropped `SubagentStop` hook (recover with `apd pipeline reconstruct-agents`), NOT a maxTurn exhaust.

## 9. Mandatory skills

These skills are NOT optional. They MUST be used at the specified points in the pipeline.

| Skill | When | Who | Trigger |
|-------|------|-----|---------|
| `/apd-pipeline-guide` | Before EVERY spec — unconditional, no skip | Orchestrator | Every new task |
| `/apd-brainstorm` | Before the guide, when task is vague or complex | Orchestrator | User gives unclear/broad task |
| `/apd-tdd` | During implementation | Builder agents | Every builder dispatch |
| `/apd-debug` | When verifier fails or reviewer finds bugs | Orchestrator → Builder | Test failure, build failure, critical review finding |
| `/apd-finish` | After successful commit | Orchestrator | Pipeline completes and commit succeeds |

### Skill enforcement rules

- **`/apd-pipeline-guide`** — MANDATORY on every new task before writing spec-card.md, even when the task is perfectly clear. The spec gate hard-BLOCKS without the `.guide-marker` it writes; there is no skip flag.
- **`/apd-brainstorm`** — If the user's task description is more than one sentence, involves multiple components, or has ambiguous scope → invoke `/apd-brainstorm` BEFORE the guide to converge on a design with the user. Do NOT skip this to save time when scope is unclear; skipping it is fine for fully specified tasks.
- **`/apd-tdd`** — Every Builder agent MUST follow TDD: write failing test → implement → verify pass. The `/apd-tdd` skill defines the exact process. Builders that skip TDD produce untestable code.
- **`/apd-debug`** — When the verifier fails or the reviewer reports a critical issue, do NOT re-dispatch the builder with "fix the bug". FIRST invoke `/apd-debug` to systematically identify the root cause, THEN dispatch the builder with specific fix instructions.
- **`/apd-finish`** — After a successful commit, ALWAYS invoke `/apd-finish` to present the user with options: push, PR, keep local, or discard. Do NOT push without this step.

### Optional skills

| Skill | When |
|-------|------|
| `/apd-github` | If the project uses GitHub Projects for task tracking |
| `/apd-miro` | If the project uses a Miro board for visualization |
