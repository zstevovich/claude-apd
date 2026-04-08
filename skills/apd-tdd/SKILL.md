---
name: apd-tdd
description: Test-Driven Development for APD Builder agents. Write failing test first, then minimal code to pass. Use when implementing features or fixing bugs.
effort: high
---

# APD Test-Driven Development

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over. No exceptions.

## Red-Green-Refactor

### 1. RED — Write failing test

Write ONE minimal test showing the expected behavior.

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

**Run the test. Watch it FAIL.** If it passes — you're testing existing behavior, fix the test.

### 2. GREEN — Minimal code to pass

Write the SIMPLEST code that makes the test pass. Nothing more.

- No extra features
- No "while I'm here" improvements
- No over-engineering

### 3. REFACTOR — Clean up

Only after green:
- Remove duplication
- Improve names
- Extract helpers

**Keep tests green throughout.**

### 4. REPEAT

Next failing test for next behavior.

## Within APD Pipeline

This skill is used by **Builder agents** during the implementation phase:

```
Orchestrator creates spec → user approves
Orchestrator dispatches Builder:
  Builder uses TDD:
    RED → GREEN → REFACTOR for each behavior
    All tests pass when done
Orchestrator dispatches Reviewer
Verifier runs build + test
One commit
```

The Builder agent uses TDD internally — the orchestrator does not need to know the details.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "Need to explore first" | Fine. Throw away exploration, start with TDD. |
| "TDD will slow me down" | TDD is faster than debugging. |
| "Manual test faster" | Manual doesn't prove edge cases. |

## When Stuck

| Problem | Solution |
|---------|----------|
| Don't know how to test | Write the API you wish existed. Assert first. |
| Test too complicated | Design too complicated. Simplify. |
| Must mock everything | Code too coupled. Use dependency injection. |

## Checklist

Before marking task complete:
- [ ] Every new function has a test
- [ ] Watched each test fail before implementing
- [ ] Wrote minimal code to pass
- [ ] All tests pass
- [ ] Edge cases covered
