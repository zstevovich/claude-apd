---
name: apd-tdd
description: MANDATORY for every APD builder dispatch. Use when implementing any feature, fixing any bug, or writing new code as a builder agent — write a FAILING test first, watch it fail, write minimal code to pass, refactor while green. Triggers on "implement", "add feature", "fix bug", "write code", "TDD", "test-first", "builder", any APD spec-card.md transitioning from spec → builder phase.
effort: xhigh
allowed-tools: Read Write Edit Glob Grep Bash
---

# APD Test-Driven Development

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over. No exceptions. Violating the letter IS violating the spirit.

## When to use / When to skip

**Use when:**
- You are inside the APD builder phase
- You are about to write or modify production code (any non-test source file)
- You are fixing a bug that has reached Phase 4 of `apd-debug`

**Skip when:**
- You are reading code without modifying it (use Read directly)
- You are running an existing test suite (use Bash directly)
- You are editing documentation, configuration, or scaffolding files

## Red-Green-Refactor

```dot
digraph tdd {
    RED [label="RED\nWrite failing test" style=filled fillcolor="#ffcccc"];
    RUN_RED [label="Run test\nWatch it FAIL" style=filled fillcolor="#ffcccc"];
    GREEN [label="GREEN\nMinimal code to pass" style=filled fillcolor="#ccffcc"];
    RUN_GREEN [label="Run test\nWatch it PASS" style=filled fillcolor="#ccffcc"];
    REFACTOR [label="REFACTOR\nClean up" style=filled fillcolor="#ccccff"];
    RUN_REFACTOR [label="Run test\nStill PASS?" style=filled fillcolor="#ccccff"];
    NEXT [label="Next behavior?"];

    RED -> RUN_RED;
    RUN_RED -> GREEN [label="fails ✓"];
    RUN_RED -> RED [label="passes — fix test"];
    GREEN -> RUN_GREEN;
    RUN_GREEN -> REFACTOR [label="passes ✓"];
    RUN_GREEN -> GREEN [label="fails — fix code"];
    REFACTOR -> RUN_REFACTOR;
    RUN_REFACTOR -> NEXT [label="passes ✓"];
    RUN_REFACTOR -> REFACTOR [label="fails — revert"];
    NEXT -> RED [label="yes"];
}
```

### 1. RED — Write Failing Test

Write ONE minimal test showing expected behavior:

```
test('deletes post by id', () => {
    // Arrange
    $repo->create(['title' => 'Test', 'url' => 'https://x.com']);
    // Act
    $result = $repo->delete(1);
    // Assert
    assertTrue($result);
    assertEmpty($repo->findAll());
});
```

**Run the test. Watch it FAIL.** If it passes — you are testing existing behavior, fix the test.

### 2. GREEN — Minimal Code to Pass

Write the SIMPLEST code that makes the test pass. Nothing more.

- No extra features
- No "while I'm here" improvements
- No over-engineering

### 3. REFACTOR — Clean Up

Only after green:
- Remove duplication
- Improve names
- Extract helpers

**Keep tests green throughout.**

### 4. REPEAT

Next failing test for next behavior.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests that pass immediately prove nothing. You must WATCH them fail first. |
| "Need to explore first" | Fine. Throw away exploration code, then start with TDD. |
| "TDD will slow me down" | TDD is faster than debugging. Every time. |
| "Manual test is faster" | Manual testing doesn't prove edge cases or prevent regressions. |
| "I can't test this" | You can't test the CURRENT design. Simplify the design. |
| "The framework makes TDD hard" | Test the behavior, not the framework. Mock the boundary. |

## When Stuck

| Problem | Solution |
|---------|----------|
| Don't know how to test | Write the API you wish existed. Assert first. |
| Test too complicated | Design too complicated. Simplify. |
| Must mock everything | Code too coupled. Use dependency injection. |
| Edge case explosion | Separate input validation from business logic. Test each. |

## Red Flags — STOP

- Writing a function before its test
- Test passes on first run (you are testing existing behavior)
- Multiple behaviors in one test
- "I'll add tests at the end"
- Refactoring while tests are red

## Exit criteria

You're done when:
- Every new function has at least one test that you watched fail
- All tests pass — both new and the prior suite (no regressions)
- Edge cases are covered (empty input, invalid input, boundary values)
- No production code exists that isn't exercised by a test
- Refactor pass left tests green

## Hand-off

- After this skill completes → builder phase advances via `pipeline-advance builder`
- Then dispatch the regular `code-reviewer` and run `pipeline-advance reviewer` — that step writes `.adversarial-pending` as the green light for adversarial dispatch
- Do NOT dispatch `adversarial-reviewer` before `reviewer.done` exists; the pre-flight gate (`track-agent` hook) exits 2 and the dispatch is wasted
- If a test goes red unexpectedly → switch to `apd-debug` (Phase 4 of debug uses this skill again)
- Never skip — even for "trivial" changes. Especially for trivial changes.
