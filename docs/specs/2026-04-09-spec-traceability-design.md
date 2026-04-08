# Spec Traceability — Design Document

## Overview

Mechanical verification that every spec acceptance criterion has test coverage. Builders add `@trace R*` markers in test files; a bash script compares markers against spec-card.md before allowing commit.

## Problem

Specs exist only in Claude Code session context. No persistent link between requirements and code/tests. After commit, there's no mechanical way to verify that all acceptance criteria were implemented and tested. Everything depends on builder's memory and reviewer's attention.

## Solution

### spec-card.md — Ephemeral Spec Persistence

**Location:** `.claude/.pipeline/spec-card.md`

**Lifecycle:** Born during spec step, verified before commit, deleted on pipeline reset.

**Format:**
```markdown
## Task name
**Goal:** One sentence.
**Effort:** max | high
**Out of scope:** What we are NOT doing.
**Acceptance criteria:**
- R1: First requirement
- R2: Second requirement
- R3: Third requirement
**Affected modules:** Files/layers being changed.
**Risks:** What can go wrong.
**Rollback:** How to revert.
```

Only change from current spec format: acceptance criteria get `R1:`-`RN:` prefix. Sequential, per-task, reset with every new spec.

### @trace Markers — Convention

**Mandatory in test files:**
```
// @trace R1
// @trace R2 R3
# @trace R1
```

Pattern: `@trace` followed by one or more `R[0-9]+` IDs. Any comment syntax (`//`, `#`, `--`, `/*`, `%`, `;;`).

**Optional in code files:** Same format. Informational only — verification counts only test files.

**Rules:**
- One marker can cover multiple requirements: `@trace R1 R3`
- One requirement can have multiple markers across test files
- Marker in non-test file is ignored during verification (informational)
- Extra markers (R* in tests not present in spec) produce a warning but don't block

**Test file detection per stack:**

| Stack | Patterns |
|-------|----------|
| nodejs | `*.test.ts`, `*.spec.ts`, `*.test.js`, `*.spec.js`, `__tests__/` |
| python | `test_*.py`, `*_test.py`, `tests/` |
| php | `*Test.php`, `tests/` |
| dotnet | `*.Tests.cs`, `*Test.cs`, `*.Tests/` |
| go | `*_test.go` |
| java | `*Test.java`, `*Spec.java`, `src/test/` |

Stack read from `CLAUDE_PLUGIN_OPTION_STACK`. If undefined, all patterns used.

### verify-trace.sh — Verification Script

**Location:** `scripts/verify-trace.sh` (plugin-level)

**Steps:**
1. Parse spec-card.md — extract all `R[0-9]+:` lines from Acceptance criteria section
2. Scan test files — find `@trace R[0-9]+` markers using stack-aware patterns
3. Compare — each R* from spec must have at least one test match
4. Optionally scan code — informational count (does not block)
5. Report with color output via style.sh

**Output example:**
```
■ Spec Traceability
  ✓ R1: Login endpoint returns JWT     code(2) test(1)
  ✗ R2: JWT validates user role         test missing
  ✓ R3: Expired tokens rejected         test(2)

  Coverage: 2/3 (66%)
  ✗ FAILED: R2 has no test coverage
```

**Exit codes:**
- `0` — all R* covered by tests
- `1` — some R* missing test coverage

**Edge cases:**
- No spec-card.md → exit 0 (backward compatible, traceability not activated)
- spec-card.md exists but no R* criteria → exit 1 with message
- Extra @trace markers not in spec → warning, no block

**Stdout for session-log:** Single line `TRACE:2/3:R2` (covered/total:uncovered list).

### Pipeline Integration

**1. `pipeline-advance.sh spec` — validation**

Before creating `spec.done`, check:
- If spec-card.md exists, verify it has at least one R* criterion
- If spec-card.md doesn't exist, allow (backward compatible)
- If spec-card.md exists without R* criteria, block

**2. `pipeline-advance.sh verifier` — verification gate**

Before creating `verifier.done`, call `verify-trace.sh`:
- Exit 0 → create verifier.done, proceed to commit
- Exit 1 → verifier.done NOT created, orchestrator must fix

**3. `pipeline-advance.sh reset` — session-log enhancement**

Read last verify-trace.sh stdout output. Add to session-log entry:
```markdown
**Spec coverage:** 3/3 (R1, R2, R3)
```

### Workflow & Agent Template Changes

**`rules/workflow.md`:**
- Spec format: acceptance criteria require R* prefix
- New rule: orchestrator writes spec-card.md to `.claude/.pipeline/` before `pipeline-advance.sh spec`
- New builder rule: must add `@trace R*` in test files for every acceptance criterion

**`templates/agent-template.md` (builder):**
- Read `.claude/.pipeline/spec-card.md` for acceptance criteria
- Add `@trace R*` markers in test files for each requirement

**`templates/reviewer-template.md`:**
- Verify builder added `@trace R*` markers for all acceptance criteria
- Flag missing markers as Critical finding

### What Does NOT Change

- `guard-git.sh` — no traceability awareness
- `verify-all.sh` template — stays focused on build+test
- `pipeline-gate.sh` — still only checks .done files
- `hooks.json` — no new hooks
- Brainstorm, TDD, Debug, Finish skills — unchanged

## Backward Compatibility

Projects without spec-card.md work exactly as before. verify-trace.sh exits 0 when no spec-card.md exists. The feature activates only when orchestrator writes spec-card.md — which happens through updated workflow rules in new/updated projects.

## Files Changed

| File | Change |
|------|--------|
| `scripts/verify-trace.sh` | **NEW** — spec traceability verification |
| `scripts/pipeline-advance.sh` | Spec validation, verifier gate, session-log enhancement |
| `rules/workflow.md` | R* format, spec-card.md rule, builder @trace rule |
| `templates/agent-template.md` | Builder @trace instruction |
| `templates/reviewer-template.md` | Reviewer @trace verification instruction |
