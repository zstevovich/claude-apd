# APD Brainstorm (Codex)

**Read this file when:** the task you received is vague, broad, has multiple
reasonable interpretations, or is an "improve X" style ask. Finish
brainstorming BEFORE calling `apd_advance_pipeline('spec', ...)`.

## The Iron Law

```
NO SPEC WITHOUT SHARED UNDERSTANDING FIRST
```

If you cannot explain the design in one sentence, you are not ready for a
spec card. A vague spec produces vague code.

## Process

```
vague task → read context → one question → user answers → (enough clarity?)
                                     ↑                           ↓
                                     └────── no ──────┘          yes
                                                                  ↓
                                                       present 2–3 approaches
                                                                  ↓
                                                        user picks approach
                                                                  ↓
                                                      design summary to user
                                                                  ↓
                                                        (user approves?)
                                                         no → revise
                                                         yes → apd_advance_pipeline('spec', '<name>')
```

### 1. Read context first

- `AGENTS.md` — stack, conventions, entry points the user filled in
- `.apd/memory/MEMORY.md` and `.apd/memory/status.md` — what was done
  recently, what is in motion
- Existing source close to the idea — how is similar work done here?

### 2. Ask ONE question at a time

Do **not** dump a list of 5 questions. Ask one, wait for the answer, ask
the next. This keeps the user's attention anchored and reveals hidden
constraints one layer at a time.

- Good: `What problem does this feature solve for the user?`
- Bad: `1. What problem... 2. Target user... 3. Priority... 4. ...`

### 3. Present trade-offs, do not decide

When real choices exist, spell 2–3 concise options:

```
Two approaches:
A) Server-rendered — simpler, slower initial interaction, no JS plumbing
B) Client-side fetch — smoother UX, more JS, extra error surface

Which fits this codebase better?
```

### 4. Converge on a design

When enough is clear, hand the user a short summary:

```
Goal: <one sentence>
Scope: <what's in>
Out of scope: <what's out>
Approach: <one-paragraph technical direction>
Affected files: <list>
Pipeline mode: Full | Lean  (see AGENTS.md)
```

**Pick Lean only when ALL are true:** fewer than 5 affected files, no
migration, no auth/session, no public-API or wire-protocol change, no
security-sensitive surface, no cross-module refactor. Otherwise go Full.
When in doubt, Full. If you pick Lean, add `adversarial: skip — <reason>`
in the spec card (honored only when ≤ 2 R-criteria).

Wait for explicit approval. Then — and only then — write
`.apd/pipeline/spec-card.md` and call
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
