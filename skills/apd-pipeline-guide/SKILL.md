---
name: apd-pipeline-guide
description: MANDATORY before EVERY pipeline task — load this skill BEFORE writing spec-card.md, on every new task, no exceptions. It is the APD operating manual, NOT a brainstorm — "the task is already clear" is not a reason to skip it. Carries the current gate contract - pipeline phase map, implementation-plan **Implements:** format, adversarial rationale file format, common BLOCKs + recovery, state read rules. The spec gate hard-BLOCKS without the .guide-marker this skill writes on exit. There is no skip flag.
effort: low
allowed-tools: Read
---

# APD Pipeline Guide

The operating manual for one pipeline cycle. Read it, acknowledge the contract,
write the marker, proceed. ~2 minutes; cheaper than any single BLOCK it prevents.

This skill is NOT a clarification dialogue. If the task scope is vague, load
`/apd-brainstorm` FIRST (interactive, optional), converge on a design, then come
back here. This guide is unconditional either way.

## Pipeline phase map

```
spec → builder → reviewer → adversarial → verifier → commit
```

| Advance | Gate checks at that point |
|---|---|
| `apd pipeline spec "<task>"` | spec-card.md exists, ≤7 R-criteria, **`.guide-marker` present (this skill)** |
| `apd pipeline builder` | implementation-plan.md exists, plan-spec consistency (strict), no stale pre-spec dispatch |
| `apd pipeline reviewer` | builder ran post-spec, builder cycle cap (default 2) |
| adversarial dispatch | only AFTER reviewer.done (out-of-order start is not recorded — re-dispatch) |
| `apd pipeline verifier` | `.adversarial-summary` + `.adversarial-rationale.md` present, rationale gate, spec-hash immutability |
| commit | guard-git: pipeline complete, commit message prefix, no mass staging |

Mode: `pipeline_mode: polish` in spec-card.md lowers cycle caps to 1 and skips
adversarial for 1-2 R hotfixes. Lean vs Full is declared in the spec; this guide
applies to BOTH.

## Implementation plan contract

Write `.apd/pipeline/implementation-plan.md` BEFORE `apd pipeline builder`.
**EVERY `### Section` MUST have an `**Implements:**` header — NO RESERVED NAMES.**

```
## Implementation Plan: <task-name>

### Files to modify
**Implements:** none              ← scaffolding sections use 'none'

- src/...

### Backend
**Implements:** R1, R3            ← every dispatch section maps to R-ids

- src/api/... — endpoint changes

### Agents
**Implements:** none              ← Agents needs the header too

- backend-builder
- code-reviewer

### Notes
**Implements:** none              ← Notes needs the header too

- relevant context
```

Bidirectional check (`verify-plan-spec`, strict by default since v6.8.1):
- forward — every R-id in an `**Implements:**` line must exist in spec-card.md
- reverse — every spec R-id must appear in at least one section
- symmetric — every `### Section` must declare R-ids or `none`

Known failure shape: headers written for Files-to-modify/create but forgotten on
Agents/Notes (asymmetric learning). Write ALL headers FROM THE START.

## Adversarial rationale contract

AFTER the adversarial-reviewer dispatch, BEFORE `apd pipeline verifier`, write
`.apd/pipeline/.adversarial-rationale.md` (note the `.md` extension) with one
block per finding:

```
## Finding 1 — <one-line title>
**Severity:** critical | important | minor
**Status:** accepted | dismissed | reviewer-self-dismissed
**Rationale:** <text ≥40 chars required for dismissed/reviewer-self-dismissed>
```

- Missing file → BLOCK at verifier.
- 100% orchestrator-dismiss (T≥3, A=0, Do≥1) → hard BLOCK. Accept at least one
  finding OR reclassify with the adversarial reviewer's own note as
  reviewer-self-dismissed.
- Do NOT write `adversarial: max_defects=...` in the spec — DEPRECATED (v6.9),
  removed in v7.0; the rationale gate is the replacement.

## Reading pipeline state

Use the sanctioned read path — `cat`/`ls` on `.apd/pipeline/` is guard-blocked:

```bash
bash .claude/bin/apd pipeline show          # digest: criteria, plan, reviewed count, T:A:D, cycles
bash .claude/bin/apd pipeline show spec     # full spec-card.md
bash .claude/bin/apd pipeline show plan     # full implementation-plan.md
```

Writes to allowlisted pipeline files (spec-card.md, implementation-plan.md,
.adversarial-summary, .adversarial-rationale.md, .guide-marker) go through the
Write/Edit tool — bash redirects to `.apd/pipeline/` are blocked by design.

## Common BLOCKs + recovery

| BLOCK reason | Quick fix |
|---|---|
| `guide-marker-missing` | Load this skill, write the marker (below), re-run spec advance |
| `plan-spec-consistency issues=N` | Add `**Implements:**` headers / missing R-ids per the inline template; re-run builder (~10s) |
| `rationale-missing` | Write `.adversarial-rationale.md` with T entries; re-run verifier |
| `rationale-100pct-orch-dismiss` | Accept ≥1 finding OR reclassify dismissed → reviewer-self-dismissed |
| `max_builder_cycles-exceeded` | Decompose into 2+ tasks OR raise cap via spec-card `builder: max_cycles=N` |
| `adversarial-before-reviewer` | Dispatch code-reviewer first; advance reviewer; THEN adversarial |
| `max_defects-*` (DEPRECATED v6.9) | Remove the `max_defects` field from spec-card; do not re-introduce |
| `pipeline-state-write` on a read | You used bash `cat`/`ls` on pipeline state — use `apd pipeline show` |

## Exit — write the marker

The spec gate reads `.apd/pipeline/.guide-marker`. Write it as the LAST step of
this skill, with the exact task name you will pass to the spec advance:

```bash
printf '%s|%s\n' "<task-name>" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .apd/pipeline/.guide-marker

bash .claude/bin/apd pipeline spec "<task-name>"
```

Name mismatch or missing marker → hard BLOCK. There is no `--skip` flag — this
gate has no opt-out by design (reading the contract is cheaper than negotiating
about it). The marker is wiped on reset and on task completion.

## Exit criteria

You're done when:
- You can state which gate fires at each of the 5 advances
- You know the two file contracts (plan `**Implements:**`, rationale `.md`)
- `.guide-marker` is written with the exact task name
