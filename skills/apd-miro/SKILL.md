---
name: apd-miro
description: Use when the project has a Miro board configured and you need to update the pipeline dashboard. Visualizes current status, completed tasks, and metrics.
effort: high
---

# Miro Pipeline Dashboard

Creates or updates a pipeline dashboard on the Miro board with:
- Current pipeline status (which step is active)
- Recently completed tasks with durations
- Pipeline metrics (averages, skip rate)

## Prerequisite

- Miro MCP configured: `claude mcp add --transport http miro https://mcp.miro.com`
- Authentication: `/mcp auth`
- Board URL defined in CLAUDE.md (`{{MIRO_BOARD_URL}}`)

## When to use

- At the start of a session — display pipeline state on the board
- After completing a task — update the board with the new result
- On user request — "update Miro dashboard"
- Periodically — for reviewing team performance

## Procedure

### 1. Gather data

Run the following commands and save the output:

```bash
# Pipeline status
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh status

# Metrics (if available)
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh metrics

# Skip statistics
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh stats
```

### 2. Create dashboard table on the board

Use Miro MCP `create_table` to create a table with the following content:

**Table 1: Pipeline Status**

| Step | Status | Time |
|------|--------|------|
| Spec | ✅ / ⏳ / — | timestamp |
| Builder | ✅ / ⏳ / — | timestamp |
| Reviewer | ✅ / ⏳ / — | timestamp |
| Verifier | ✅ / ⏳ / — | timestamp |

- ✅ = completed (green sticky note)
- ⏳ = in progress (yellow sticky note)
- — = not started (gray sticky note)

### 3. Create metrics section

Use Miro MCP `create_document` for a markdown document:

```markdown
# APD Pipeline Metrics

**Total tasks:** {count}
**Average duration:** {time}
**Fastest task:** {time}
**Slowest task:** {time}
**Skip rate:** {percentage}

## Average per step
- spec→builder: {time}
- builder→reviewer: {time}
- reviewer→verifier: {time}
```

### 4. Create recent tasks

Use Miro MCP `create_table` for a table of the last 5 tasks:

| Task | Duration | Status |
|------|----------|--------|
| {name} | {time} | ✅ / ⚠️ skip / … partial |

### 5. Organize on the board

Position elements in a frame named **"APD Pipeline Dashboard"**:
- Pipeline Status table — top left
- Metrics document — top right
- Recent tasks — bottom

### 6. Updating an existing dashboard

If the frame "APD Pipeline Dashboard" already exists on the board:
1. Delete existing elements in the frame
2. Create new ones with updated data
3. Do NOT create a new frame — use the existing one

## Usage example

```
User: Update Miro dashboard
Claude: Reading pipeline status and metrics...

  Pipeline: CreateOrder task
    [DONE] spec
    [DONE] builder
    [----] reviewer ← next
    [----] verifier

  Metrics: 12 tasks, average 8m 30s, skip rate 4%

  Updating Miro board...
  ✓ Pipeline Status table updated
  ✓ Metrics document updated
  ✓ Recent tasks table updated

Dashboard updated: https://miro.com/app/board/...
```

## Automatic updating

The orchestrator can call this skill automatically in two ways:

1. **At the end of the pipeline** — after `pipeline-advance.sh verifier`, before commit
2. **On session start** — if a Miro board exists in the configuration

For automatic updating at each step, add to the orchestrator workflow:
```
After each pipeline-advance.sh step → call /apd-miro
```
