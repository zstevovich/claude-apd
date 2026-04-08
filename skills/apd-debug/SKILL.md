---
name: apd-debug
description: Use when encountering any bug, test failure, build failure, or unexpected behavior during APD pipeline. MANDATORY before re-dispatching builder after verifier failure or critical review finding.
effort: max
allowed-tools: Read Glob Grep Bash
---

# APD Systematic Debugging

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you have not completed Phase 1, you CANNOT propose fixes. Guessing is not debugging. Violating the letter IS violating the spirit.

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

## Integration

- **Called by:** Orchestrator when verifier fails or reviewer finds critical bugs (workflow.md step 7)
- **Pairs with:** `/apd-tdd` for Phase 4 (fix with failing test)
- **Escalates to:** Orchestrator/user after 3+ failed hypotheses
