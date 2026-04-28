---
name: apd-github
description: Use when the project has GitHub Projects configured (GITHUB_PROJECTS_URL in AGENTS.md) on Codex and APD pipeline tasks need to sync with the board. Creates issues for specs, moves cards through columns (todo → in-progress → review → done), closes on commit. Triggers on "GitHub Projects", "issue", "board", "card", "sync", "kanban", "project board", any APD pipeline phase transition when a board URL is configured.
---

# GitHub Projects — APD Pipeline Tracking (Codex)

Maps APD pipeline phases to GitHub Projects v2 columns. Each task becomes an
issue with the spec-card.md content embedded, and pipeline progress is reflected on the board.

## When to use / When to skip

**Use when:**
- The project has a GitHub Projects v2 board configured (`GITHUB_PROJECTS_URL` in AGENTS.md)
- A pipeline phase just transitioned — sync the column
- Spec was just approved — create the issue
- Pipeline just committed — close the issue with the commit reference

**Skip when:**
- No GitHub Projects board is configured for the project
- The repo is not on GitHub (Gitlab/Bitbucket/local)
- `gh` CLI is not authenticated — escalate, don't silently skip
- The user is in a hotfix flow that bypasses the pipeline (no issue to track)

## Automation — gh-sync

Instead of calling `gh` directly, use the `gh-sync` wrapper which tracks the
active issue across the pipeline:

```bash
bash ${APD_PLUGIN_ROOT}/bin/core/gh-sync spec "User login"
bash ${APD_PLUGIN_ROOT}/bin/core/gh-sync builder
bash ${APD_PLUGIN_ROOT}/bin/core/gh-sync reviewer
bash ${APD_PLUGIN_ROOT}/bin/core/gh-sync verifier
bash ${APD_PLUGIN_ROOT}/bin/core/gh-sync done 42 abc1234
bash ${APD_PLUGIN_ROOT}/bin/core/gh-sync skip 42 "Hotfix"
bash ${APD_PLUGIN_ROOT}/bin/core/gh-sync status
```

`gh-sync` automatically tracks the issue number for the current pipeline — you
don't need to pass it at every step. On Codex, the wrapper is invoked through
shell calls subject to `guard-bash-scope`.

## Prerequisite

- `gh` CLI authenticated (`gh auth login`)
- GitHub Projects v2 created with columns: **Spec**, **In Progress**, **Review**, **Testing**, **Done**
- `GITHUB_PROJECTS_URL` set in `AGENTS.md`

## Pipeline → column mapping

| APD step | GitHub Projects column | Action |
|---|---|---|
| `apd_advance_pipeline('spec', "Task")` | **Spec** | Create issue with spec-card.md content, add to board |
| `apd_advance_pipeline('builder')` | **In Progress** | Move issue to In Progress |
| `apd_advance_pipeline('reviewer')` | **Review** | Move issue to Review |
| `apd_advance_pipeline('verifier')` | **Testing** | Move issue to Testing |
| Commit (successful) | **Done** | Close issue, link commit, move to Done |
| `apd_advance_pipeline('skip', "<reason>")` | **Done** | Close issue with `apd-skip` label |

## Procedure

### 1. Spec phase — create the issue

When the orchestrator writes spec-card.md, also create a GitHub issue:

```bash
bash ${APD_PLUGIN_ROOT}/bin/core/gh-sync spec "Task name"
```

This creates the issue with the spec-card.md body and adds it to the configured
project board.

### 2. Move cards on phase transitions

After each `apd_advance_pipeline()` call, run the matching `gh-sync` step.
The wrapper knows the active issue number from `.apd/pipeline/gh-issue` and
moves the card to the next column.

### 3. Close on completion

After a successful commit:

```bash
bash ${APD_PLUGIN_ROOT}/bin/core/gh-sync done <issue> <commit>
```

### 4. Skip label

If the pipeline was skipped (hotfix):

```bash
bash ${APD_PLUGIN_ROOT}/bin/core/gh-sync skip <issue> "<reason>"
```

## Anti-patterns

- **Don't** call `gh issue create` directly when `gh-sync spec` is available **→ Do** use `gh-sync` so the issue number is tracked through the pipeline
- **Don't** open a new issue for each pipeline phase **→ Do** create one issue at spec, move it through columns, close at commit
- **Don't** silently swallow `gh` auth failures **→ Do** escalate with `gh auth login` instructions
- **Don't** close the issue with a generic "done" comment **→ Do** include the commit hash so the board links back to code
- **Don't** pull labels/columns from a hard-coded list **→ Do** read the project's column names dynamically (project owners customise them)

## Examples

**Example 1 — Full happy-path lifecycle.**

*Input:* User asks to implement "User login". No active issue; pipeline starts at spec phase.

*Output:* On each `apd_advance_pipeline()` call, run the matching `gh-sync` step:
```
apd_advance_pipeline('spec', "User login") → gh-sync spec "User login"
                                              opens #42, board column = Spec
apd_advance_pipeline('builder')             → gh-sync builder
                                              moves #42 to In Progress
apd_advance_pipeline('reviewer')            → gh-sync reviewer
                                              moves #42 to Review
apd_advance_pipeline('verifier')            → gh-sync verifier
                                              moves #42 to Testing
commit                                       → gh-sync done 42 abc1234
                                              closes #42 with "Commit: abc1234"
                                              board column = Done
```
The orchestrator never passes the issue number — `gh-sync` reads it from `.apd/pipeline/gh-issue`.

**Example 2 — Hotfix bypasses the pipeline.**

*Input:* Production incident — pipeline is skipped via `apd_advance_pipeline('skip', "Hotfix: payment 5xx")`. Issue #57 is open in the Spec column but the work goes straight to commit.

*Output:* Close with skip label, do not move through the in-progress columns:
```
gh-sync skip 57 "Hotfix: payment processor 5xx"
→ #57 closed with comment "Pipeline skipped (hotfix): Hotfix: payment processor 5xx"
→ label `apd-skip` added
→ board column = Done
```
Cycle-time metrics still capture the skip — the board reflects reality, not the pipeline.

**Example 3 — Drift detected → escalate, don't auto-correct.**

*Input:* Orchestrator runs `gh-sync status` after a builder phase. Output reports issue #42 in column "Done" while `apd_pipeline_state()` is in `builder` phase.

*Output:* Stop and escalate to the user:
```
GitHub Projects board out of sync:
  - Pipeline phase: builder
  - Issue #42 column: Done
Likely cause: someone closed the issue manually.
Action: confirm with user whether to reopen #42 or open a fresh issue —
do NOT silently move the card back.
```

## Exit criteria

You're done when:
- The active issue's column reflects the current pipeline phase
- On commit: issue is closed with the commit hash in the closing comment
- On skip: issue closed with `apd-skip` label and the skip reason
- The board's column-history reflects every pipeline transition (cycle-time data is preserved)
- No orphan issues — every `[APD]` issue maps to a real pipeline task or has been triaged

## Hand-off

- This skill is **complementary**, not a gate — pipeline progress is authoritative; board is the projection
- Called by orchestrator on every `apd_advance_pipeline()` step (workflow), not by humans directly
- If `gh-sync` reports an inconsistency (issue out of sync with pipeline state) → escalate to user; don't auto-correct

## Board setup recommendation

Create a GitHub Projects v2 board with the following columns:

| Column | Description |
|---|---|
| **Backlog** | Planned tasks (not in the pipeline) |
| **Spec** | Spec card created, awaiting approval |
| **In Progress** | Builder working |
| **Review** | Reviewer examining |
| **Testing** | Verifier testing |
| **Done** | Committed and pushed |

Labels:
- `apd-pipeline` — all APD tasks
- `apd-skip` — tasks with skipped pipeline
- `human-gate` — tasks requiring approval
