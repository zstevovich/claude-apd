---
name: apd-debug
description: MANDATORY before re-dispatching the builder after any APD verifier block or critical reviewer finding on Codex. Use on any bug, test failure, build failure, error, crash, regression, or unexpected behavior. Four-phase systematic debugging — root cause investigation, pattern analysis, hypothesis + controlled test, fix with TDD. Escalate after three failed hypotheses instead of piling on more guesses. Triggers on "bug", "fail", "failing", "broken", "doesn't work", "error", "crash", "regression", "verifier blocked", "reviewer rejected".
---

# APD Systematic Debugging (Codex)

Do this BEFORE re-running any pipeline phase.

## When to use / When to skip

**Use when:**
- A test failed (unit, integration, or end-to-end)
- A build or compile failed
- The verifier step blocked the pipeline
- The reviewer raised a critical finding
- You are about to re-run a pipeline phase after a verifier failure (MANDATORY)

**Skip when:**
- The "failure" is actually expected behaviour (test marked skip/expected-fail)
- You haven't run the failing command yourself yet (run it first, get a real error message)
- The issue is a known intermittent and you have a tracking ticket — escalate, don't loop

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
3. Run `apd:apd_verify_step()` and make sure no other test regressed.

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

## Examples

**Example 1 — Phase 1 saves you from the wrong fix.**

*Input:* Builder reports `TypeError: Cannot read property 'id' of undefined at UserService.findById:42`. Tempting fix: add `if (user)` guard at line 42.

*Output (Phase 1):* Trace the data flow upstream. `findById` receives `userId` from `AuthMiddleware.parseToken()` which returns `undefined` when the token is missing the `sub` claim. Root cause: middleware silently passes `undefined` instead of rejecting malformed tokens. Right fix is at the middleware boundary, not the service guard. *Phase 4:* failing test "malformed token → 401", then validate in `parseToken`. Confirm with `apd:apd_verify_step()`.

**Example 2 — Pattern analysis spots the subtle difference.**

*Input:* New endpoint `POST /orders/:id/refund` returns 500 in CI, works locally. Tempting fix: wrap it in `try/catch` and swallow the error.

*Output (Phase 2):* Locate three working endpoints (`/orders/:id`, `/cancel`, `/ship`). Diff the registration order: working ones declare `router.use(authMiddleware)` BEFORE the route; the new one declares the route first. Express middleware order. *Phase 4:* failing integration test for unauthenticated `/refund` expecting 401 (currently 500), then reorder `router.use`. `apd:apd_verify_step()` confirms no regressions.

**Example 3 — Three failed hypotheses → escalate, don't form H4.**

*Input:* `apd:apd_verify_step()` blocks pipeline with `migration 0042 failed: column already exists`. H1 (add IF NOT EXISTS guard) fails. H2 (previous migration not rolled back) — no evidence. H3 (stale schema cache) — DB restart, still fails.

*Output:* STOP. Hand back to user with summary: "0042 fails 'column already exists'; tried IF-NOT-EXISTS, history check, cache restart. Need human inspection of CI schema state." Don't keep guessing — escalate per Iron Law.

## Exit criteria

You're done when:
- Root cause is named in one sentence with file:line evidence
- Failing test reproducing the bug exists and is committed (Phase 4)
- The single targeted fix turns the failing test green
- `apd:apd_verify_step()` confirms no regressions
- No unrelated cleanup snuck into the same change

## Hand-off

- After this skill completes → resume the pipeline phase that failed (re-run the affected phase)
- During Phase 4 (writing the failing test) → invoke `apd-tdd`
- After 3+ failed hypotheses → escalate to user with summary of what was tried; do NOT keep guessing
