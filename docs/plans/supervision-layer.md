# Supervision layer — frontier-model final review, profile-coupled

**Status:** IMPLEMENTED 2026-07-05 (test-codex-adapter green; independent pre-commit audit run, 6 IMPORTANT findings fixed in-session — see "Audit outcome" below; bump pending user go-ahead)
**Type:** minor (new agent role + verifier-gate condition + conf extension)
**Enforcement impact:** floor UNCHANGED — purely additive gate; no existing guard/gate loosened

## Audit outcome (2026-07-05, decontextualized agent — rule 3)

No CRITICAL floor regression. Fixed in-session:
1. **Env override was two-way** (`off` + silent `warn`-downgrade + synthetic
   skip) — contradicted D3's zero-gaming-surface bar. Now: `SUPERVISION_GATE_DEFAULT`
   constant; env may only ESCALATE to strict; downgrade attempts ignored +
   logged (`supervision-gate-downgrade-ignored`); NO `off`; NO synthetic skip
   (Section 8 sees a harmless WARN in Phase 1; at the strict flip Section 8
   MUST pre-write supervision fixtures — recorded in SPEC §24).
2. **Metrics 18-col row corrupted the second reader** (`apd pipeline metrics`):
   `adv_w` absorbed `|sup_t|sup_a|sup_d` and `$(( ))` evaluated `|` as bitwise
   OR (verified: warns 2 → 6). Fixed with the same named-columns + `_rest` sink
   as pipeline-report.
3. **Hybrid CC+Codex projects** share the APD config → gate active in Codex
   sessions too; Codex `guard-file-edit` allowlist now carries both supervision
   files and the Codex guide note documents the hybrid case (was "inert on
   Codex" — false for hybrids).
4. **No finality check** — a pre-fix supervisor dispatch satisfied the gate
   while judging a stale diff (defeats the fix-of-findings purpose). Now: last
   supervisor STOP must postdate every other agent stop (`supervision-not-final`).
5. **Churn cap counted starts** — a maxTurn-exhausted dispatch (~22% baseline)
   burned the budget. Now counts STOPS (cap 2).
6. **Warn path had zero telemetry** (strict-flip criterion unmeasurable) — now
   logs `supervision-warn` INFO; pass logs `supervision-pass` with the
   supervisor frontmatter model (per-run attribution, plan §3.5 honored).

Deliberate deviations from this plan: `.supervision-count` file dropped (cap
derived from `.agents` stops — one less state file/wipe site); strict BLOCK
exits 1 (consistent with sibling verifier gates), not 2.

**Backlog (audit #2, NOT in v1):** the gate keys off orchestrator-writable
config (`MODEL_PROFILE` line, project `model-profiles.conf` override, supervisor
agent `model:` hand-edit). Same tamper class as the profile system itself;
mitigation = an `audit-drift` dimension (declared-profile-vs-conf-vs-agent-tier
consistency) at Phase 2, not a guard (guards defend the natural move; the
natural move — env prefix — is closed by fix 1).

## 1. Problem / motivation

Two forces meet:

1. **Economy.** Generation is disproportionately more expensive than verification
   (builder phase = multi-dispatch loops, tests, re-dispatches; a review of the
   final diff = one dispatch over a bounded artifact). The eco profile
   (Sonnet builders) is the default workhorse for >80% of tasks
   ([[feedback-eco-default-workhorse]]), and in token-limited weeks it is the
   difference between working and being blocked. What eco lacks is a strong
   final judgment.
2. **A documented gap.** Nobody is REQUIRED to look at the final diff after
   adversarial findings are fixed. Corpus evidence: the maintenance fix-builder
   introduced an EF-in-Application regression while fixing 4 adversarial
   findings — caught only by a VOLUNTARY re-review. Adversarial reviews the
   pre-fix state; fix-of-findings collateral is a known, recurring class.
   Additionally, the v6.17 regression-surface gate is presence-checked, never
   evaluated — no layer reads the RS/Evidence claims and judges them.

**Supervision** = one dispatch of the strongest available frontier model
(claude-fable-5), decontextualized (fresh context AND different model than the
eco builders — the full global-rule-3 stack), positioned AFTER adversarial
fixes and BEFORE the verifier. It buys eco runs a frontier-grade final verdict
at a fraction of what cruise builders would cost.

Profile coupling (user decision): **eco → required, cruise → none (v1),
burn → none.** On burn the builder IS the frontier model — a same-model
supervisor loses the cross-model axis and duplicates what adversarial position
already provides. The gradient tracks the builder↔supervisor capability gap.

## 2. Design decisions (converged)

| # | Decision | Choice |
|---|---|---|
| D1 | Position | Between adversarial close and verifier advance. NO new lifecycle phase — mirrors the adversarial pattern exactly (a summary file the verifier gate requires). Zero state-machine changes. |
| D2 | Profile coupling | Data in `model-profiles.conf`: a `supervisor` role row. **Presence of the row = supervision applies to that profile.** v1 ships the row ONLY on `eco`. cruise/burn have no row → gate inert. |
| D3 | No spec-card opt-out | **NONE.** No `supervision:` spec-card field, no skip flag, no `--force`. User decision: the risk is too high; a gameable required-gate repeats the R-atomization lesson. The only ways out are `apd pipeline reset` or a profile change (already mid-pipeline-refused). Zero gaming surface by construction. |
| D4 | Full mode only | Supervision required only when adversarial ran (Full mode). Lean (≤2 R) stays lean — a frontier supervisor on a trivial DI hotfix contradicts the economy that motivates the layer. |
| D5 | Charter ≠ adversarial | Supervisor does NOT hunt bugs in new code (adversarial's job, positional value stays untouched). Its questions: (1) does the FINAL diff still satisfy the R-criteria; (2) did fix-of-findings introduce collateral; (3) do the Regression-surface/Evidence claims hold against the diff; (4) verdict — safe to commit. |
| D6 | Findings contract | `.supervision-summary` (`SUPERVISION:T:A:D` + Notes) + `.supervision-rationale.md` with the SAME per-finding contract as adversarial rationale (severity/status/rationale ≥40 chars; accept/dismiss/spinoff dispositions; same parser logic reused). No new triage mechanism. |
| D7 | Loop bound | `.supervision-count` cycle cap: findings → fix → ONE re-check, then stop (max 2 supervisor dispatches per task). Mirrors reviewer `max_cycles`. |
| D8 | Rollout | Phase 1 = gate in **warn** mode on eco (advisory, collects live evidence). Phase 2 = flip to **strict** (one-line default change) after ~5–10 live eco+supervision runs compared against the cruise baseline. Same staged pattern as plan-spec v6.8.0→v6.8.1 and regression-surface v6.17. |
| D9 | Opinion, not proof | Supervision is the last OPINION layer before empirical close. It never replaces the executed floor (verify-all.sh, tests that fail-before/pass-after). "Fable said OK" is not evidence ([[feedback-evidence-attestation-not-proof]]). |
| D10 | Runtime scope | CC-only v1 (profiles are CC-only). Codex has no `MODEL_PROFILE` → no supervisor row → gate inert by construction. Documented, not special-cased. |

## 3. Mechanics

### 3.1 `model-profiles.conf`

```
eco|default|claude-sonnet-5|xhigh
eco|adversarial|claude-sonnet-5|max
eco|supervisor|claude-fable-5|max
```

- `pipeline-model-profile`: new exact name-match `supervisor` → `supervisor`
  role class (alongside `adversarial-reviewer` → adversarial,
  `code-reviewer` → reviewer). Existing rewrite + drift-marker (v6.26/27)
  machinery applies unchanged.
- Comment block in the conf documents the supervisor role rule: strongest
  available model, one row per profile that wants supervision, absence = off.

### 3.2 Agent

- New `templates/supervisor-template.md` modeled on
  `adversarial-reviewer-template.md`: `memory: none`, default
  `model: claude-fable-5`, `effort: max`, charter per D5. Input contract in the
  prompt: final `git diff` vs base, spec-card (R + Regression surface block),
  `.adversarial-rationale.md`.
- `apd-init` scaffolds `supervisor.md` as a fourth default agent (present on
  every project; whether the PIPELINE requires its dispatch is the profile's
  decision). Init update-mode model repair skips it when `MODEL_PROFILE`
  declared (same rule as v6.16.1).

### 3.3 Verifier gate (pipeline-advance)

Condition, evaluated at `verifier` advance, in order:

1. `MODEL_PROFILE` declared AND its conf has a `supervisor` row → supervision
   expected; else gate inert (exit path unchanged).
2. Full mode only (`.adversarial-summary` present); Lean → inert (D4).
3. Require `.supervision-summary` + `.supervision-rationale.md`; run the same
   structural checks as the adversarial rationale gate (finding count match,
   valid statuses, T/A/D accounting, ≥40-char rationale scan).
4. Mode: `SUPERVISION_GATE_DEFAULT=warn` (Phase 1) → WARN + proceed;
   Phase 2 flips the constant to `strict` → BLOCK (exit 2, `log_block
   supervision-missing` / `supervision-rationale-malformed`), actionable
   message with the dispatch + file contract (v6.8.3 pattern).

Order enforcement (nice-to-have, Phase 1 if cheap): track-agent
supervisor-before-adversarial check mirroring the v6.8.6
adversarial-out-of-order block.

### 3.4 State lifecycle

New files: `.supervision-summary`, `.supervision-rationale.md`,
`.supervision-count`.

- **Wipe sites (v6.29 #2 lesson — audit ALL of them):** reset, spec
  re-advance, verifier rollback. Add all three files at each site.
- **Archive:** extend `archive_rationale()` to also append
  `.supervision-rationale.md` (own header block) — dismiss-heavy supervision
  runs must stay retro-auditable (same ephemerality lesson as adversarial).
- **Guards:** `.supervision-summary` + `.supervision-rationale.md` join the
  guard-pipeline-state Write/Edit allowlist + guard-bash-scope three-way
  message file list (writes via Write/Edit, reads via `apd pipeline show`).
- `apd pipeline show state` digest: supervision T:A:D + count line.
- `spinoff-finding` precondition widens: adversarial-on-record OR
  supervision-on-record (supervision findings can be spun off too).

### 3.5 Telemetry

- guard-audit: `INFO|orchestrator|supervision-pass|model=<frontmatter model>
  verdict=T:A:D` (routed via `_audit_type`; frontmatter model is the honest
  v1 attribution — the served-model gap is a known separate item).
- `pipeline-metrics.log`: columns 16–18 `sup_t|sup_a|sup_d` (12→15 precedent;
  old rows render unchanged, `apd report` adds a Supervision line when
  non-empty).

### 3.6 Education layer

- `apd-pipeline-guide` (CC skill; Codex mirror gets a one-line "CC-only,
  profile-gated" note — remember the v6.17 three-mirror miss): supervision
  contract section — when it triggers (eco+Full), dispatch point (after
  adversarial fixes), file contract, Common BLOCKs entry.
- `workflow.md` template: supervision step in the phase list + skeleton.
- README enforcement table: row added ONLY at Phase 2 strict-flip (drift
  dim D lesson — no enforcement claims while warn).

## 4. Deliverables (files)

| File | Change |
|---|---|
| `plugins/apd/templates/model-profiles.conf` | eco supervisor row + role docs |
| `plugins/apd/templates/supervisor-template.md` | NEW — agent template |
| `plugins/apd/bin/core/pipeline-model-profile` | supervisor role match |
| `plugins/apd/bin/core/pipeline-advance` | verifier gate condition, wipe sites ×3, archive extension, show digest, spinoff precondition, metrics cols |
| `plugins/apd/bin/core/apd-init` | scaffold 4th default agent |
| `plugins/apd/bin/adapter/cc/guard-pipeline-state` (+bash-scope msg list) | allowlist 2 new files |
| `plugins/apd/bin/core/track-agent` | (optional) out-of-order check |
| `skills/apd-pipeline-guide/SKILL.md` + Codex mirror note | supervision contract |
| `plugins/apd/templates/workflow.md` (rules/workflow.md) | phase step |
| `docs/SPEC.md` | state-file rows, gate row, conf format, agent, metrics, §24 note |
| `plugins/apd/bin/core/test-codex-adapter` | §95 (below) |

## 5. Test plan (§95)

Static: conf eco row present + cruise/burn absent; template exists with
`memory: none` + fable model; role match in pipeline-model-profile; gate code
references both files; wipe sites contain the new files (grep all three).

Live (fixture project): (a) eco profile + Full + no supervision → WARN
(Phase 1) / BLOCK (Phase 2 flip test via env override); (b) supervision files
valid → verifier passes; (c) malformed rationale → warn/block;
(d) Lean eco → gate inert; (e) no MODEL_PROFILE (Codex-shaped) → gate inert;
(f) reset + spec re-advance + rollback wipe all three files; (g) archive
receives supervision block; (h) `.supervision-count` cap honored;
(i) verify-apd Section 8 UNAFFECTED (fixtures declare no eco profile → gate
inert by construction; lock-in assert per the #10/#11 callsite lesson).

## 6. Risks / notes

- **Duplication risk (biggest design risk):** if the supervisor prompt drifts
  toward bug-hunting, it becomes a fourth redundant reviewer. The charter
  (D5) and the template prompt are the defense; watch the first live runs for
  finding-overlap with adversarial.
- **Cost check:** supervision reads the full final diff — on very large eco
  diffs the dispatch is not free, but remains << builder cost. No cap in v1;
  revisit only on evidence.
- **Hypothesis, not fact:** "eco+supervision ≈ cruise quality for less" is the
  thesis to TEST in Phase 1 (compare accept-rates, regression incidents,
  finding overlap vs cruise baseline). Strict-flip only on evidence.
- **verify-apd Section 8:** safe by construction (no eco profile in fixtures),
  but §24 pre-bump grep of ALL pipeline-advance callsites is mandatory before
  bump — every gate change so far that skipped it produced a same-day hotfix.
