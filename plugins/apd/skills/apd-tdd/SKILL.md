---
name: apd-tdd
description: Use during the APD builder phase (between apd_advance_pipeline('spec', ...) and apd_advance_pipeline('builder')) whenever you're implementing a feature or fixing a bug. Write a FAILING test first, watch it fail, write minimal code to pass, refactor while green. Every file write must go through apd_guard_write(apd_role, file_path) — scope is enforced server-side from .apd/agents/<apd_role>.md.
---

# APD Test-Driven Development (Codex)

On Codex the orchestrator IS the builder — this skill applies to every
implementation between `apd_advance_pipeline('spec', ...)` and
`apd_advance_pipeline('builder')`.

## When to use / When to skip

**Use when:**
- You are inside the APD builder phase
- You are about to write or modify production code (any non-test source file)
- You are fixing a bug that has reached Phase 4 of `apd-debug`

**Skip when:**
- You are reading code without modifying it
- You are running an existing test suite (use shell directly)
- You are editing documentation, configuration, or scaffolding files

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over. No exceptions.

## Red → Green → Refactor

### 1. RED — failing test first

Write ONE minimal test that describes the behavior you want. **Run it.
Watch it fail.** If it passes on the first run, you are testing existing
behavior — fix the test to actually describe the new requirement.

Before each test-file write, call
`apd_guard_write(apd_role="<role>", file_path="<path>")`. The server reads
scope from `.apd/agents/<role>.md` on every call — you only pass the role
name and target path. Use `apd_list_agents()` to discover which roles are
defined. (Argument is `apd_role`, not `role`, to dodge Codex 0.121.0's
multi_agent role-mismatch approval prompt.)

### 2. GREEN — minimal code to pass

Write the SIMPLEST code that makes the test pass. Nothing more.

- No extra features
- No "while I'm here" improvements
- No over-engineering

### 3. REFACTOR — clean up (tests stay green)

Only once green: remove duplication, improve names, extract helpers. If a
test goes red during refactoring, revert immediately.

### 4. Next behavior

Pick the next behavior. Write the next failing test. Repeat.

## Scope enforcement on every write

Builder scope is declared in the agent frontmatter
(`.apd/agents/<role>.md`, `scope:` list). Call
`apd_guard_write(apd_role="<role>", file_path="<path>")` before every
Write/Edit — the server reads scope from the agent file itself, so the
role name is the only handle you need (and can't widen).

Do NOT bypass with direct Bash writes — `guard-bash-scope` blocks writes
into `.apd/pipeline/` and reviewed-files scope, and the verifier will
fail the cycle.

## Common rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests that pass immediately prove nothing. WATCH them fail first. |
| "Need to explore first" | Fine. Throw away exploration code, then start with TDD. |
| "TDD will slow me down" | TDD is faster than debugging. Every time. |
| "Manual test is faster" | Manual testing doesn't prove edge cases or prevent regressions. |
| "I can't test this" | You can't test the CURRENT design. Simplify the design. |

## Exit criteria

You're done when:
- Every new function has a test you watched fail
- All tests pass locally — both new and the prior suite (no regressions)
- Edge cases are covered (empty input, invalid input, boundary values)
- Every write went through `apd_guard_write(apd_role=..., file_path=...)`
- No unrelated files touched outside the agent's `scope:`
- Refactor pass left tests green

## Hand-off

- After this skill completes → call `apd_advance_pipeline('builder')`
- If a test goes red unexpectedly → switch to `apd-debug` (Phase 4 of debug uses this skill again)
- Never skip — even for "trivial" changes. Especially for trivial changes.
