# APD Skill Template

> Single source of truth for the structure of every APD skill on **both runtimes**
> (Claude Code and Codex). Every `skills/<name>/SKILL.md` (CC) and
> `plugins/apd/skills/<name>/SKILL.md` (Codex) must conform.

This document is the canon — not a working skill. Use it as the reference when
authoring new skills or auditing existing ones.

---

## 1. Frontmatter

### 1.1 Claude Code

```yaml
---
name: apd-<phase>
description: <one paragraph: TRIGGER cues, optional SKIP cues, optional MANDATORY tag>
effort: <min|low|med|high|max|xhigh>
allowed-tools: <explicit space-separated list — never omit>
disable-model-invocation: <true ONLY for manual-only skills>
---
```

| Field | Required | Notes |
|---|---|---|
| `name` | yes | kebab-case, prefixed `apd-` |
| `description` | yes | First sentence is a TRIGGER ("Use when ..."). Add SKIP cue if the description is broad enough to over-fire. Add MANDATORY tag if the skill is a hard-required gate ("MANDATORY before/after X"). |
| `effort` | yes | Pick from the taxonomy in §3. Don't invent new levels. |
| `allowed-tools` | yes | Explicit list. Default minimum: `Read Glob Grep`. Add `Bash` if the skill runs scripts. Add `Edit Write` only if the skill modifies files. Skills must never be tool-unbounded. |
| `disable-model-invocation` | no | Set `true` only for skills the user must invoke explicitly (e.g. `apd-setup` — bootstrap-only). Default: omit. |

### 1.2 Codex

```yaml
---
name: apd-<phase>
description: <one paragraph: TRIGGER cues, optional SKIP cues, optional MANDATORY tag>
---
```

Codex skill schema (0.124+) only honours `name` and `description`. No `effort`,
no `allowed-tools`, no `disable-model-invocation`. Tool scope on Codex is
enforced server-side via `apd_guard_write` / `guard-bash-scope`, not via skill
frontmatter — the body should reference the relevant guards explicitly.

---

## 2. Body — 4 mandatory + 2 optional sections

### 2.1 When to use / When to skip — MANDATORY

Two adjacent bullet lists, no prose preamble. The auto-invocation matcher
already fired on the description; this section is the **second filter** Claude
applies before doing real work.

```markdown
## When to use / When to skip

**Use when:**
- <concrete trigger condition 1>
- <concrete trigger condition 2>

**Skip when:**
- <case where description matches but skill should not fire>
- <case the user clearly meant something else>
```

### 2.2 Steps — MANDATORY

Numbered sequence. Each step starts with an action verb and names the concrete
target (file path, command, tool). Steps must be executable without re-reading
the rest of the skill.

```markdown
## Steps

1. <verb> <target> — <one-line context>
2. <verb> <target> — <one-line context>
3. ...
```

### 2.3 Exit criteria — MANDATORY

Bullet list of measurable conditions that mean the skill is done. "You're done
when ..." framing. No "consider", no "should" — definite.

```markdown
## Exit criteria

You're done when:
- <measurable condition 1>
- <measurable condition 2>
```

### 2.4 Anti-patterns — MANDATORY

Two valid formats — pick whichever matches the failure mode.

**Format A — Don't → Do pairs.** Action-oriented. Best for procedural skills
where the failure is wrong sequencing or wrong tool choice.

```markdown
## Anti-patterns

- **Don't** <failure mode> **→ Do** <correct alternative>
- **Don't** <failure mode> **→ Do** <correct alternative>
```

**Format B — Common Rationalizations table.** Anti-self-deception. Best for
skills where the failure mode starts with the orchestrator talking itself
into a shortcut (TDD, debug, brainstorm, finish).

```markdown
## Common rationalizations

| Excuse | Reality |
|---|---|
| <excuse the orchestrator tells itself> | <why the excuse is wrong> |
```

A skill may use both — typically rationalizations as the headline section and
Don't → Do pairs as a "Red Flags" follow-up. Generic platitudes ("don't be
sloppy") are forbidden in either format. Every entry must target a real
failure mode the orchestrator has hit before.

### 2.5 Iron Law — OPTIONAL

Use **only** when the skill has a genuine non-negotiable invariant. Examples:

- `apd-tdd`: "No production code without a failing test first."
- `apd-debug`: "Investigate root cause before applying any fix."

If the skill has no real invariant, omit this section. Forcing one yields
empty platitudes ("audit thoroughly") which add noise.

```markdown
## The Iron Law

> <one-sentence invariant>
```

### 2.6 Hand-off — OPTIONAL

Use when the skill has well-defined transitions to other skills. Be explicit
about both the trigger and the target.

```markdown
## Hand-off

- After this skill completes successfully → invoke `apd-<next>`
- If <failure mode> → switch to `apd-debug`
```

---

## 3. Effort taxonomy

| Level | Wall time | Shape | Examples |
|---|---|---|---|
| `min` | < 10s | single tool call, trivial | (reserved; APD does not currently use) |
| `low` | < 30s | a few tool calls, status checks | (reserved; APD does not currently use) |
| `med` | ~1 min | multi-step decision with branching | (reserved; APD does not currently use) |
| `high` | minutes | substantial structured work, may stop & wait for input | `apd-finish`, `apd-github`, `apd-miro` |
| `max` | minutes, mandatory checks | long-running phase work, no shortcuts | `apd-setup`, `apd-audit`, `apd-brainstorm`, `apd-debug` |
| `xhigh` | minutes, must complete iterative loop | TDD-style red→green→refactor cycles | `apd-tdd` |

Pick the lowest level that honestly describes the skill's shape. Inflating
effort is just as bad as deflating: callers use it to budget time and tokens.

---

## 4. Cross-runtime parity

| Skill | CC | Codex | Reason |
|---|---|---|---|
| `apd-setup` | yes | NO | Replaced on Codex by `apd cdx init` CLI; a skill wrapper would be empty |
| `apd-audit` | yes | yes | Logic is runtime-agnostic |
| `apd-brainstorm` | yes | yes | Logic is runtime-agnostic |
| `apd-debug` | yes | yes | Logic is runtime-agnostic |
| `apd-finish` | yes | yes | Logic is runtime-agnostic |
| `apd-github` | yes | yes | Integration usable from either runtime |
| `apd-miro` | yes | yes | Integration usable from either runtime |
| `apd-tdd` | yes | yes | Logic is runtime-agnostic |

Total: **8 CC skills, 7 Codex skills.** The body of paired skills should be
near-identical, differing only where the runtime forces it (e.g. CC says
"Read the spec card with the Read tool"; Codex says "Read the spec card
through `apd_guard_write`-aware Read"). Drift between paired bodies must be
called out in code review.

---

## 5. Worked example — `apd-tdd` (excerpt)

```markdown
---
name: apd-tdd
description: Use when implementing any feature or fixing any bug as a Builder agent. Write a failing test first, then minimal code to pass. MANDATORY for all APD builder dispatches.
effort: xhigh
allowed-tools: Read Write Edit Glob Grep Bash
---

# APD Test-Driven Development

## The Iron Law

> No production code without a failing test first.

## When to use / When to skip

**Use when:**
- You are inside the APD builder phase
- You are about to write or modify production code

**Skip when:**
- You are reading code without modifying it
- You are running tests that already exist (use Bash directly)

## Steps

1. Read the spec card and acceptance criteria
2. Write the smallest failing test that captures the next acceptance bullet
3. Run the test, confirm it fails for the right reason
4. Write the minimum code to make the test pass
5. Run the full test suite, confirm green
6. Refactor while green — no new behaviour
7. Repeat from step 2 until acceptance criteria are covered

## Exit criteria

You're done when:
- Every acceptance bullet has at least one passing test
- The full test suite is green
- No production code exists that is not exercised by a test

## Anti-patterns

- **Don't** write code first then add tests after → **Do** write a failing test first, every time
- **Don't** write a sweeping test that asserts a whole feature → **Do** the smallest test that fails for one acceptance bullet
- **Don't** refactor while red → **Do** get to green first, then refactor

## Hand-off

- After this skill completes → builder phase advances via `apd_advance_pipeline('builder')`
- If the test suite goes red after step 5 → switch to `apd-debug`
```

---

## 6. Maintenance

- Any change to this template must update **every** skill in the same commit
  (same rule as `docs/SPEC.md`).
- The template is the spec; individual skills are implementations. Drift goes
  in this file, not in skills.
- New effort levels, new mandatory sections, new frontmatter fields all
  require a CHANGELOG entry.
