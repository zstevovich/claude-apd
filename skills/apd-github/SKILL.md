---
name: apd-github
description: Use when the project has GitHub Projects configured and you need to sync pipeline tasks with the board. Creates issues for specs, moves cards through columns, closes on completion.
effort: high
---

# GitHub Projects — APD Pipeline Tracking

Maps APD pipeline phases to GitHub Projects v2 columns. Each task becomes an issue with a spec card, and pipeline progress is reflected on the board.

## Automation — gh-sync

Instead of manually calling `gh issue create` and `gh issue close`, use the `gh-sync` wrapper:

```bash
# Instead of manually:
bash ${CLAUDE_PLUGIN_ROOT}/bin/core/gh-sync spec "User login"      # creates issue + starts pipeline spec
bash ${CLAUDE_PLUGIN_ROOT}/bin/core/gh-sync builder                 # comments on issue + starts pipeline builder
bash ${CLAUDE_PLUGIN_ROOT}/bin/core/gh-sync reviewer                # comments + starts reviewer
bash ${CLAUDE_PLUGIN_ROOT}/bin/core/gh-sync verifier                # comments + starts verifier
bash ${CLAUDE_PLUGIN_ROOT}/bin/core/gh-sync done 42 abc1234         # closes issue with commit reference
bash ${CLAUDE_PLUGIN_ROOT}/bin/core/gh-sync skip 42 "Hotfix"        # closes with apd-skip label
bash ${CLAUDE_PLUGIN_ROOT}/bin/core/gh-sync status                  # shows active issue
```

`gh-sync` automatically tracks the issue number for the current pipeline — you don't need to pass it at every step.

## Prerequisite

- GitHub MCP server configured in `.mcp.json`
- GitHub Projects v2 created with columns: **Spec**, **In Progress**, **Review**, **Testing**, **Done**
- `gh` CLI authenticated (`gh auth login`)

## Pipeline → column mapping

| APD step | GitHub Projects column | Action |
|----------|----------------------|--------|
| `pipeline-advance spec "Task"` | **Spec** | Create issue with spec card, add to board |
| `pipeline-advance builder` | **In Progress** | Move issue to In Progress |
| `pipeline-advance reviewer` | **Review** | Move issue to Review |
| `pipeline-advance verifier` | **Testing** | Move issue to Testing |
| Commit (successful) | **Done** | Close issue, link commit, move to Done |
| `pipeline-advance skip` | **Done** | Close issue with `skip` label |

## Procedure

### 1. Creating an issue for a new task (Spec phase)

When the orchestrator creates a spec card, also create a GitHub issue:

```bash
gh issue create \
  --title "[APD] Task name" \
  --body "$(cat <<'EOF'
## Spec card

**Goal:** One sentence.
**Effort:** max | high
**Out of scope:** What we are NOT doing.
**Acceptance criteria:**
- [ ] Criterion 1
- [ ] Criterion 2
**Affected modules:** files/layers
**Risks:** what can go wrong
**Rollback:** how to revert

---
_APD Pipeline Task — do not close manually_
EOF
)" \
  --label "apd-pipeline" \
  --project "{PROJECT_NAME}"
```

### 2. Moving cards through columns

Use the GitHub MCP server to move items on the board:

```
Orchestrator: Move issue #42 to the "In Progress" column on the GitHub Projects board.
```

The GitHub MCP server supports `update_project_item` for changing status.

### 3. Closing the issue on completion

After a successful commit:

```bash
gh issue close ISSUE_NUMBER --comment "Completed through APD pipeline. Commit: COMMIT_HASH"
```

### 4. Skip label

If the pipeline was skipped (hotfix):

```bash
gh issue close ISSUE_NUMBER --comment "Pipeline skipped (hotfix): REASON" 
gh issue edit ISSUE_NUMBER --add-label "apd-skip"
```

## Automation

The orchestrator can automate the entire flow:

1. **On spec** → create issue + add to board in the Spec column
2. **On each `pipeline-advance` step** → move issue to the corresponding column
3. **On commit** → close issue with commit reference
4. **On skip** → close with skip label

### Example flow

```
User: Implement user login
Orchestrator:
  1. Creates spec card
  2. → gh issue create --title "[APD] User login" --project "MyProject"
  3. → pipeline-advance spec "User login"
  4. Dispatches backend-builder
  5. → moves issue #42 to "In Progress"
  6. → pipeline-advance builder
  7. Starts reviewer
  8. → moves issue #42 to "Review"
  9. → pipeline-advance reviewer
  10. Starts verifier
  11. → moves issue #42 to "Testing"
  12. → pipeline-advance verifier
  13. Commits
  14. → gh issue close 42 --comment "Commit: abc1234"
  15. → issue moves to "Done"
```

## Metrics from GitHub Projects

GitHub Projects stores card movement history. This enables:
- **Cycle time** — how long an issue takes from Spec to Done
- **Bottleneck detection** — which column holds cards the longest
- **Throughput** — how many issues are closed per day/week

This data is complementary to `pipeline-advance metrics` — GitHub provides a board-level view, pipeline provides per-step timing.

## Board setup recommendation

Create a GitHub Projects v2 board with the following columns:

| Column | Description |
|--------|-------------|
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
