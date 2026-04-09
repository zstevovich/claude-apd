# Implementation Plan Step + Enforcement Gaps — Design Document

## Overview

Two complementary changes: (1) orchestrator writes implementation-plan.md before dispatching builder, (2) enforcement gaps fixed — hard block for spec-card.md and implementation-plan.md, soft warn for adversarial-summary.

## Problem

**Plan step:** Orchestrator reads files before dispatch but that knowledge stays in session context — builder doesn't see it. Builder wastes tokens re-reading and searching the codebase. A plan file bridges the gap.

**Enforcement gaps:** Real-world testing (efiskalizacija, 2026-04-09) showed orchestrator doesn't consistently write spec-card.md and .adversarial-summary despite workflow rules. Spec traceability was a no-op (verify-trace.sh found no spec-card.md, exited 0). Adversarial reviewer ran but session-log showed N/A because no summary was written.

## Solution

### pipeline-advance.sh — 3 changes

**1. Spec step — hard block spec-card.md**

Currently: validates R* format IF spec-card.md exists, allows advance without it.
Change: `pipeline-advance.sh spec` BLOCKS (exit 1) if `.pipeline/spec-card.md` does not exist.

```
BLOCKED: spec-card.md not found.

  Write the spec card to .claude/.pipeline/spec-card.md before advancing.
  Acceptance criteria must use R1:, R2:, ... format.
```

**2. Builder step — hard block implementation-plan.md**

New check in `pipeline-advance.sh builder`: BLOCKS (exit 1) if `.pipeline/implementation-plan.md` does not exist.

```
BLOCKED: implementation-plan.md not found.

  Write the implementation plan to .claude/.pipeline/implementation-plan.md before advancing.
  List files to change with 1-2 sentences per file describing the change.
```

**3. Verifier step — soft warn adversarial-summary**

Before creating `verifier.done`: if `.claude/agents/adversarial-reviewer.md` exists in the project but `.pipeline/.adversarial-summary` does not exist, show a warning. Does NOT block.

```
! Adversarial reviewer is configured but was not used.
  Write ADVERSARIAL:total:accepted:dismissed to .pipeline/.adversarial-summary
```

### Cleanup

`.pipeline/implementation-plan.md` added to all cleanup locations:
- Spec step (start of new task)
- Reset step (after commit)
- Rollback of builder step

### workflow.md — 2 changes

**1. Flow diagram update**

Step 4 clarified:
```
4. WRITE IMPLEMENTATION PLAN
   → Analyze codebase, write .pipeline/implementation-plan.md
   → List files to create/modify with concrete change descriptions
   → pipeline-advance.sh builder validates plan exists
```

**2. New section: Implementation plan format**

```markdown
### Implementation plan format
**File:** `.claude/.pipeline/implementation-plan.md`
- List of files to create/modify
- 1-2 sentences per file describing the concrete change
- No code snippets — implementation decisions are the builder's job
- Orchestrator reads relevant code BEFORE writing the plan
```

### templates/agent-template.md — 1 change

Builder workflow step 1 updated:

From: `Read .claude/.pipeline/spec-card.md for acceptance criteria (R1, R2, ...)`
To: `Read .claude/.pipeline/implementation-plan.md for what to change and .claude/.pipeline/spec-card.md for acceptance criteria`

## What Does NOT Change

- verify-trace.sh — unchanged
- Guard scripts — unchanged
- hooks.json — unchanged
- Reviewer and adversarial reviewer templates — unchanged
- pipeline-gate.sh — unchanged (still 4 gates: spec, builder, reviewer, verifier)
- Pipeline state machine — no new .done files

## Backward Compatibility

Hard blocks on spec-card.md and implementation-plan.md mean existing projects must write these files. This is intentional — without them, spec traceability and plan-driven building don't work. Projects updating via `/apd-setup` get the new workflow.md rules automatically.

## Files Changed

| File | Change |
|------|--------|
| `scripts/pipeline-advance.sh` | Hard block spec-card.md (spec step), hard block implementation-plan.md (builder step), soft warn adversarial-summary (verifier step), cleanup lines |
| `rules/workflow.md` | Step 4 clarified, implementation plan format section |
| `templates/agent-template.md` | Builder reads implementation-plan.md |
