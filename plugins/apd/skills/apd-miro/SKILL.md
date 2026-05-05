---
name: apd-miro
description: Use when the project has a Miro board configured (MIRO_BOARD_URL in AGENTS.md) on Codex and the APD pipeline dashboard needs updating. Visualizes current pipeline status, completed tasks, recent metrics, and active spec cards. Triggers on "Miro", "dashboard", "board update", "visualize pipeline", "pipeline view", "metrics", any pipeline phase change when a Miro URL is configured.
---

# Miro Pipeline Dashboard (Codex)

Creates or updates a pipeline dashboard on the Miro board with:

- Current pipeline status (which step is active)
- Recently completed tasks with durations
- Pipeline metrics (averages, skip rate)

## When to use / When to skip

**Use when:**
- The project has `MIRO_BOARD_URL` configured in `AGENTS.md`
- A pipeline cycle just completed — update the board with the new result
- The user asked: "update Miro dashboard"
- Start of a session — display current pipeline state on the board

**Skip when:**
- No Miro board is configured for the project (no `MIRO_BOARD_URL`)
- The Miro MCP server is not connected or authenticated
- The pipeline hasn't moved since the last update — the board would show the same state

## Prerequisite

- Miro MCP server registered in `.codex/config.toml` (HTTP transport: `https://mcp.miro.com`)
- MCP authentication completed (Codex prompts on first call)
- `MIRO_BOARD_URL` defined in `AGENTS.md`

## Procedure

### 1. Gather data

Pull pipeline state and historical metrics through MCP tools:

```
apd:apd_pipeline_state()                    # current step + step timings
apd:apd_pipeline_metrics()                  # historical runs (timestamp, phase ts, status, adversarial T/A/D, agent counts)
```

Compute averages and skip rate from the `runs` list returned by `apd:apd_pipeline_metrics()`. Pass `limit=N` to cap the most recent N runs (0 = all, max 200).

### 2. Create dashboard table on the board

Use Miro MCP `create_table` to create the dashboard:

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
|---|---|---|
| {name} | {time} | ✅ / ⚠️ skip / partial |

### 5. Organize on the board

Position elements in a frame named **"APD Pipeline Dashboard"**:

- Pipeline Status table — top left
- Metrics document — top right
- Recent tasks — bottom

### 6. Updating an existing dashboard

If the frame "APD Pipeline Dashboard" already exists on the board:

1. Delete existing elements in the frame
2. Create new ones with updated data
3. Do NOT create a new frame — reuse the existing one

## Anti-patterns

- **Don't** create a new "APD Pipeline Dashboard" frame on every update **→ Do** reuse the existing frame and replace its contents
- **Don't** push status to the board mid-step (transitions are fast) **→ Do** push only after a step completes (state is stable)
- **Don't** assume the user wants a board update on every commit **→ Do** check for `MIRO_BOARD_URL` in AGENTS.md before invoking
- **Don't** copy raw `apd:apd_pipeline_state()` output onto the board **→ Do** transform it into the table/sticky shapes the dashboard uses

## Examples

**Example 1 — First dashboard on a fresh board.**

*Input:* `MIRO_BOARD_URL` configured but the board has no "APD Pipeline Dashboard" frame yet. `apd:apd_pipeline_state()` reports spec=DONE, builder=ACTIVE, no metrics history.

*Output:* Create the frame and seed it with the current state:
```
Pipeline Status table:
  | Spec     | ✅ | 14:02 |
  | Builder  | ⏳ | 14:08 |
  | Reviewer | —  |       |
  | Verifier | —  |       |

Metrics document: "No completed cycles yet"
Recent tasks: empty
```
Return the board URL.

**Example 2 — Mid-cycle update preserves the frame.**

*Input:* Frame already exists from a previous run; pipeline just transitioned `builder → reviewer`. Old table shows builder=⏳, reviewer=—.

*Output:* Reuse the frame — delete old shapes, write new ones in place:
```
Before:
  | Spec     | ✅ | 14:02 |
  | Builder  | ⏳ | 14:08 |
  | Reviewer | —  |       |

After:
  | Spec     | ✅ | 14:02 |
  | Builder  | ✅ | 14:23 |
  | Reviewer | ⏳ | 14:23 |
```
Do NOT create a second frame — `find_frame_by_name("APD Pipeline Dashboard")` first.

**Example 3 — Cycle complete updates Recent tasks.**

*Input:* Pipeline cycle finished (commit `abc1234`, total 11m 32s). Old "Recent tasks" table had 4 rows; latest task should slot in at the top.

*Output:* All status cells flip to ✅, Metrics document refreshes averages, Recent tasks gets a new top row:
```
Recent tasks (after):
  | Add /orders/refund     | 11m 32s | ✅      |   ← new
  | Migrate webhook auth   |  9m 14s | ✅      |
  | Fix payment 5xx        |  3m 02s | ⚠️ skip |
  | Email template refactor|  7m 48s | ✅      |
  | OAuth callback fix     |  5m 21s | ✅      |
```
Cap at 5 rows; trim oldest if needed.

## Exit criteria

You're done when:
- The "APD Pipeline Dashboard" frame exists on the board (created or reused)
- Pipeline Status table reflects the current step state (✅/⏳/—)
- Metrics document has the latest numbers from `apd:apd_pipeline_metrics()`
- Recent tasks table shows the last 5 tasks with durations
- The board URL has been returned to the user

## Hand-off

- This skill is **idempotent** — repeated invocations update the same frame
- After a pipeline cycle completes → may be invoked from `apd-finish` if the user opts to push the dashboard before push/PR
- If MCP authentication fails → escalate to user; do NOT silently skip
