---
name: apd-audit
description: Use when you need to verify APD is correctly configured in the current project on Codex. Qualitative audit of agents under .apd/agents/, AGENTS.md, MCP server registration, hooks.json, and pipeline health — goes deeper than apd_doctor.
---

# APD Project Audit (Codex)

> Qualitative review of how APD is configured in the project — content quality,
> not just file existence. Pairs with `apd_doctor()` MCP tool (mechanical checks).

## When to use / When to skip

**Use when:**
- First session after `apd cdx init` — confirm everything is correct
- After manually editing `.apd/agents/`, `AGENTS.md`, or `.codex/config.toml`
- When the pipeline behaves unexpectedly
- When `apd_doctor()` passes but something "feels off"
- Before handing the project to another developer

**Skip when:**
- `apd_doctor()` itself is failing — fix those mechanical issues first
- You only need a yes/no health check — `apd_doctor()` is faster
- Mid-pipeline — audit is for between cycles, not during

## What This Checks (apd_doctor Does NOT)

| apd_doctor | apd-audit |
|---|---|
| Files exist? | Content correct and complete? |
| TOML valid? | Hook config actually wires to live scripts? |
| Agents have scope? | Scope paths match the project layout? |
| Pipeline runs? | Pipeline output matches the expected format? |
| Mechanical ✓/✗ | Qualitative review |

## Process

### 1. Run apd_doctor first

```
apd_doctor()
```

If it reports errors → fix those first. This skill builds on top of
`apd_doctor`, not replaces it.

### 2. Agent quality

For each agent in `.apd/agents/*.md`:

**Frontmatter check:**
- `scope:` list — paths actually exist in the repo?
- `model:` (if present) — builders should be `gpt-5.4` or stronger
- `effort:` (if present) — builders `xhigh`, reviewer `max`

**Body check:**
- Has a FORBIDDEN section with commit prohibition for builders
- Has a workflow description matching the role
- Scope paths match `apd_guard_write` arguments used elsewhere

### 3. AGENTS.md quality

Check that `AGENTS.md` has all required sections:
- `## Stack` — technology table
- `## APD` — orchestrator role description
- `### Pipeline` — enforced pipeline reference
- `### Guardrails` — guard list
- `### Mandatory skills` — brainstorm/tdd/debug/finish table
- `### Human gate` — approval requirements

Check that `AGENTS.md` does NOT contain:
- `{{PLACEHOLDER}}` unreplaced values
- References to old skill names
- `.claude/` paths (that's CC; Codex uses `.apd/`)

### 4. MCP registration

Verify `.codex/config.toml` has:
- `[mcp_servers.apd]` block with `command = "uv"`, relative `mcp/apd_mcp_server.py`, and `cwd` pointing at the APD plugin root
- All eight `[mcp_servers.apd.tools.<name>]` blocks (one per APD MCP tool)
- Approval modes are appropriate for the project's risk profile

Run `apd_ping()` to confirm the MCP server actually answers.

### 5. Hooks

Verify `.codex/hooks.json` has:
- `PreToolUse` Bash matcher → `bin/adapter/cdx/guard-bash-scope`
- `SessionStart` → `bin/adapter/cdx/session-start`
- No stale paths from previous APD versions

### 6. Pipeline health

```
apd_pipeline_state()
```

- Returns without error
- `next_step` reflects actual state on disk (`.apd/pipeline/`)
- No phantom locks

### 7. Memory files

Check `.apd/memory/`:
- `MEMORY.md` — not empty, has project context
- `status.md` — has current phase
- `session-log.md` — exists (may be empty for new projects)
- No `[fill in]` placeholders blocking the next task

## Output Format

```
APD Project Audit — {project name}

CRITICAL:
  1. [file:line] Description

IMPORTANT:
  1. [file:line] Description

CLEAN:
  ✓ Agents (X builder + 1 reviewer)
  ✓ AGENTS.md sections complete
  ✓ MCP registered + apd_ping responds
  ✓ Hooks wired
  ✓ Pipeline healthy
  ✓ Memory files present

Result: X issues (Y critical, Z important)
```

## Common rationalizations

| Excuse | Reality |
|--------|---------|
| "apd_doctor passes so it's fine" | apd_doctor checks structure, not content quality |
| "Agents work, no need to audit" | Wrong scope or missing FORBIDDEN section wastes review cycles |
| "AGENTS.md looks ok" | Missing sections mean orchestrator skips important rules |
| "I'll fix it when it breaks" | Broken pipeline produces broken code silently |

## Exit criteria

You're done when:
- Every agent under `.apd/agents/` has been opened and frontmatter checked
- Every required section in `AGENTS.md` is present and free of unreplaced `{{PLACEHOLDER}}` values
- `.codex/config.toml` has the `[mcp_servers.apd]` block plus 8 per-tool approval blocks
- `apd_ping()` returns a valid response
- `apd_pipeline_state()` runs without error
- Findings are sorted into CRITICAL / IMPORTANT / CLEAN buckets in the output format
- If any CRITICAL is reported, the user has been told what to fix and in what order

## Hand-off

- After audit completes with CRITICAL findings → invoke `apd cdx init` (CLI, outside Codex) to regenerate missing pieces
- After audit completes clean → continue with normal development
- If audit reveals a structural issue not covered by `apd cdx init` → escalate to user with concrete file:line references
