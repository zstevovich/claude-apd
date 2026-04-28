---
name: apd-brainstorm
description: Use BEFORE writing the APD spec card whenever the task is vague, broad, ambiguous, or has multiple reasonable approaches. Asks ONE question at a time, presents 2-3 options when there are real choices, converges on a design the user explicitly approves. Triggers on "improve X", "what should we", "thinking about", "options", "not sure", "maybe", "vague", "broad", "redesign", any spec card with unclear scope or fewer than 3 R-criteria.
effort: max
allowed-tools: Read Glob Grep
---

# APD Brainstorm

## The Iron Law

```
NO SPEC WITHOUT SHARED UNDERSTANDING FIRST
```

If you cannot explain the design in one sentence — you are not ready for a spec.

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

## Process

```dot
digraph brainstorm {
    "Receive vague task" -> "Read project context";
    "Read project context" -> "Ask ONE question";
    "Ask ONE question" -> "User answers";
    "User answers" -> "Enough clarity?" [shape=diamond];
    "Enough clarity?" -> "Ask ONE question" [label="no"];
    "Enough clarity?" -> "Present 2-3 approaches";
    "Present 2-3 approaches" -> "User picks";
    "User picks" -> "Present design summary";
    "Present design summary" -> "User approves?" [shape=diamond];
    "User approves?" -> "Revise" [label="no"];
    "Revise" -> "Present design summary";
    "User approves?" -> "pipeline-advance spec" [label="yes"];
}
```

### 1. Read Context

- CLAUDE.md — stack, architecture
- Recent session-log — what was done before
- Existing code related to the idea

### 2. Ask One Question at a Time

**Do NOT dump a list of questions.** Ask one, wait, ask next.

Good: `What problem does this solve for the user?`

Bad:
```
1. What problem does this solve?
2. Who is the target user?
3. What's the priority?
...
```

### 3. Explore Trade-offs

When there are choices, present 2-3 options concisely:

```
Two approaches:
A) Server-rendered — simpler, faster initial load, no JS complexity
B) AJAX — smoother UX, no page reload, more JS code

Which fits better?
```

### 4. Converge on Design

When enough is clear:

```
Goal: [one sentence]
Scope: [what's included]
Out of scope: [what's not]
Approach: [technical approach]
Affected files: [list]

Ready to write the spec card?
```

### 5. Hand Off to Spec

Once user approves → write spec card and enter pipeline:

```bash
bash .claude/bin/apd pipeline spec "Feature name"
```

<HARD-GATE>
Do NOT write code during brainstorming. This skill produces a DESIGN, not an implementation. Code comes from Builder agents after the spec is approved.
</HARD-GATE>

## Red Flags — STOP

| Thought | Reality |
|---------|---------|
| "This is simple enough, skip brainstorm" | Simple tasks have hidden complexity. 5 minutes of questions saves 30 minutes of rework. |
| "I already know what they want" | You know what YOU would build. Ask what THEY want. |
| "Let me just start coding and iterate" | Iteration without direction is waste. Design first. |
| "The user seems impatient" | Users are more impatient when you build the wrong thing. |
| "I'll figure it out during implementation" | Builder agents follow specs. Vague specs produce vague code. |

## Rules

- One question at a time
- Listen more than propose
- Present trade-offs, don't decide for the user
- No code during brainstorming
- End with a clear design that feeds into the spec

## Exit criteria

You're done when:
- The user can restate the goal in one sentence and you both agree on it
- Scope and out-of-scope are explicit and written down
- Approach is named (architectural pattern, library choice, integration point)
- Affected files are listed (not just "wherever it goes")
- The user has explicitly approved the design summary — no implicit approval

## Hand-off

- After explicit approval → write the spec card and call `pipeline-advance spec "<name>"` (the only valid exit)
- Never leads to: code, agents, implementation — those come from the builder phase
- If the user asks for "just one quick thing" mid-brainstorm → finish the brainstorm first, then queue it
