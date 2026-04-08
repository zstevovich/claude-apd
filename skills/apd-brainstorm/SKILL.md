---
name: apd-brainstorm
description: Explore requirements and design before the APD spec phase. Collaborative dialogue to turn vague ideas into concrete specs.
effort: max
---

# APD Brainstorm

Turn a vague idea into a concrete spec through collaborative dialogue.

## When to Use

- User says "I want to add X" but details are unclear
- Feature has multiple possible approaches
- Scope needs to be defined before writing a spec
- User wants to think through trade-offs

## Process

### 1. Understand Context

Read the project:
- CLAUDE.md for stack and architecture
- Recent session-log for what was done before
- Existing code related to the idea

### 2. Ask One Question at a Time

**Do NOT dump a list of 10 questions.** Ask one, wait for answer, ask next.

Good:
```
What problem does this solve for the user?
```

Bad:
```
Here are my questions:
1. What problem does this solve?
2. Who is the target user?
3. What's the priority?
4. Should it be real-time?
5. What about mobile?
...
```

### 3. Explore Trade-offs

Present options concisely when there are choices:

```
Two approaches:
A) Server-rendered — simpler, faster initial load, no JS complexity
B) AJAX — smoother UX, no page reload, more JS code

Which fits better for this project?
```

### 4. Converge on Design

When enough is clear, present the design:

```
Here's what I understand:

Goal: [one sentence]
Scope: [what's included]
Out of scope: [what's not]
Approach: [technical approach]
Affected files: [list]

Ready to write the spec card?
```

### 5. Hand Off to Spec

Once user approves the design → write the spec card and enter the APD pipeline:

```bash
pipeline-advance.sh spec "Feature name"
```

**HARD GATE:** Do NOT write code during brainstorming. This skill produces a DESIGN, not an implementation. Code comes from Builder agents after the spec is approved.

## Rules

- One question at a time
- Listen more than propose
- Present trade-offs, don't decide for the user
- No code during brainstorming
- End with a clear design that feeds into the spec
