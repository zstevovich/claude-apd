---
name: apd-debug
description: Use on any APD test failure, build failure, verifier block, or critical reviewer finding. Four-phase systematic debugging — root cause investigation, pattern analysis, hypothesis + controlled test, fix with TDD. Escalate after three failed hypotheses instead of piling on more guesses.
---

# APD Systematic Debugging (Codex)

**Use when:** a test fails, a build fails, the verifier step blocks the
pipeline, or the reviewer raises a critical finding. Do this BEFORE
re-running any pipeline step.

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

Guessing is not debugging. If you have not completed Phase 1, you cannot
propose a fix.

## Four phases

### Phase 1 — root cause investigation

1. **Read the error fully.** Don't skip the stack trace. Note
   file:line references, exception types, and the exact command that
   produced it.
2. **Reproduce reliably.** Can you trigger the failure consistently? If
   not, find a repro first — intermittent fixes are almost never fixes.
3. **Check recent changes.** `git diff`, recent commits on this pipeline.
4. **Trace the data flow.** Where does the bad value originate? What
   transformation produced it?

### Phase 2 — pattern analysis

1. Find working examples of similar code in this codebase.
2. Compare systematically — what is different between the working path
   and the broken path?
3. List every difference. Don't skip with "that can't matter" — the
   subtle ones are usually the answer.

### Phase 3 — hypothesis and controlled test

1. State the hypothesis as a sentence. "I think X causes Y because Z."
2. Test with the smallest possible change. One variable at a time.
3. Verify. Did it resolve the failure? If not, form a NEW hypothesis —
   don't layer fixes.
4. **3+ failed hypotheses → STOP** and escalate to the user with a
   clear summary of what you tried and what you learned.

### Phase 4 — fix with TDD

1. Write a failing test that reproduces the bug. Use the `apd-tdd`
   skill (or read `.apd/rules/tdd.md` when in an APD project).
2. Implement the minimum change that resolves the root cause. No
   unrelated cleanup in the same commit.
3. Run `apd_verify_step()` and make sure no other test regressed.

## Common rationalizations

| Excuse | Reality |
|--------|---------|
| "Quick fix for now, investigate later" | Later never comes. The quick fix masks the real bug. |
| "It's probably X, let me fix that" | "Probably" is a guess. Verify before fixing. |
| "Just try changing X and see" | Random changes aren't debugging. Trace data flow. |
| "I don't fully understand but this might work" | If you don't understand, your fix is random. Phase 1 first. |
| "The error message is misleading" | Maybe. Read it fully first. |
| "It works on my test, ship it" | Did you reproduce the ORIGINAL failure? Run the ORIGINAL failing test. |

## Return to Phase 1 if you catch yourself…

- Proposing a solution before tracing data flow
- Changing multiple things in one attempt
- Saying "it's probably…" without evidence
- Copy-pasting a fix you don't understand
- Starting a fourth hypothesis after three failed
