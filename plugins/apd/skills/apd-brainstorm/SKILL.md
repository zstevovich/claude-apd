---
name: apd-brainstorm
description: Use BEFORE writing the APD spec-card.md and calling apd:apd_advance_pipeline('spec', ...) on Codex whenever the task is vague, broad, ambiguous, or has multiple reasonable interpretations. Ask ONE question at a time, present 2-3 approaches when there are real choices, converge on a design the user explicitly approves. Works hand in hand with `.apd/rules/brainstorm.md` when that file exists. Triggers on "improve X", "what should we", "thinking about", "options", "not sure", "vague", "broad", "redesign", any task with unclear scope or fewer than 3 R-criteria.
---

# APD Brainstorm (Codex)

Finish the question / option / design-approval flow BEFORE calling
`apd:apd_advance_pipeline('spec', ...)`. That call is the only valid exit
after the user explicitly approves the design summary.

## When to use / When to skip

**Use when:**
- The task is vague, broad, or "improve X" style
- The user gave a destination but no path ("we need user search")
- Multiple reasonable interpretations exist
- You catch yourself making implementation choices the user hasn't seen

**Default: load on every new task.** v6.8.11 made the brainstorm-marker gate unconditional — the previous "trivial task (≤2 R-criteria) automatic skip" carve-out is gone. R-count proved gameable: orchestrator atomized non-trivial work to 2 R-criteria specifically to bypass the gate, producing 30-40 min pipelines with downstream BLOCK cascades. Per-task brainstorm load is structurally cheaper than the BLOCK loop that an undisciplined entry triggers.

**Skip only when (TWO-PART CHECK — both must be true):**

1. **Scope is aligned** — task fully specified OR user approved design informally, AND
2. **APD config decisions are explicit** — you can answer YES to ALL:
   - Adversarial budget: omit field (= unlimited) za standard tasks
   - Plan: `**Implements:**` on EVERY `### Section` (NO RESERVED NAMES — includes Agents, Notes)
   - Rationale: `.apd/pipeline/.adversarial-rationale.md` (sa `.md`!) with per-finding blocks
   - BLOCK recovery patterns known

Canonical skip cases: genuine 1:1 mirror of a just-completed task, single-line bug fix with one R-criterion, hotfix with explicit pre-aligned design.

**Also skip when:**
- Mid-pipeline (spec locked; raise concerns, don't re-brainstorm)

**If you cannot confirm BOTH parts — DO NOT skip.** Empirical: Bambi Cycle E (2026-05-22) informal brainstorm covered scope but NOT APD config → 3h cascade. BambiProject MS.4 + Photo Bill CTA (2026-05-23) skipped via R-atomization → 30-40 min each with adversarial N/A. Override flag (`apd_advance_pipeline('spec', '<name>', skip_brainstorm='<reason>')`) requires concrete reason acknowledging both parts.

## The Iron Law

```
NO SPEC WITHOUT SHARED UNDERSTANDING FIRST
```

If you cannot explain the design in one sentence, you are not ready for a
spec-card.md. A vague spec produces vague code.

## Process

1. **Read project context** — `AGENTS.md`, `.apd/memory/MEMORY.md` and
   `.apd/memory/status.md`, source close to the idea.
2. **Ask ONE question at a time.** Never dump a list of 5 questions. Ask
   one, wait for the answer, ask the next.
3. **Present trade-offs, do not decide.** When real choices exist, offer
   2–3 concise options and let the user pick.
4. **Converge on a design.** Hand the user a short summary covering Goal /
   Scope / Out of scope / Approach / Affected files / **Risks** / **Rollback**
   / Mode / Adversarial budget / R-criteria / Human gate. Wait for explicit
   approval.

   **Risks + Rollback are NOT optional** for tasks with DB migration / new
   public endpoint / auth changes / external API. For trivial polish/hotfix,
   say "minimal" or "revert commit" — but be explicit. Empty Risks/Rollback
   in spec-card.md is documentation gap adversarial cannot catch.
5. **Only then** write `.apd/pipeline/spec-card.md`, write the brainstorm
   marker, and call `apd:apd_advance_pipeline('spec', '<name>')`.

   **MANDATORY (v6.8.5+):** before the spec advance, write the marker:
   ```bash
   printf '%s|%s\n' "<task-name>" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .apd/pipeline/.brainstorm-marker
   ```
   `apd_advance_pipeline('spec', ...)` reads it. R-count > 2 in spec-card.md
   without marker → hard BLOCK. **Override (v6.8.8+, rare — requires concrete
   reason):** pass `skip_brainstorm='<reason mentioning scope alignment AND
   APD config clarity>'` to the tool call. Empty reason → BLOCK. Skip event
   loguje INFO entry u guard-audit.log za audit trail.

**Adversarial budget — `max_defects` field is DEPRECATED as of v6.9.**

Will be removed in v7.0. **DO NOT write `adversarial: max_defects=...` in new specs.** Field continues to function in v6.9 for graceful transition (verifier gate + immutability check both active), but emits a deprecation warn on every spec advance. Rationale gate (v6.7) structurally covers the misuse pattern that max_defects was meant to prevent (per-finding rationale ≥40 chars dismissed + 100%-orchestrator-dismiss hard-block).

| Task profile | Recommended |
|---|---|
| Standard task (1–7 R, almost all) | **omit `max_defects` field** — default = unlimited |
| polish-mode (1–2 R hotfix) | `pipeline_mode: polish` — lower cycle caps + skip adversarial entirely |

Empirical evidence (v6.8 dev cycle, 2026-05-22): tasks sa `max_defects=0` trajali 26-33 min sa 3 guard BLOCK-a; identicni task BEZ polja trajao 13 min clean. v6.8 chain (10 patches) validated rationale gate as sufficient standalone enforcement.

## Downstream gates the spec triggers

After spec advance, orchestrator MUST write these files. Brainstorm should mentally prepare for them:

**Implementation plan** (`.apd/pipeline/implementation-plan.md`): **EVERY** `### Section` MUST start with `**Implements:** R1, R3` (or `none` for scaffolding) — **NO RESERVED NAMES**. This applies uniformly to functional sections (Backend, Frontend, Database, Tests) AND scaffolding sections (Files to modify, Files to create, Agents, Notes). Empirical evidence (Soft-delete task 2026-05-22): orchestrator naucio Implements pattern za Files-to-mod/create ali zaboravio za Agents/Notes — asymmetric learning triggered plan-spec-consistency BLOCK na 2 missing headera. `verify-plan-spec` strict mode (v6.8.1+ default) hard-BLOCKS `apd:apd_advance_pipeline('builder')` otherwise. Bidirectional check: every R-id from spec must appear in ≥1 section's **Implements:** line.

**Adversarial rationale** (`.apd/pipeline/.adversarial-rationale.md`): after `apd:apd_adversarial_pass(...)`, write one block per finding (`## Finding N` + `**Severity:**` + `**Status:**` + `**Rationale:**`) BEFORE `apd:apd_advance_pipeline('verifier')`. v7.1 BLOCK otherwise. v7.6 BLOCK if 100% orchestrator-dismissed (T≥3 && A==0 && Do≥1) — at least one accept OR reclassify to reviewer-self-dismissed.

## Common BLOCKs + recovery

| BLOCK reason | Quick fix |
|---|---|
| `plan-spec-consistency` | Add **Implements:** headers per section; re-run builder advance |
| `max_defects-exceeded` (v6.9 DEPRECATED) | Reset + remove `max_defects` field — gate goes away in v7.0 |
| `rationale-missing` | Write `.adversarial-rationale.md` with T entries; re-run verifier |
| `rationale-100pct-orch-dismiss` | Accept at least 1 finding OR reclassify dismissed → reviewer-self-dismissed |
| `max_builder_cycles-exceeded` | Decompose into 2+ tasks OR raise cap via spec-card `builder: max_cycles=N` |
| `adversarial-before-reviewer` | Dispatch code-reviewer first; advance reviewer; THEN adversarial |

## Do not do during brainstorming

- Write code
- Call `apd:apd_guard_write`
- Edit any file outside `.apd/pipeline/`
- Advance the pipeline while asking questions, presenting options, or revising
  the design; the spec advance is allowed only after explicit approval and is
  the only valid exit

Brainstorming produces a DESIGN. Implementation is the builder phase.

## Red flags — STOP and return to Ask-One-Question

| Thought | Reality |
|---------|---------|
| "This is simple, skip brainstorm" | Simple tasks have hidden complexity. 5 minutes of questions saves 30 minutes of rework. |
| "I already know what they want" | You know what YOU would build. Ask what THEY want. |
| "Let me just start coding and iterate" | Iteration without direction is waste. |
| "The user seems impatient" | Users are more impatient when you build the wrong thing. |
| "I'll figure it out during implementation" | Vague specs produce vague code. |

## Exit criteria

You're done when:
- The user can restate the goal in one sentence and you both agree on it
- Scope and out-of-scope are explicit and written down
- Approach is named (architectural pattern, library choice, integration point)
- Affected files are listed (not just "wherever it goes")
- The user has explicitly approved the design summary — no implicit approval
- `.apd/pipeline/spec-card.md` has been written and `apd:apd_advance_pipeline('spec', '<name>')` has been called as the final brainstorm action

## Hand-off

- After explicit approval → write the spec-card.md and call `apd:apd_advance_pipeline('spec', '<name>')`; this is not a mid-brainstorm advance, it is the only valid exit
- Never leads to: code, agent edits, file writes outside `.apd/pipeline/` — those come from the builder phase
- If the user asks for "just one quick thing" mid-brainstorm → finish the brainstorm first, then queue it
