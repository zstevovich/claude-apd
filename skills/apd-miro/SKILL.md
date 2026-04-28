---
name: apd-miro
description: Use when the project has a Miro board configured (MIRO_BOARD_URL in CLAUDE.md) and the APD pipeline dashboard needs updating. Visualizes current pipeline status, completed tasks, recent metrics, and active spec cards. Triggers on "Miro", "dashboard", "board update", "visualize pipeline", "pipeline view", "metrics", any pipeline phase change when a Miro URL is configured.
effort: high
allowed-tools: Read Bash
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

## When to use / When to skip

**Use when:**
- The project has `MIRO_BOARD_URL` configured in `CLAUDE.md`
- A pipeline cycle just completed — update the board with the new result
- The user asked: "update Miro dashboard"
- Start of a session — display current pipeline state on the board

**Skip when:**
- No Miro board is configured for the project (no `MIRO_BOARD_URL`)
- The Miro MCP server is not connected or authenticated
- The pipeline hasn't moved since the last update — the board would show the same state

## Procedure

### 1. Gather data

Run the following commands and save the output:

```bash
# Pipeline status
bash .claude/bin/apd pipeline status

# Metrics (if available)
bash .claude/bin/apd pipeline metrics

# Skip statistics
bash .claude/bin/apd pipeline stats
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

## Anti-patterns

- **Don't** create a new "APD Pipeline Dashboard" frame on every update **→ Do** reuse the existing frame and replace its contents
- **Don't** push status to the board mid-step (transitions are fast) **→ Do** push only after a step completes (state is stable)
- **Don't** assume the user wants a board update on every commit **→ Do** check for `MIRO_BOARD_URL` in CLAUDE.md before invoking
- **Don't** copy raw `apd pipeline status` output onto the board **→ Do** transform it into the table/sticky shapes the dashboard uses

## Exit criteria

You're done when:
- The "APD Pipeline Dashboard" frame exists on the board (created or reused)
- Pipeline Status table reflects the current step state (✅/⏳/—)
- Metrics document has the latest numbers from `apd pipeline metrics`
- Recent tasks table shows the last 5 tasks with durations
- The board URL has been returned to the user

## Hand-off

- This skill is **idempotent** — repeated invocations update the same frame
- After a pipeline cycle completes → may be invoked from `apd-finish` if the user opts to push the dashboard before push/PR
- If MCP authentication fails → escalate to user with `claude mcp auth miro` instructions; do NOT silently skip
