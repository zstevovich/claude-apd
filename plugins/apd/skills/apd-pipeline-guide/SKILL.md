---
name: apd-pipeline-guide
description: MANDATORY before EVERY pipeline task on Codex — load BEFORE writing spec-card.md and calling apd:apd_advance_pipeline('spec', ...), on every new task, no exceptions. It is the APD operating manual, NOT a brainstorm — "the task is already clear" is not a reason to skip it. Carries the current gate contract - phase map, implementation-plan **Implements:** format, adversarial rationale file format, common BLOCKs + recovery, state read rules. The spec gate hard-BLOCKS without the .guide-marker this skill writes on exit. There is no skip argument.
effort: low
---

# APD Pipeline Guide (Codex)

The operating manual for one pipeline cycle. Read it, acknowledge the contract,
write the marker, proceed. ~2 minutes; cheaper than any single BLOCK it prevents.

This skill is NOT a clarification dialogue. If the task scope is vague, load
`apd-brainstorm` FIRST (interactive, optional), converge on a design, then come
back here. This guide is unconditional either way.

## Pipeline phase map

```
spec → builder → reviewer → adversarial → verifier → commit
```

| Advance | Gate checks at that point |
|---|---|
| `apd:apd_advance_pipeline('spec', '<task>')` | spec-card.md exists, ≤7 R-criteria, **`.guide-marker` present (this skill)** |
| `apd:apd_advance_pipeline('builder')` | implementation-plan.md exists, plan-spec consistency (strict), regression surface (Cover/Evidence), no stale pre-spec dispatch |
| `apd:apd_advance_pipeline('reviewer')` | builder ran post-spec, builder cycle cap (default 2) |
| `apd:apd_adversarial_pass(...)` | only AFTER reviewer.done — out-of-order verdict is refused; and since v6.36 a real native subagent must be on record (`apd_prepare_dispatch` + `spawn_agent`), not an inline verdict |
| `apd:apd_advance_pipeline('verifier')` | `.adversarial-summary` + `.adversarial-rationale.md` present, rationale gate, spec-hash immutability |
| commit | guard-git: pipeline complete, commit message prefix, no mass staging |

Two independent spec-card switches, routinely confused:

- `pipeline_mode: polish` — lowers the builder AND reviewer caps 2 → 1. It does
  **NOT** skip adversarial: the full builder → reviewer → adversarial → verifier
  sequence still runs, just once through.
- `adversarial: skip — <reason>` — the Lean opt-out, and the ONLY way to skip
  adversarial. Honoured only at **≤2 R-criteria**; at 3+ the opt-out is DENIED
  (warning) and adversarial stays required at the verifier.

Lean vs Full is declared in the spec; this guide applies to BOTH.

Note: the v6.30 supervision layer (frontier review of the FINAL diff) is
CC-owned and **honest-inert on the Codex runtime since v6.33** — a Codex run
structurally cannot dispatch the CC supervisor, so the gate never passes and
never blocks; it logs `supervision-not-applicable|runtime=codex` and moves on.
This holds on hybrid CC+Codex projects too, even though they share the APD
config and a `MODEL_PROFILE` declared from the CC side. Do NOT hand-write
`.supervision-summary` to satisfy it: before v6.33 that produced a FALSE
`supervision-pass` with no supervisor on record, which is why the gate now
keys on the runtime instead of on the file.

**Consequence worth knowing:** on Codex the adversarial pass is the only
independent review layer this pipeline has. Triage it accordingly.

## Implementation plan contract

Write `.apd/pipeline/implementation-plan.md` BEFORE the builder advance.
**EVERY `### Section` MUST have an `**Implements:**` header — NO RESERVED NAMES.**
Functional sections (Backend, Frontend, Database, Tests) → R-id list (`R1, R3`);
scaffolding sections (Files to modify, Files to create, Agents, Notes) → `none`.

Bidirectional check (`verify-plan-spec`, strict by default since v6.8.1):
forward (every declared R-id exists in spec), reverse (every spec R-id appears in
≥1 section), symmetric (every section declares R-ids or `none`).

Known failure shape: headers written for Files-to-modify/create but forgotten on
Agents/Notes (asymmetric learning). Write ALL headers FROM THE START.

## Regression surface contract

A task that reaches into a shared module to do its own job must not regress that
module's surrounding behaviour. The adversarial reviewer is not exhaustive on the
first pass — so declare the must-not-break set in spec-card.md and let the gate
check it (`verify-regression-surface`, in the builder advance).

```
**Regression surface:**
- RS1: <neighbouring behaviour touched> — **Cover:** existing <Suite>
- RS2: <another> — **Cover:** new <TestName>
```

- Every `- RS<N>:` needs a `**Cover:**` value (existing test / `new <name>` / `none: <reason>`).
- No shared state touched? Say so explicitly: `**Regression surface:** none — <reason>`.
  Leaving it blank when the spec has a Human gate is a BLOCK; an unjustified bare `none` is a BLOCK.
- Human gate = Yes escalates: each RS item also needs `**Evidence:**` (≥40 chars)
  attesting the module's tests green before+after. The gate checks presence; you run the tests.
- Mode `regression_gate: strict|warn|off` (default `warn`; `off` ignored on a Human-gate path).

## Dispatching agents — native subagents only (v6.36)

The orchestrator coordinates; it does not implement or review inline. Every
builder, reviewer and adversarial pass is a REAL native subagent, and the gates
now require a matching start AND stop in `.agents` — a self-attested phase is
rejected.

```
apd:apd_list_agents()                        # which roles exist
apd:apd_prepare_dispatch(apd_role="<role>")  # reserve the phase, get a safe task_name
spawn_agent(<returned task_name>, ...)       # the real dispatch — then WAIT
```

Prepare immediately before `spawn_agent`, one at a time — a second preparation
before the first child starts collides (the reservation is single-pending with a
120s TTL). The child clears every write through `apd:apd_guard_write(apd_role,
file_path)`, which reads scope from the canonical role definition and **cannot be
widened by the prompt**; a writable role with no scope anywhere fails CLOSED.

## Dispatching the adversarial reviewer — keep it blind

Its value is positional: it judges the diff without knowing the intent, which is
how it finds what the contextual reviewer already rationalised away.

**On Codex this is discipline, not enforcement.** The CC-side `guard-spec-blind`
keys on a per-call role tag that the Codex payload does not carry, so it is inert
here — nothing stops that child from reading `spec-card.md`. You keep the layer
honest:

- Do NOT paste the spec, the R-criteria or the design intent into its prompt.
- Do NOT tell it to read the spec card or the implementation plan.
- Point it at `.apd/pipeline/.reviewed-files` for scope, nothing more.
- A finding phrased as "this does not match the spec" means the intent leaked in.

## Adversarial rationale contract

AFTER `apd:apd_adversarial_pass(...)`, BEFORE the verifier advance, write
`.apd/pipeline/.adversarial-rationale.md` (note the `.md` extension) with one
block per finding:

```
## Finding 1 — <one-line title>
**Severity:** critical | important | minor
**Status:** accepted | dismissed | reviewer-self-dismissed
**Rationale:** <text ≥40 chars required for dismissed/reviewer-self-dismissed>
```

- Missing file → BLOCK at verifier.
- 100% orchestrator-dismiss (T≥3, A=0, Do≥1) → hard BLOCK. Accept at least one
  finding OR reclassify with the adversarial reviewer's own note as
  reviewer-self-dismissed.
- Do NOT write `adversarial: max_defects=...` in the spec — DEPRECATED (v6.9),
  removed in v7.0; the rationale gate is the replacement.

## Finding dispositions — accept / dismiss / SPINOFF

Every adversarial finding gets one of three dispositions:

- **accept** — real AND in this task's scope (and within the cycle cap) → fix via builder.
- **dismiss** — not a real defect → rationale ≥40 chars.
- **spinoff** — real BUT out of THIS task's declared scope (often the ones that
  surface at the cycle cap). Do NOT expand the task, do NOT cram it into this
  commit, and **NEVER disable APD to land it**. Record it as a follow-up task
  seed and continue in scope:

  ```bash
  apd pipeline spinoff-finding <id> "<why out of scope + the follow-up task>"
  apd pipeline show deferred   # the follow-up backlog
  ```

  In `.adversarial-rationale.md` a spun-off finding is still **`**Status:** accepted`**
  (it is real — it counts in the summary `A`). `spinoff-finding` is the durable
  deferral RECORD, not a rationale status — the rationale gate only knows
  `accepted | dismissed | reviewer-self-dismissed`, so do NOT invent a `spinoff`
  status (that BLOCKs at verifier).

  The spun-off finding becomes its own APD task next — full spec + fresh
  adversarial + red-green test. That is exactly the treatment a real (often
  rule-1) defect deserves; cramming it in with enforcement disabled skips it.

**When you ask the user what to do about an out-of-scope finding at the cap,
list spinoff FIRST and recommend it.** "Expand this task / raise the cap" is only
right when the finding is genuinely in scope and the cap raise is justified.

## Reading pipeline state

Use the sanctioned read path — shell `cat`/`ls` on `.apd/pipeline/` is
guard-blocked:

```bash
apd pipeline show          # digest: criteria, plan, reviewed count, T:A:D, cycles
apd pipeline show spec     # full spec-card.md
apd pipeline show plan     # full implementation-plan.md
```

Writes to allowlisted pipeline files (spec-card.md, implementation-plan.md,
.adversarial-summary, .adversarial-rationale.md, .guide-marker) go through the
Edit/apply_patch channel cleared by `apd:apd_guard_write` — shell redirects to
`.apd/pipeline/` are blocked by design.

## Common BLOCKs + recovery

### Gate BLOCKs — fire at a pipeline advance

| BLOCK reason | Quick fix |
|---|---|
| `guide-marker-missing` | Load this skill, write the marker (below), re-run spec advance |
| `plan-spec-consistency issues=N` | Add `**Implements:**` headers / missing R-ids per the inline template; re-run builder (~10s) |
| `regression-surface issues=N` | Add `**Regression surface:**` with `- RS<N>: ... **Cover:** ...` (and `**Evidence:**` on Human-gate paths), or `none — <reason>`; re-run builder |
| `rationale-missing` | Write `.adversarial-rationale.md` with T entries; re-run verifier |
| `rationale-100pct-orch-dismiss` | Accept ≥1 finding OR reclassify dismissed → reviewer-self-dismissed |
| `rationale-count-mismatch` / `rationale-accepted-mismatch` / `rationale-status-mismatch` | The rationale must RECONCILE with `ADVERSARIAL:T:A:D`: one `## Finding` block per T, blocks with `Status: accepted` = A, `dismissed` + `reviewer-self-dismissed` = D. Fix the file or fix the recorded pass — whichever is wrong |
| `rationale-malformed-fields` | Every block needs all three of `**Severity:**` / `**Status:**` / `**Rationale:**`, and a dismissal needs ≥40 chars of reasoning |
| `max_builder_cycles-exceeded` / `max_reviewer_cycles-exceeded` | First ask why: is the plan complete, the spec ambiguous, the same finding coming back? Then either decompose into 2+ tasks, or lift the budget in place: `apd pipeline raise-cap builder\|reviewer <N> "<reason>"`. **Do NOT edit `max_cycles` in the signed spec** — that forces a spec re-advance, which WIPES `.agents`, destroys the evidence already earned and (on Codex) forces a redundant re-dispatch |
| `adversarial-before-reviewer` | Dispatch code-reviewer first; advance reviewer; THEN adversarial |
| `adversarial-agent-missing` | No `adversarial-reviewer` definition and no valid opt-out, so the layer cannot run. Restore the agent (`apd cdx init`) — or, only if the task genuinely qualifies (≤2 R-criteria), declare `adversarial: skip — <reason>`. A missing agent is a setup fault, never an opt-out |
| `adversarial-unaccounted` | Reached the verifier with no `.adversarial-pending` and no valid opt-out — the layer was dropped rather than run or waived, usually because the agent definition went missing after the reviewer step. Restore it and re-advance the reviewer |
| `adversarial-summary-without-dispatch` | Recorded a pass with no adversarial start in `.agents` — since v6.36 the phase needs a REAL native subagent (`apd_prepare_dispatch` + `spawn_agent`), not an inline verdict |
| `max_defects-*` (DEPRECATED v6.9) | Remove the `max_defects` field from spec-card; do not re-introduce |
| `adversarial-timestamp-unparseable` | The `.agents` ledger is corrupt or was hand-edited — the gate fails closed rather than guess an ordering. Inspect it before doing anything else |
| `pipeline-incomplete` | Commit attempted before `verifier.done` — finish the pipeline first |

### Guard BLOCKs — fire on a tool call, at any point in the run

These are not phase gates. They stop the individual call and the run continues.

| BLOCK reason | What it means |
|---|---|
| write not cleared (`guard-file-edit`) | Every implementation write goes through `apd:apd_guard_write(apd_role, file_path)` FIRST. Scope comes from the role definition; a writable role with no scope anywhere fails CLOSED |
| `out-of-scope-bash-write` | A shell write outside the role's scope. Give the work to the role that owns that path — routing the same write through the shell to dodge the check is the bypass the guard exists for |
| `portability-<cmd>` | A GNU-ism on macOS, or a BSD-ism on Linux. `apd env` prints the platform and the portable form of each blocked command |
| `pipeline-state-write` on a read | You used shell `cat`/`ls` on pipeline state — use `apd pipeline show` |

## Exit — write the marker

The spec gate reads `.apd/pipeline/.guide-marker`. Write it as the LAST step of
this skill, with the exact task name you will pass to the spec advance:

```bash
printf '%s|%s\n' "<task-name>" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .apd/pipeline/.guide-marker
```

Then call `apd:apd_advance_pipeline('spec', '<task-name>')`. Name mismatch or
missing marker → hard BLOCK. There is no skip argument — this gate has no
opt-out by design (reading the contract is cheaper than negotiating about it).
The marker is wiped on reset and on task completion.

## Exit criteria

You're done when:
- You can state which gate fires at each of the 5 advances
- You know the two file contracts (plan `**Implements:**`, rationale `.md`)
- `.guide-marker` is written with the exact task name
