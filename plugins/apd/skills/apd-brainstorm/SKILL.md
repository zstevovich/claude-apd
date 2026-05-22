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

**Skip when:**
- The task is fully specified (file paths, function names, R-criteria)
- The user has already approved a design — write the spec-card.md directly
- You are mid-pipeline (spec is locked; raise concerns to user, don't re-brainstorm)

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
4. **Converge on a design.** Hand the user a short summary — Goal /
   Scope / Out of scope / Approach / Affected files / Adversarial
   budget. Wait for explicit approval.
5. **Only then** write `.apd/pipeline/spec-card.md`, write the brainstorm
   marker, and call `apd:apd_advance_pipeline('spec', '<name>')`.

   **MANDATORY (v6.8.5+):** before the spec advance, write the marker:
   ```bash
   printf '%s|%s\n' "<task-name>" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .apd/pipeline/.brainstorm-marker
   ```
   `apd_advance_pipeline('spec', ...)` reads it. R-count > 2 in spec-card.md
   without marker → hard BLOCK. Override (rare): pass `skip_brainstorm=True`
   to the tool call for eksperimentalne/pre-specified tasks.

**Adversarial budget recommendation** (writes an `adversarial: max_defects=N` line into spec-card.md, enforced at verifier step):

| R-criterion count | Recommended | Why |
|---|---|---|
| 1–7 R (default — almost all tasks) | **omit field** (= unlimited) | v6.7 rationale gate structurally catches misuse (per-finding rationale ≥40 chars + 100%-orchestrator-dismiss BLOCK). No preflight budget cap needed. |
| polish-mode (1–2 R hotfix) | `pipeline_mode: polish` | Lean preset — lower cycle caps + skip adversarial entirely. |
| Power-user explicit budget | `max_defects=N` | ONLY when ti REALLY znas budget unapred — rare. `=0` forces accept-everything which cascades into N-finding builder fix dispatches and possible cycle-cap exhaust. |

**DO NOT write `max_defects=0` for standard tasks.** Empirical evidence iz v6.8 dev cycle (2026-05-22): tasks sa `max_defects=0` trajali 26-33 min sa 3 guard BLOCK-a; identicniji task BEZ polja trajao 13 min clean. Default = omit field.

## Downstream gates the spec triggers

After spec advance, orchestrator MUST write these files. Brainstorm should mentally prepare for them:

**Implementation plan** (`.apd/pipeline/implementation-plan.md`): every `### Section` MUST start with `**Implements:** R1, R3` (or `none` for scaffolding). `verify-plan-spec` strict mode (v6.8.1+ default) hard-BLOCKS `apd:apd_advance_pipeline('builder')` otherwise. Bidirectional check: every R-id from spec must appear in ≥1 section's **Implements:** line.

**Adversarial rationale** (`.apd/pipeline/.adversarial-rationale.md`): after `apd:apd_adversarial_pass(...)`, write one block per finding (`## Finding N` + `**Severity:**` + `**Status:**` + `**Rationale:**`) BEFORE `apd:apd_advance_pipeline('verifier')`. v7.1 BLOCK otherwise. v7.6 BLOCK if 100% orchestrator-dismissed (T≥3 && A==0 && Do≥1) — at least one accept OR reclassify to reviewer-self-dismissed.

## Common BLOCKs + recovery

| BLOCK reason | Quick fix |
|---|---|
| `plan-spec-consistency` | Add **Implements:** headers per section; re-run builder advance |
| `max_defects-exceeded` | Either accept findings, OR reset + remove field from spec-card |
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
