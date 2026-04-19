# APD Test-Driven Development (Codex)

**Read this file when:** you are implementing a feature or fixing a bug
inside the builder phase. On Codex the orchestrator IS the builder — this
applies to every implementation you do between `apd_advance_pipeline('spec', ...)`
and `apd_advance_pipeline('builder')`.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over. No exceptions. Violating
the letter IS violating the spirit.

## Red → Green → Refactor

```
┌────────────┐       ┌──────────────┐       ┌────────────┐
│    RED     │  pass │    GREEN     │  pass │  REFACTOR  │
│ Write test ├──fail→│ Minimal code ├──pass→│  Clean up  │
└────────────┘       └──────────────┘       └─────┬──────┘
      ↑                                            │
      └──────────── next behavior ─────────────────┘
```

### 1. RED — write a failing test FIRST

Write ONE minimal test that describes the behavior you want:

```typescript
test('deletes post by id', async () => {
    await repo.create({ title: 'Test', url: 'https://x.com' });
    const result = await repo.delete(1);
    expect(result).toBe(true);
    expect(await repo.findAll()).toHaveLength(0);
});
```

**Run it. Watch it fail.** Before every write, call
`apd_guard_write("<builder-role>", test_file_path)`. The server reads the
role's scope from `.apd/agents/<role>.md` itself — you only pass the role
name and target. Exit 2 means BLOCK; move the test to a path inside scope.

If the test passes on the first run, you are testing existing behavior —
fix the test to actually describe the new requirement.

### 2. GREEN — minimal code to pass

Write the SIMPLEST code that makes the test pass. Nothing more.

- No extra features
- No "while I'm here" improvements
- No over-engineering

### 3. REFACTOR — clean up (tests stay green)

Only once the test passes:

- Remove duplication
- Improve names
- Extract helpers

If a test goes red during refactoring, revert immediately.

### 4. Next behavior

Pick the next behavior. Write the next failing test. Repeat.

## Scope enforcement on every write

Builder scope is declared in the agent file's frontmatter
(`.apd/agents/<role>.md`, `scope:` list). Call
`apd_guard_write("<role>", "<target-path>")` before every Write/Edit — the
server reads scope from the agent file on every call, so you cannot widen
it by manipulating arguments. Use `apd_list_agents()` once to discover
which role names are defined.

Do NOT bypass `apd_guard_write` with direct Bash writes — `guard-bash-scope`
blocks writes into `.apd/pipeline/` and reviewed-files scope, and the
whole pipeline will fail the verifier if scope was evaded.

## Common rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests that pass immediately prove nothing. You must WATCH them fail first. |
| "Need to explore first" | Fine. Throw away exploration code, then start with TDD. |
| "TDD will slow me down" | TDD is faster than debugging. Every time. |
| "Manual test is faster" | Manual testing doesn't prove edge cases or prevent regressions. |
| "I can't test this" | You can't test the CURRENT design. Simplify the design. |

## Checklist before calling `apd_advance_pipeline('builder')`

- [ ] Every new function has a test
- [ ] Watched each test fail before implementing
- [ ] Wrote minimal code to pass
- [ ] All tests pass locally
- [ ] Edge cases covered
- [ ] Every write went through `apd_guard_write`
