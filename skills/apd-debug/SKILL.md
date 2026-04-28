---
name: apd-debug
description: MANDATORY before re-dispatching the builder after any APD verifier failure or critical reviewer finding. Use on any bug, test failure, build failure, error, crash, regression, or unexpected behavior during the APD pipeline. Four-phase root-cause analysis — investigate, pattern-match, hypothesize + controlled test, fix with TDD. Triggers on "bug", "fail", "failing", "broken", "doesn't work", "error", "crash", "regression", "verifier blocked", "reviewer rejected".
effort: max
allowed-tools: Read Glob Grep Bash
---

# APD Systematic Debugging

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you have not completed Phase 1, you CANNOT propose fixes. Guessing is not debugging. Violating the letter IS violating the spirit.

## When to use / When to skip

**Use when:**
- A test failed (unit, integration, or end-to-end)
- A build or compile failed
- The verifier blocked the pipeline
- The reviewer raised a critical finding
- You are about to re-dispatch a builder after a verifier failure (MANDATORY)

**Skip when:**
- The "failure" is actually expected behaviour (test marked skip/expected-fail)
- You haven't run the failing command yourself yet (run it first, get a real error message)
- The issue is a known intermittent and you have a tracking ticket — escalate, don't loop

## Four Phases

```dot
digraph debug {
    P1 [label="Phase 1\nRoot Cause Investigation" style=filled fillcolor="#ffcccc"];
    P2 [label="Phase 2\nPattern Analysis"];
    P3 [label="Phase 3\nHypothesis & Test"];
    P4 [label="Phase 4\nFix with TDD"];
    ESCALATE [label="ESCALATE\n3+ failed fixes\nAsk orchestrator/user" style=filled fillcolor="#ffffcc"];

    P1 -> P2;
    P2 -> P3;
    P3 -> P4 [label="hypothesis confirmed"];
    P3 -> P3 [label="hypothesis wrong\nnew hypothesis"];
    P3 -> ESCALATE [label="3+ failures"];
    P4 -> P1 [label="fix doesn't work"];
}
```

### Phase 1: Root Cause Investigation

**BEFORE attempting ANY fix:**

1. **Read error messages carefully** — don't skip stack traces
2. **Reproduce consistently** — can you trigger it reliably?
3. **Check recent changes** — `git diff`, recent commits
4. **Trace data flow** — where does the bad value originate?

### Phase 2: Pattern Analysis

1. **Find working examples** — similar code in the same codebase that works
2. **Compare** — what's different between working and broken?
3. **List every difference** — don't assume "that can't matter"

### Phase 3: Hypothesis and Testing

1. **State hypothesis clearly** — "I think X causes Y because Z"
2. **Test with SMALLEST change** — one variable at a time
3. **Verify** — did it work? If not, form NEW hypothesis
4. **3+ failed fixes → STOP** — escalate to orchestrator/user

### Phase 4: Fix with TDD

1. **Write failing test** reproducing the bug (use `/apd-tdd`)
2. **Implement single fix** — root cause only, no extras
3. **Verify** — test passes, no regressions

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Quick fix for now, investigate later" | Later never comes. The quick fix masks the real bug. |
| "It's probably X, let me fix that" | "Probably" is a guess. Verify before fixing. |
| "Just try changing X and see" | Changing random things is not debugging. Trace the data flow. |
| "I don't fully understand but this might work" | If you don't understand, your fix is random. Phase 1 first. |
| "The error message is misleading" | Maybe. But read it fully before deciding it lies. |
| "It works on my test, ship it" | Did you reproduce the ORIGINAL failure? Run the ORIGINAL failing test. |

## Red Flags — Return to Phase 1

- Proposing solutions before tracing data flow
- Changing multiple things at once
- "It's probably..." without evidence
- Copy-pasting a Stack Overflow fix without understanding it
- 3+ fixes failed and still guessing

## Quick Reference

| Phase | Do | Don't |
|-------|-----|-------|
| 1. Root Cause | Read errors, reproduce, trace | Guess, skip traces |
| 2. Pattern | Find working code, compare | Assume differences don't matter |
| 3. Hypothesis | One change, verify | Multiple changes at once |
| 4. Fix | Failing test first, single fix | Fix without test, bundle changes |

## Examples

**Example 1 — Phase 1 saves you from the wrong fix.**

*Input:* Builder reports `TypeError: Cannot read property 'id' of undefined at UserService.findById:42`. Tempting fix: add `if (user)` guard at line 42.

*Output (Phase 1):* Trace the data flow upstream. `findById` receives `userId` from `AuthMiddleware.parseToken()` which returns `undefined` when the token is missing the `sub` claim. Root cause: middleware silently passes `undefined` instead of rejecting malformed tokens. Right fix is at the middleware boundary, not the service guard. *Phase 4:* failing test "malformed token → 401", then validate in `parseToken`.

**Example 2 — Pattern analysis spots the subtle difference.**

*Input:* New endpoint `POST /orders/:id/refund` returns 500 in CI, works locally. Builder is about to wrap it in `try/catch` and swallow the error.

*Output (Phase 2):* Locate three working endpoints (`/orders/:id`, `/cancel`, `/ship`). Diff the registration order: working ones declare `router.use(authMiddleware)` BEFORE the route; the new one declares the route first. Express middleware order. *Phase 4:* failing integration test for unauthenticated `/refund` expecting 401 (currently 500), then reorder `router.use`.

**Example 3 — Three failed hypotheses → escalate, don't form H4.**

*Input:* Verifier blocks pipeline with `migration 0042 failed: column already exists`. H1 (add IF NOT EXISTS guard) fails. H2 (previous migration not rolled back) — no evidence in history. H3 (stale schema cache) — DB restart, still fails.

*Output:* STOP. Hand back to user with summary: "0042 fails 'column already exists'; tried IF-NOT-EXISTS, history check, cache restart. Need human inspection of CI schema state." Don't keep guessing — escalate per Iron Law.

## Exit criteria

You're done when:
- Root cause is named in one sentence with file:line evidence
- Failing test reproducing the bug exists and is committed (Phase 4)
- The single targeted fix turns the failing test green
- Full test suite passes — no regressions
- No unrelated cleanup snuck into the same change

## Hand-off

- After this skill completes → resume the pipeline phase that failed (re-dispatch builder, re-run verifier)
- During Phase 4 (writing the failing test) → invoke `apd-tdd`
- After 3+ failed hypotheses → escalate to user with summary of what was tried; do NOT keep guessing
