# Adversarial Reviewer — Design Document

## Overview

Optional context-free code reviewer that runs after the regular reviewer. Sees only code changes (git diff + touched files), not the spec or task context. Finds bugs that contextual reviewers miss by not knowing intent. Findings are advisory — orchestrator decides what to act on.

## Problem

The regular reviewer has full context: spec, task description, builder report. This context creates empathy — the reviewer "understands what the builder was trying to do" and unconsciously forgives mistakes. A fresh pair of eyes without context catches issues that contextual review misses.

## Solution

### Agent Template

**File:** `templates/adversarial-reviewer-template.md`

**Frontmatter:**
```yaml
name: adversarial-reviewer
description: Context-free code reviewer — finds issues that contextual reviewers miss
tools: Read, Glob, Grep, Bash
model: sonnet
effort: max
color: red
maxTurns: 15
permissionMode: plan
memory: none
```

Key differences from regular reviewer:
- `memory: none` — no access to session memory, doesn't know the task
- `model: sonnet` instead of opus — different perspective, different blind spots
- `effort: max` — deep analysis despite smaller model
- `color: red` — visually distinct from regular reviewer (orange)
- No scope guards (reads everything, writes nothing)

### What the Agent Receives

Orchestrator prepares context before dispatch:

1. Run `git diff` to get changed lines
2. Extract list of touched files
3. Dispatch with prompt containing only the file list and review instructions

The agent then reads each file in full using its tools. It does NOT receive:
- spec-card.md
- Session context or task description
- Builder report or regular reviewer findings

### What the Agent Checks

1. **Bugs** — logic errors, off-by-one, null handling, race conditions
2. **Security** — injection, XSS, auth bypass, data leaks
3. **Edge cases** — empty input, boundary values, error paths
4. **Design** — unclear names, tight coupling, missing abstractions
5. **Missed tests** — untested code paths, weak assertions

The agent does NOT:
- Ask what the task was or why changes were made
- Suggest style changes (formatting, naming conventions)
- Flag things that are clearly intentional design choices
- Recommend refactoring outside the changed files

### Output Format

```
## Adversarial Review

### Findings
1. [file:line] SEVERITY — Description

### Summary
X findings (N high, M medium, K low)
```

If no issues found: `### Summary: No issues found — code looks solid.`

### Pipeline Integration

**Position:** After regular reviewer, before verifier (step 6b in workflow).

**No pipeline state machine changes.** No `adversarial.done` file. The adversarial reviewer is an orchestrator-level decision between the `reviewer` and `verifier` steps. Pipeline-advance.sh does not know about it.

**Orchestrator logic:**
1. After `pipeline-advance.sh reviewer`, dispatch adversarial-reviewer
2. Read findings
3. For each finding: **accept** (legitimate, needs fix) or **dismiss** (false positive, conscious trade-off)
4. Write summary to `.pipeline/.adversarial-summary`: `ADVERSARIAL:total:accepted:dismissed` (e.g., `ADVERSARIAL:5:2:3`)
5. If accepted findings exist → dispatch builder to fix → re-run regular reviewer → adversarial again
6. Proceed to `pipeline-advance.sh verifier`

**Tracking:** track-agent.sh automatically logs the agent in `.agents` (existing SubagentStart/Stop hooks). Session-log shows it in the "Agents" list.

### Hit Rate Metrics

Tracking accept/dismiss ratio per task gives hard data on whether this feature adds value or generates noise.

**Per-task (ephemeral):**
- `.pipeline/.adversarial-summary` — written by orchestrator, format: `ADVERSARIAL:total:accepted:dismissed`
- `pipeline-advance.sh reset` reads this and adds to session-log:
  ```
  **Adversarial review:** 5 findings (2 accepted, 3 dismissed)
  ```
- Cleaned up on reset (same pattern as `.trace-summary`)

**Cumulative:**
- `pipeline-metrics.log` extended with adversarial columns: `|adv_total|adv_accepted|adv_dismissed`
- `pipeline-advance.sh metrics` displays aggregate hit rate:
  ```
  Adversarial hit rate:  42% (18/43 accepted across 8 tasks)
  ```

If cumulative hit rate drops below ~20%, the feature generates more noise than value and should be recalibrated or disabled.

### Workflow Changes

**New step 6b in workflow.md:**
```
6b. DISPATCH ADVERSARIAL REVIEWER (optional, recommended)
    → Dispatch adversarial-reviewer agent (sonnet/max, read-only, no spec context)
    → Agent sees only git diff + touched files, finds issues blind
    → Orchestrator evaluates findings against spec context
    → If legitimate issues found → fix via builder → re-review
    → This step is informational — does NOT block pipeline mechanically
```

**New role in "Four roles" section (becomes "Five roles"):**
```
### Adversarial Reviewer (dispatched agent)
- Model: sonnet | Effort: max
- Context-free — sees only code changes, not the spec or task
- Finds bugs that contextual reviewers miss by not knowing intent
- Findings are advisory — orchestrator decides what to act on
- Runs AFTER regular reviewer, BEFORE verifier
```

**Model table extended:**

| Role | Model | Effort | Why |
|------|-------|--------|-----|
| Adversarial Reviewer | sonnet | max | Fresh eyes, different model = different blind spots |

## What Does NOT Change

- No guard scripts modified (guard-*.sh)
- hooks.json unchanged
- Builder template unchanged
- Regular reviewer template unchanged
- Pipeline state machine unchanged (no new .done files)
- pipeline-gate.sh unchanged (still 4 gates)
- verify-trace.sh unchanged

## Backward Compatibility

Projects that don't define an adversarial-reviewer agent work exactly as before. The step is documented as "optional, recommended" in workflow.md. Orchestrator only dispatches it if the agent definition exists in `.claude/agents/`. Hit rate metrics are only recorded when `.adversarial-summary` exists.

## Files Changed

| File | Change |
|------|--------|
| `templates/adversarial-reviewer-template.md` | **NEW** — agent template |
| `rules/workflow.md` | New step 6b, new role, extended model table |
| `scripts/pipeline-advance.sh` | Reset reads `.adversarial-summary` for session-log + metrics, cleanup on reset/spec/rollback |
