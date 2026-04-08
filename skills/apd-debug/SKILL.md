---
name: apd-debug
description: Systematic debugging for APD Builder agents. Find root cause before proposing fixes. Use when encountering any bug, test failure, or unexpected behavior.
effort: max
---

# APD Systematic Debugging

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST
```

If you haven't completed Phase 1, you cannot propose fixes.

## Four Phases

### Phase 1: Root Cause Investigation

**BEFORE attempting ANY fix:**

1. **Read error messages carefully** — don't skip stack traces
2. **Reproduce consistently** — can you trigger it reliably?
3. **Check recent changes** — git diff, recent commits
4. **Trace data flow** — where does the bad value originate?

### Phase 2: Pattern Analysis

1. **Find working examples** — similar code in the same codebase that works
2. **Compare** — what's different between working and broken?
3. **List every difference** — don't assume "that can't matter"

### Phase 3: Hypothesis and Testing

1. **State hypothesis clearly** — "I think X causes Y because Z"
2. **Test with SMALLEST change** — one variable at a time
3. **Verify** — did it work? If not, form NEW hypothesis
4. **3+ failed fixes → STOP** — question the architecture, ask the user

### Phase 4: Implementation

1. **Write failing test** reproducing the bug (use `/apd-tdd`)
2. **Implement single fix** — root cause only, no extras
3. **Verify** — test passes, no regressions

## Within APD Pipeline

This skill is used by **Builder agents** when they encounter failures:

```
Builder implementing feature → test fails unexpectedly
Builder uses /apd-debug:
  Phase 1: Investigate root cause
  Phase 2: Analyze patterns
  Phase 3: Form and test hypothesis
  Phase 4: Write failing test + fix
Builder continues with implementation
```

**The Builder does NOT ask the orchestrator for help** unless 3+ fixes fail (architectural problem).

## Red Flags — STOP and Return to Phase 1

- "Quick fix for now, investigate later"
- "Just try changing X and see if it works"
- "It's probably X, let me fix that"
- "I don't fully understand but this might work"
- Proposing solutions before tracing data flow
- 3+ fixes failed → question the architecture

## Quick Reference

| Phase | Do | Don't |
|-------|-----|-------|
| 1. Root Cause | Read errors, reproduce, trace | Guess, skip traces |
| 2. Pattern | Find working code, compare | Assume differences don't matter |
| 3. Hypothesis | One change, verify | Multiple changes at once |
| 4. Fix | Failing test first, single fix | Fix without test, bundle changes |
