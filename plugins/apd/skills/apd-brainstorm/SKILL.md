---
name: apd-brainstorm
description: Use when an APD task is vague, broad, or has multiple reasonable interpretations — before writing the spec card and calling apd_advance_pipeline('spec', ...). Ask ONE question at a time, present 2-3 approaches when there are choices, converge on a design the user explicitly approves. Works hand in hand with `.apd/rules/brainstorm.md` when that file exists in the project.
---

# APD Brainstorm (Codex)

Finish brainstorming BEFORE calling `apd_advance_pipeline('spec', ...)`.

## When to use / When to skip

**Use when:**
- The task is vague, broad, or "improve X" style
- The user gave a destination but no path ("we need user search")
- Multiple reasonable interpretations exist
- You catch yourself making implementation choices the user hasn't seen

**Skip when:**
- The task is fully specified (file paths, function names, acceptance criteria)
- The user has already approved a design — write the spec card directly
- You are mid-pipeline (spec is locked; raise concerns to user, don't re-brainstorm)

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

## Exit criteria

You're done when:
- The user can restate the goal in one sentence and you both agree on it
- Scope and out-of-scope are explicit and written down
- Approach is named (architectural pattern, library choice, integration point)
- Affected files are listed (not just "wherever it goes")
- The user has explicitly approved the design summary — no implicit approval
- `.apd/pipeline/spec-card.md` has been written and `apd_advance_pipeline('spec', '<name>')` is the next call

## Hand-off

- After explicit approval → write the spec card and call `apd_advance_pipeline('spec', '<name>')` (the only valid exit)
- Never leads to: code, agent edits, file writes outside `.apd/pipeline/` — those come from the builder phase
- If the user asks for "just one quick thing" mid-brainstorm → finish the brainstorm first, then queue it
