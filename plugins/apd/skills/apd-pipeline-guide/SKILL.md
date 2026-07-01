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
| `apd:apd_adversarial_pass(...)` | only AFTER reviewer.done — out-of-order verdict is refused |
| `apd:apd_advance_pipeline('verifier')` | `.adversarial-summary` + `.adversarial-rationale.md` present, rationale gate, spec-hash immutability |
| commit | guard-git: pipeline complete, commit message prefix, no mass staging |

Mode: `pipeline_mode: polish` in spec-card.md lowers cycle caps to 1 and skips
adversarial for 1-2 R hotfixes. Lean vs Full is declared in the spec; this guide
applies to BOTH.

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

| BLOCK reason | Quick fix |
|---|---|
| `guide-marker-missing` | Load this skill, write the marker (below), re-run spec advance |
| `plan-spec-consistency issues=N` | Add `**Implements:**` headers / missing R-ids per the inline template; re-run builder (~10s) |
| `regression-surface issues=N` | Add `**Regression surface:**` with `- RS<N>: ... **Cover:** ...` (and `**Evidence:**` on Human-gate paths), or `none — <reason>`; re-run builder |
| `rationale-missing` | Write `.adversarial-rationale.md` with T entries; re-run verifier |
| `rationale-100pct-orch-dismiss` | Accept ≥1 finding OR reclassify dismissed → reviewer-self-dismissed |
| `max_builder_cycles-exceeded` | Decompose into 2+ tasks OR raise cap via spec-card `builder: max_cycles=N` |
| `adversarial-before-reviewer` | Run code-reviewer first; advance reviewer; THEN adversarial |
| `max_defects-*` (DEPRECATED v6.9) | Remove the `max_defects` field from spec-card; do not re-introduce |
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
