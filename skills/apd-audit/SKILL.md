---
name: apd-audit
description: Use when you need to verify APD is correctly configured in the current project. Qualitative audit of agents, hooks, CLAUDE.md, pipeline, and guardrails — goes deeper than verify-apd.sh.
effort: max
allowed-tools: Read Glob Grep Bash
---

# APD Project Audit

## The Iron Law

```
NO TASK WITHOUT A HEALTHY PIPELINE FIRST
```

If the audit finds issues, fix them before starting work. A broken pipeline produces broken results.

## When to Use

- First session after `/apd-setup` — confirm everything is correct
- After manually editing agents, CLAUDE.md, or settings.json
- When pipeline behaves unexpectedly
- When verify-apd.sh passes but something "feels off"
- Before handing the project to another developer

## What This Checks (verify-apd.sh Does NOT)

| verify-apd.sh | /apd-audit |
|---|---|
| Files exist? | Content correct and complete? |
| JSON valid? | Hook `if` patterns correct? |
| Agents have model? | Agents have correct model/effort/color/maxTurns? |
| Pipeline runs? | Pipeline output matches expected format? |
| Mechanical ✓/✗ | Qualitative review |

## Process

### 1. Run verify-apd.sh first

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify-apd.sh
```

If FAIL → fix those first. This skill builds on top of verify-apd.sh, not replaces it.

### 2. Agent Quality

For each agent in `.claude/agents/*.md`:

**Frontmatter check:**
- `model:` — builders must be `sonnet`, reviewer must be `opus`
- `effort:` — builders must be `high`, reviewer must be `max`
- `color:` — should be set (purple/blue/green/cyan for builders, orange for reviewer)
- `maxTurns:` — should be set (20 for builders, 15 for reviewer)
- `permissionMode:` — builders `bypassPermissions`, reviewer `plan`
- `memory: project` — should be set

**Hook check:**
- `if:` field must be inside hook objects, NOT at matcher level
- No env var prefixes in `if` patterns (e.g., `Bash(git *)` not `Bash(APD_ORCHESTRATOR_COMMIT=1 git *)`)
- Guard scripts use `${CLAUDE_PLUGIN_ROOT}/scripts/` paths
- Builders have: guard-scope, guard-bash-scope, guard-secrets, guard-git
- Reviewer has: guard-secrets, guard-git (NO guard-scope — read-only)

**Body check:**
- Has FORBIDDEN section with commit prohibition
- Has workflow section
- Scope paths match guard-scope arguments

### 3. CLAUDE.md Quality

Check that CLAUDE.md has all required sections:
- `## Stack` — technology table
- `## APD` — orchestrator role description
- `### Pipeline` — enforced pipeline reference
- `### Guardrails` — guard script list
- `### Mandatory skills` — brainstorm/tdd/debug/finish table
- `### Human gate` — approval requirements
- `### Session memory` — session-log reference
- `## Anti-patterns` — common mistakes
- `## Memory` — `@.claude/memory/` references

Check that CLAUDE.md does NOT contain:
- `{{PLACEHOLDER}}` unreplaced values
- References to old skill names (`/apd-init`, `/github-projects`, `/miro-dashboard`)
- `superpowers:subagent-driven-development` references (should use APD pipeline)

### 4. Settings Quality

Read `.claude/settings.json` and verify:
- `enabledPlugins.superpowers@claude-plugins-official: false`
- `attribution.commit: ""` (empty — no AI signatures)
- `attribution.pr: ""` (empty)
- `permissions.allow` includes `.claude/memory/**` (Write and Edit)
- Notification hook configured

### 5. Workflow Rules

Read `.claude/rules/workflow.md` and verify:
- Uses `${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh` (not `apd-pipeline`)
- Has step 9 (finish)
- Has mandatory skills section (brainstorm, tdd, debug, finish)
- Model discipline table present (orchestrator opus, builder sonnet, reviewer opus)

### 6. Pipeline Health

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh status
bash ${CLAUDE_PLUGIN_ROOT}/scripts/apd-init.sh --version
```

- Pipeline responds without errors
- Version matches expected

### 7. Memory Files

Check `.claude/memory/`:
- `MEMORY.md` — not empty, has project context
- `status.md` — has current phase
- `session-log.md` — exists (may be empty for new projects)
- No `[fill in]` placeholders in the last session-log entry (blocks new tasks)

## Output Format

```
APD Project Audit — {project name}

CRITICAL:
  1. [file:line] Description

IMPORTANT:
  1. [file:line] Description

CLEAN:
  ✓ Agents (X builder + 1 reviewer)
  ✓ CLAUDE.md sections complete
  ✓ Settings configured
  ✓ Workflow rules current
  ✓ Pipeline healthy
  ✓ Memory files present

Result: X issues (Y critical, Z important)
```

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "verify-apd.sh passes so it's fine" | verify-apd.sh checks structure, not content quality |
| "Agents work, no need to audit" | Wrong model or missing maxTurns wastes time and money |
| "CLAUDE.md looks ok" | Missing sections mean orchestrator skips important rules |
| "I'll fix it when it breaks" | Broken pipeline produces broken code silently |

## Integration

- **Called by:** Developer at start of session or after configuration changes
- **Pairs with:** `verify-apd.sh` (mechanical checks) + `/apd-setup` (fixes issues)
- **Leads to:** Fix issues → re-audit → start working
