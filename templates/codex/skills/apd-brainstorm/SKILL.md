---
name: apd-brainstorm
description: Use when an APD task is vague, broad, or has multiple reasonable interpretations — before writing the spec card and calling apd_advance_pipeline('spec', ...). Ask ONE question at a time, present 2-3 approaches when there are choices, converge on a design the user explicitly approves. Works hand in hand with `.apd/rules/brainstorm.md` when that file exists in the project.
---

# APD Brainstorm (Codex)

**Use when:** the task is vague, broad, or "improve X" style. Finish
brainstorming BEFORE calling `apd_advance_pipeline('spec', ...)`.

## The Iron Law

```
NO SPEC WITHOUT SHARED UNDERSTANDING FIRST
```

If you cannot explain the design in one sentence, you are not ready for a
spec card. A vague spec produces vague code.

## Process

1. **Read project context** — `AGENTS.md`, `.apd/memory/MEMORY.md` and
   `.apd/memory/status.md`, source close to the idea.
2. **Ask ONE question at a time.** Never dump a list of 5 questions. Ask
   one, wait for the answer, ask the next.
3. **Present trade-offs, do not decide.** When real choices exist, offer
   2–3 concise options and let the user pick.
4. **Converge on a design.** Hand the user a short summary — Goal /
   Scope / Out of scope / Approach / Affected files. Wait for explicit
   approval.
5. **Only then** write `.apd/pipeline/spec-card.md` and call
   `apd_advance_pipeline('spec', '<name>')`.

## Do not do during brainstorming

- Write code
- Call `apd_guard_write`
- Edit any file outside `.apd/pipeline/`
- Advance the pipeline

Brainstorming produces a DESIGN. Implementation is the builder phase.

## Red flags — STOP and return to Ask-One-Question

| Thought | Reality |
|---------|---------|
| "This is simple, skip brainstorm" | Simple tasks have hidden complexity. 5 minutes of questions saves 30 minutes of rework. |
| "I already know what they want" | You know what YOU would build. Ask what THEY want. |
| "Let me just start coding and iterate" | Iteration without direction is waste. |
| "The user seems impatient" | Users are more impatient when you build the wrong thing. |
| "I'll figure it out during implementation" | Vague specs produce vague code. |
