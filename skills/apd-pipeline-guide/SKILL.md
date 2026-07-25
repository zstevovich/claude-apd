---
name: apd-pipeline-guide
description: MANDATORY before EVERY pipeline task — load this skill BEFORE writing spec-card.md, on every new task, no exceptions. It is the APD operating manual, NOT a brainstorm — "the task is already clear" is not a reason to skip it. Carries the current gate contract - pipeline phase map, implementation-plan **Implements:** format, adversarial rationale file format, common BLOCKs + recovery, state read rules. The spec gate hard-BLOCKS without the .guide-marker this skill writes on exit. There is no skip flag.
effort: low
allowed-tools: Read Bash
---

# APD Pipeline Guide

The operating manual for one pipeline cycle. Read it, acknowledge the contract,
write the marker, proceed. ~2 minutes; cheaper than any single BLOCK it prevents.

This skill is NOT a clarification dialogue. If the task scope is vague, load
`/apd-brainstorm` FIRST (interactive, optional), converge on a design, then come
back here. This guide is unconditional either way.

## Pipeline phase map

```
spec → builder → reviewer → adversarial → [supervision] → verifier → commit
```

| Advance | Gate checks at that point |
|---|---|
| `apd pipeline spec "<task>"` | spec-card.md exists, ≤7 R-criteria, **`.guide-marker` present (this skill)** |
| `apd pipeline builder` | implementation-plan.md exists, plan-spec consistency (strict), regression surface (Cover/Evidence), no stale pre-spec dispatch |
| `apd pipeline reviewer` | builder ran post-spec, builder cycle cap (default 2) |
| adversarial dispatch | only AFTER reviewer.done (out-of-order start is not recorded — re-dispatch) |
| supervision dispatch | **every** profile carries a `supervisor` row (v6.38 — burn, cruise and eco alike), so this applies on whatever profile is declared, once adversarial ran (Full mode) — see Supervision contract below |
| `apd pipeline verifier` | `.adversarial-summary` + `.adversarial-rationale.md` present, rationale gate, supervision gate (profile-coupled), spec-hash immutability |
| commit | guard-git: pipeline complete, commit message prefix, no mass staging |

Two independent spec-card switches, routinely confused:

- `pipeline_mode: polish` — lowers the builder AND reviewer caps 2 → 1. It does
  **NOT** skip adversarial: the full builder → reviewer → adversarial → verifier
  sequence still runs, just once through.
- `adversarial: skip — <reason>` — the Lean opt-out, and the ONLY way to skip
  adversarial. Honoured only at **≤2 R-criteria**; at 3+ the opt-out is DENIED
  (warning) and adversarial stays required at the verifier.

Lean vs Full is declared in the spec; this guide applies to BOTH.

## Implementation plan contract

Write `.apd/pipeline/implementation-plan.md` BEFORE `apd pipeline builder`.
**EVERY `### Section` MUST have an `**Implements:**` header — NO RESERVED NAMES.**

```
## Implementation Plan: <task-name>

### Files to modify
**Implements:** none              ← scaffolding sections use 'none'

- src/...

### Backend
**Implements:** R1, R3            ← every dispatch section maps to R-ids

- src/api/... — endpoint changes

### Agents
**Implements:** none              ← Agents needs the header too

- backend-builder
- code-reviewer

### Notes
**Implements:** none              ← Notes needs the header too

- relevant context
```

Bidirectional check (`verify-plan-spec`, strict by default since v6.8.1):
- forward — every R-id in an `**Implements:**` line must exist in spec-card.md
- reverse — every spec R-id must appear in at least one section
- symmetric — every `### Section` must declare R-ids or `none`

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

## Dispatching the adversarial reviewer — it is BLIND

Its value is positional: it judges the diff without knowing the intent, which is
how it finds what the contextual reviewer already rationalised away. Since v6.38
that is **mechanically enforced** (`guard-spec-blind`), not just asked for. The
whole of `.apd/pipeline/` and the APD memory directory are closed to that role —
spec-card, implementation-plan, any earlier rationale, `apd pipeline show`,
`apd report`. One exception: `.apd/pipeline/.reviewed-files`, which IS its scope.

What this means for the dispatch you write:

- Do NOT paste the spec, the R-criteria or the design intent into its prompt.
  Blinding the file and then quoting it in the prompt defeats the entire layer.
- Do NOT tell it to "read the spec card first" — it will hit `spec-blind`.
- Point it at `.reviewed-files` for scope and let it find what it finds.
- Findings that arrive phrased as "this does not match the spec" are a signal the
  intent leaked in; treat them with suspicion.

The blind guard fires ONLY for that role. Builders, the code reviewer, the
supervisor and you all read the spec normally — blinding them would deadlock.

## Adversarial rationale contract

AFTER the adversarial-reviewer dispatch, BEFORE `apd pipeline verifier`, write
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
  commit, and **NEVER `apd toggle off` to land it** (that disables the whole
  enforcement layer). Record it as a follow-up task seed and continue in scope:

  ```bash
  bash .claude/bin/apd pipeline spinoff-finding <id> "<why out of scope + the follow-up task>"
  bash .claude/bin/apd pipeline show deferred   # the follow-up backlog
  ```

  In `.adversarial-rationale.md` a spun-off finding is still **`**Status:** accepted`**
  (it is real — it counts in the summary `A`). `spinoff-finding` is the durable
  deferral RECORD, not a rationale status — the rationale gate only knows
  `accepted | dismissed | reviewer-self-dismissed`, so do NOT invent a `spinoff`
  status (that BLOCKs at verifier).

  The spun-off finding becomes its own APD task next — full spec + fresh
  adversarial + red-green test. That is exactly the treatment a real (often
  rule-1) defect deserves; cramming it in under a disabled pipeline skips it.

**When you ask the user what to do about an out-of-scope finding at the cap,
list spinoff FIRST and recommend it.** "Expand this task / raise the cap" is only
right when the finding is genuinely in scope and the cap raise is justified.

**Orthogonal to all three: does the finding generalize?** A disposition settles
this instance; a class outlives it. If the same shape can appear elsewhere,
record it once — builders read `.apd/lessons.md` before they start, so it
becomes education on every future dispatch instead of knowledge that leaves with
the run:

```bash
bash .claude/bin/apd pipeline lesson "<the rule, as a class>" "<what it cost>"
bash .claude/bin/apd pipeline show lessons
```

Write the rule, not the patch, and not one per finding — a file past ~20 entries
gets skimmed rather than read. `/apd-finish` asks this again at the end of the run.

## Supervision contract (v6.30; topology fixed in v6.38)

Full mode (adversarial ran) expects a **supervision pass over the FINAL diff**
before the verifier, on **every** profile. Rollout: currently a WARN at the
verifier; becomes a hard BLOCK in a future release — treat it as required now.

Supervision is **topology, not a price tier** (v6.38): burn, cruise and eco all
carry a `supervisor` row, so the layer runs at every price point and the profiles
stay comparable. Do not read a cheap profile as "supervision does not apply here".
It is inert on one axis only: `APD_RUNTIME=codex`, where the CC supervisor cannot
be dispatched at all (the gate logs `supervision-not-applicable`).

Sequence, AFTER all adversarial findings are triaged and fixed:

1. Dispatch: `Agent({ subagent_type: "supervisor", prompt: "Final review per charter" })`.
   The supervisor judges only: R-criteria still met by the final diff,
   fix-of-findings collateral, Regression-surface claims vs the diff, commit
   verdict. It does NOT repeat the adversarial bug hunt.
2. Record `.apd/pipeline/.supervision-summary` (Write/Edit tool):
   `SUPERVISION:T:A:D` + Notes — same shape as the adversarial summary.
3. If T>0: triage into `.apd/pipeline/.supervision-rationale.md` — the SAME
   per-finding contract as the adversarial rationale (Severity/Status/Rationale,
   three dispositions incl. spinoff, ≥40-char dismissals). Accepted findings →
   builder fix → ONE supervisor re-check (cap: 2 COMPLETED passes — an
   exhausted dispatch doesn't count; the supervisor's stop must also be the
   LAST agent activity before the verifier, or the gate flags
   `supervision-not-final`).

There is NO spec-card opt-out for this gate — by design. The ways out are
`apd pipeline reset` or switching profile BEFORE the spec advance.

## Reading pipeline state

Use the sanctioned read path — `cat`/`ls` on `.apd/pipeline/` is guard-blocked:

```bash
bash .claude/bin/apd pipeline show          # digest: criteria, plan, reviewed count, T:A:D, cycles
bash .claude/bin/apd pipeline show spec     # full spec-card.md
bash .claude/bin/apd pipeline show plan     # full implementation-plan.md
```

Writes to allowlisted pipeline files (spec-card.md, implementation-plan.md,
.adversarial-summary, .adversarial-rationale.md, .supervision-summary,
.supervision-rationale.md, .guide-marker) go through the Write/Edit tool — bash
redirects to `.apd/pipeline/` are blocked by design.

## Common BLOCKs + recovery

### Gate BLOCKs — fire at a pipeline advance

| BLOCK reason | Quick fix |
|---|---|
| `guide-marker-missing` | Load this skill, write the marker (below), re-run spec advance |
| `plan-spec-consistency issues=N` | Add `**Implements:**` headers / missing R-ids per the inline template; re-run builder (~10s) |
| `regression-surface issues=N` | Add `**Regression surface:**` with `- RS<N>: ... **Cover:** ...` (and `**Evidence:**` on Human-gate paths), or `none — <reason>`; re-run builder |
| `rationale-missing` | Write `.adversarial-rationale.md` with T entries; re-run verifier |
| `rationale-100pct-orch-dismiss` | Accept ≥1 finding OR reclassify dismissed → reviewer-self-dismissed |
| `rationale-count-mismatch` / `rationale-accepted-mismatch` / `rationale-status-mismatch` | The rationale must RECONCILE with `ADVERSARIAL:T:A:D`: one `## Finding` block per T, blocks with `Status: accepted` = A, `dismissed` + `reviewer-self-dismissed` = D. Fix the file or fix the summary — whichever is wrong |
| `rationale-malformed-fields` | Every block needs all three of `**Severity:**` / `**Status:**` / `**Rationale:**`, and a dismissal needs ≥40 chars of reasoning |
| `max_builder_cycles-exceeded` / `max_reviewer_cycles-exceeded` | First ask why: is the plan complete, the spec ambiguous, the same finding coming back? Then either decompose into 2+ tasks, or lift the budget in place: `apd pipeline raise-cap builder\|reviewer <N> "<reason>"`. **Do NOT edit `max_cycles` in the signed spec** — that forces a spec re-advance, which WIPES `.agents` and destroys the builder/reviewer evidence already earned |
| `adversarial-before-reviewer` | Dispatch code-reviewer first; advance reviewer; THEN adversarial |
| `adversarial-agent-missing` | No `adversarial-reviewer` definition and no valid opt-out, so the layer cannot run. Restore the agent (`/apd-setup`) — or, only if the task genuinely qualifies (≤2 R-criteria), declare `adversarial: skip — <reason>`. A missing agent is a setup fault, never an opt-out |
| `adversarial-unaccounted` | Reached the verifier with no `.adversarial-pending` and no valid opt-out — the layer was dropped rather than run or waived, usually because the agent definition went missing after the reviewer step. Restore it and re-advance the reviewer |
| `adversarial-summary-without-dispatch` | Summary written with no adversarial start in `.agents` — dispatch the agent for real. (If it DID run and only its stop is missing, that is a dropped hook: `apd pipeline reconstruct-agents`) |
| `max_defects-*` (DEPRECATED v6.9) | Remove the `max_defects` field from spec-card; do not re-introduce |
| `adversarial-timestamp-unparseable` | The `.agents` ledger is corrupt or was hand-edited — the gate fails closed rather than guess an ordering. Inspect it; `apd pipeline reconstruct-agents` rebuilds it from the transcripts |
| `pipeline-incomplete` | Commit attempted before `verifier.done` — finish the pipeline first |
| `toggle-off-active-pipeline` | Don't disable APD mid-run to cram an out-of-scope fix — use `apd pipeline spinoff-finding <id> "<reason>"`, or `apd pipeline reset` to end the run |
| `supervision-missing` (warn now, BLOCK later) | Dispatch the supervisor on the FINAL diff, record `.supervision-summary` (+ rationale if T>0); re-run verifier. Applies on every profile |
| `supervision-summary-without-dispatch` | Summary written but no supervisor in agent log — actually dispatch the agent first |
| `supervision-not-final` | Agent activity after the last supervisor stop — re-dispatch supervisor on the FINAL state |
| `supervision-cycle-cap` | >2 completed supervisor passes — the loop is the problem; reset or finish the fix properly |

### Guard BLOCKs — fire on a tool call, at any point in the run

These are not phase gates. They stop the individual call and the run continues.

| BLOCK reason | What it means |
|---|---|
| `orchestrator-code-write` | **You** tried to write a code file. The orchestrator writes spec, plan, docs and config — production code goes through a builder agent. This is the pipeline's whole premise, not a formality |
| `out-of-scope-write` / `out-of-scope-bash-write` | An agent wrote outside its declared scope. Give the work to the agent that owns that path, or widen that agent's scope deliberately — routing the same write through bash to dodge it is the bypass the guard exists for |
| `secret-access` | A call touched `.env*`, a key, a cert or a keystore. Nothing in the pipeline needs them |
| `spec-blind` | The adversarial reviewer reached for the spec / plan / a rationale / the memory dir. Working as intended — see the blind-dispatch section above. Fires for that role only |
| `portability-<cmd>` | A GNU-ism on macOS, or a BSD-ism on Linux. `apd env` prints the platform and the portable form of each blocked command |
| `send-message-during-pipeline` | `SendMessage` continues an agent WITHOUT firing SubagentStart/Stop, so the work never reaches `.agents` and the next gate rejects it as "no agent dispatched". Dispatch with `Agent()` instead |
| `parallel-same-agent` | Two dispatches of the same agent type inside the window — serialize them; concurrent same-role writes are how scope collisions happen |
| `pipeline-state-write` on a read | You used bash `cat`/`ls` on pipeline state — use `apd pipeline show` |
| `commit-no-prefix` / `push-no-prefix` | The APD commit prefix is missing. Recurring in practice — check the message shape before every commit |
| `forged-done-file` | A `.done` file written by hand. Phase files come from `apd pipeline <phase>`, never from an editor |

**Three of these are new in v6.38** — `spec-blind`, `secret-access` and
`out-of-scope-write` were wired to per-agent frontmatter hooks, which do not
fire; they now run session-level. If a run of yours hits one of them for the
first time, that is the guard finally working, not a regression.

## Exit — write the marker

The spec gate reads `.apd/pipeline/.guide-marker`. Write it as the LAST step of
this skill, with the exact task name you will pass to the spec advance:

```bash
printf '%s|%s\n' "<task-name>" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .apd/pipeline/.guide-marker

bash .claude/bin/apd pipeline spec "<task-name>"
```

Name mismatch or missing marker → hard BLOCK. There is no `--skip` flag — this
gate has no opt-out by design (reading the contract is cheaper than negotiating
about it). The marker is wiped on reset and on task completion.

## Exit criteria

You're done when:
- You can state which gate fires at each of the 5 advances
- You know the two file contracts (plan `**Implements:**`, rationale `.md`)
- `.guide-marker` is written with the exact task name
