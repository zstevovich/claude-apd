# Plan — Regression Surface Gate

> Make collateral regression a declared, mechanically-checked concern: when a task
> touches a module to do its own job, the surrounding behaviour of that module must
> stay provably intact. Target: next minor (v6.17 candidate). Status: design,
> not started.

## Problem

APD has strong gates for "did the task do what it declared" (R-criteria + verify-trace,
plan-spec consistency) but only one *implicit* defence for "did the task break something
it merely touched": the adversarial reviewer. The adversarial reviewer's value is
positional (it sees the sum, cross-handler interactions) — but it is **not exhaustive on
the first pass**, and this is documented in our own corpus:

- The maintenance-broadcast run was `5:3:2` "clean", yet shipped a latent
  `catch(Exception)` swallowing `OperationCanceledException` — caught only later when a
  *sibling* task happened to touch the same handler. A clean adversarial pass means "this
  pass found nothing", not "nothing was broken".

The user's framing: *"pipeline dira profil jer uvezuje porudžbine — ne sme da regresira
bilo šta iz profila okolo."* When task X edits module A for X's own reason, the rest of A
must not silently regress. This is exactly a rule-1 path from the global CLAUDE.md
(shared state, accumulation, cross-boundary atomicity) — the bug lives in the
composition, invisible at any single read.

Regression is, by nature, **empirical** (global rules 2 + 4): only execution can disprove
it; agent consensus cannot. So any anti-regression layer that ends at "the model thought
about the blast radius" repeats the failure mode it is meant to catch. The design below
keeps a cheap declarative anchor as the default, and reserves an *execution-evidence*
requirement for the paths where the cost of error actually justifies it.

## Design — three graduated levels

Strictness is graduated by risk, the existing APD pattern (Lean/Full, `strict|warn|off`).
The orchestrator does **not** pick the level — the framework derives it from already-declared,
already-checkable signals.

### Level 1 — Declaration (always)

New optional spec-card block. The orchestrator names what the task touches *indirectly*
and what must stay intact. Empty (with a one-line reason) when the task touches no shared
state — a quiet default, not a ceremony.

```
**Regression surface:**
- RS1: profile address edit path — **Cover:** existing ProfileAddressTests
- RS2: GDPR consent read on order import — **Cover:** new ConsentUnaffectedTest
```

or, when genuinely nothing shared is touched:

```
**Regression surface:** none — task is self-contained (no shared module read/write)
```

### Level 2 — Coverage anchor (default gate)

Mechanical check, modelled exactly on `verify-plan-spec` (declare → must map):

- Every `RS<N>` line must carry a non-empty `**Cover:**` value (an existing test
  reference, the literal `new <name>`, or `none: <reason>`).
- **Anti-gaming reverse check:** if the spec raises a risk signal (see Level 3) **and**
  `Regression surface:` is empty/absent, BLOCK with "declare a regression surface or
  justify it empty". This closes the empty-surface dodge the same way the plan-spec
  reverse check closes `**Implements:** none` on everything.
- The gate verifies *declaration + mapping*, not test execution — execution stays with
  the builder/adversarial, the framework asks for the artifact. This is the cheap level
  and covers the ~80% case.

### Level 3 — Execution evidence (escalation, derived not chosen)

Only when the surface touches a sensitive path. **Source of the signal is the existing
`**Human gate:**` field** (already enumerates "API changes, migrations, auth, deploy"),
plus DB-migration mention in the plan. No new classifier.

- When `**Human gate:**` = yes (or migration present), each `RS<N>` must additionally
  carry an `**Evidence:**` line — a reference to the surrounding module's existing tests
  green before and after (e.g. a test-run output path, or `green: <suite> @ <commit>`).
- The gate checks the **presence** of the `**Evidence:**` line, the same way the verifier
  checks that `.adversarial-rationale.md` exists. It does **not** map module→suite or run
  tests itself — that is a cross-stack confabulation trap (cf. the verify-contracts PHP
  episode). The builder runs and attests; the framework demands the attestation.

Net: `declare` everywhere, `anchor` as the default gate, `evidence` only when risk pulls
it — automatically, never by orchestrator choice.

## Mechanism

### New verifier: `plugins/apd/bin/core/verify-regression-surface`

Modelled on `verify-plan-spec`. Reads `spec-card.md` only (no plan dependency). Behaviour:

1. Early-exit 0 if spec-card absent or has no `**Regression surface:**` AND no risk signal.
2. Parse risk signal: `**Human gate:**` value (yes/required/true → escalate) + plan
   migration mention.
3. Parse surface items (`- RS<N>: ... **Cover:** ...`).
4. Coverage check: every RS has a non-empty `**Cover:**`.
5. Reverse/anti-gaming: risk signal present + surface empty → issue.
6. If escalated: every RS must also have `**Evidence:**`.
7. Mode from spec-card `regression_gate: strict|warn|off` — **default derived**, not a
   free orchestrator dial (see Open question 1). `log_block "regression-surface" "..."`
   on BLOCK; exit 1 in strict with issues, else 0.

### Wiring

- `pipeline-advance`: call `verify-regression-surface` in the **builder** phase, after
  the plan-spec gate (both are spec/plan-shape gates; same dispatch point).
- Reset wipes nothing new (surface lives in spec-card.md, already wiped on re-advance).
- No new guard-allowlisted file — the surface is part of spec-card.md, already writable
  via the cleared Edit channel.

### Where it learns (critical — else the surface is empty from ignorance, not safety)

- `apd-pipeline-guide` (CC + Codex mirror + openai.yaml): new "Regression surface
  contract" section — teach the orchestrator to ask *"what do I import / read / write
  that I don't own?"* before writing the spec, with the `RS<N>` + `**Cover:**` /
  `**Evidence:**` format and the Human-gate escalation rule.
- `apd-brainstorm`: one clarifying prompt nudging blast-radius thinking during scoping.
- `workflow.md` §SPEC + AGENTS.md step 1: format example + the "declare or justify empty"
  rule.
- `Common BLOCKs` table (guide): `regression-surface-*` rows with quick fixes.

## Test plan

`test-codex-adapter` new section (next free §, ~ §85): static (binary exists/executable,
forward/reverse strings, escalation string, `regression_gate` parser, DEFAULT derivation)
+ live on an isolated synthetic project: (a) surface declared + covered → pass; (b) RS
without `**Cover:**` → BLOCK; (c) Human gate=yes + RS without `**Evidence:**` → BLOCK;
(d) Human gate=yes + empty surface → BLOCK (anti-gaming); (e) self-contained `none` +
no risk signal → pass; (f) `regression_gate: off` opt-out → pass. Update test count.

Lock-in for the guard/guide learning surface per the test-hook-path-blindspot lesson.

## Docs (same commit as implementation, per SPEC-first rule)

- `docs/SPEC.md` — new verifier row in the verifiers table; spec-card field; §24 pre-bump
  callsite note (grep `verify-regression-surface` is now a pipeline-advance callsite).
- `workflow.md`, `AGENTS.md`, `apd-pipeline-guide` SKILL (CC + Codex), `README` enforcement
  table.

## Open questions (to resolve before coding)

1. **`regression_gate` mode — derived vs dialable.** Default must be **derived** from
   Human gate (the whole point: orchestrator can't pick cheap). But do we expose
   `regression_gate: off` at all? Precedent (`plan_consistency_gate: off`) says yes for
   graceful migration, but `off` on a Human-gate=yes task is exactly the path we most want
   covered. Leaning: allow `off` but log it loudly + ignore `off` when Human gate=yes
   (escalation is non-negotiable, like the v6.13 floor stance).
2. **`**Evidence:**` format.** How concrete? A free-text attestation is gameable (the
   adversarial-summary-without-dispatch precedent). A test-output path is stronger but
   cross-stack-fragile. Leaning: free-text but require ≥40 chars (mirror the rationale
   gate's anti-laziness rule) + name the suite — presence-checked, not executed.
3. **Default rollout: `warn` first or `strict`?** Plan-spec shipped `warn` then flipped to
   `strict` same-day on evidence. Same staged approach reduces blast radius on existing
   projects that have no `Regression surface:` block yet (they'd all BLOCK on day one
   under strict). Leaning: `warn` for one release, flip on live evidence.

## Out of scope (explicit, no silent caps)

- Automatic blast-radius detection (module→affected-symbol graph). Cross-stack, high
  confabulation risk. We declare, we don't infer.
- Framework-run test execution / module→suite mapping. The framework checks the artifact;
  it never runs the suite. Revisit only if presence-check proves too weak in the corpus.
- Coverage-percentage tooling (touched-symbol vs covered-symbol). Language-specific;
  a later, separate consideration if Level 2 anchors prove insufficient.

## Enforcement-floor note

This is **additive enforcement**, not loosening — it closes a gap the adversarial pass
provably misses, consistent with the non-negotiable-floor position. It does not touch any
existing gate.
