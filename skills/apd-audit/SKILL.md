---
name: apd-audit
description: Use when verifying that APD is correctly configured in the current project — qualitative deep audit of agents, hooks, CLAUDE.md, pipeline state, MCP wiring, and guardrails. Goes further than verify-apd. Triggers on "audit APD", "review setup", "is APD configured", "verify framework", "check APD", "APD health", "is everything wired", after any major framework upgrade or version bump.
effort: max
allowed-tools: Read Glob Grep Bash
---

# APD Project Audit

> Qualitative review of how APD is configured in the project — content quality,
> not just file existence. Pairs with `verify-apd` (mechanical checks).

## When to use / When to skip

**Use when:**
- First session after `/apd-setup` — confirm everything is correct
- After manually editing agents, CLAUDE.md, or settings.json
- When the pipeline behaves unexpectedly
- When `verify-apd` passes but something "feels off"
- Before handing the project to another developer

**Skip when:**
- `verify-apd` itself is failing — fix those mechanical issues first
- You only need a yes/no health check — `verify-apd` is faster
- Mid-pipeline — audit is for between cycles, not during

## What This Checks (verify-apd Does NOT)

| verify-apd | /apd-audit |
|---|---|
| Files exist? | Content correct and complete? |
| JSON valid? | Hook `if` patterns correct? |
| Agents have model? | Agents have correct model/effort/color/maxTurns? |
| Pipeline runs? | Pipeline output matches expected format? |
| Mechanical ✓/✗ | Qualitative review |

## Process

### 1. Run verify-apd first

```bash
bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/verify-apd
```

If FAIL → fix those first. This skill builds on top of verify-apd, not replaces it.

### 2. Agent Quality

For each agent in `.claude/agents/*.md`:

**Frontmatter check:**
- `model:` — builders must be `sonnet`, reviewer must be `opus`
- `effort:` — builders must be `xhigh`, reviewer must be `max`
- `color:` — should be set (purple/blue/green/cyan for builders, orange for reviewer)
- `maxTurns:` — should be set (40 for builders, 30 for reviewers); legacy 20/15 auto-bumped by `apd init`
- `permissionMode:` — builders `bypassPermissions`, reviewer `plan`
- `memory: project` — should be set

**Hook check:**
- `if:` field must be inside hook objects, NOT at matcher level
- No env var prefixes in `if` patterns (e.g., `Bash(git *)` not `Bash(APD_ORCHESTRATOR_COMMIT=1 git *)`)
- Guard scripts use `${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/` paths
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
- Uses `apd pipeline` commands (not `apd-pipeline`)
- Has step 9 (finish)
- Has mandatory skills section (brainstorm, tdd, debug, finish)
- Model discipline table present (orchestrator opus, builder sonnet, reviewer opus)

### 6. Pipeline Health

```bash
bash .claude/bin/apd pipeline status
bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/apd-init --version
```

- Pipeline responds without errors
- Version matches expected

### 7. Memory Files

Check `.claude/memory/`:
- `MEMORY.md` — not empty, has project context
- `status.md` — has current phase
- `session-log.md` — exists (may be empty for new projects)
- No `[fill in]` placeholders in the last session-log entry (blocks new tasks)

### 8. Drift Detection (v6.10+)

Run the dedicated drift script — it scans three dimensions where projects typically lag behind the framework baseline:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/pipeline-audit-drift
```

**Dimensions checked:**

1. **`.claude/settings.json` deny patterns** — compares against current framework baseline (8 mkdir patterns: 4 slash-prefixed + 4 bare-dir). Pre-v6.10 re-inits left projects with only 4 patterns; v6.10 closes the bypass vector by writing all 8 on re-init.
2. **`.claude/.apd-config` APD_VERSION** — compares against the currently loaded plugin version. Stale `APD_VERSION` means the project was configured under an older minor and may carry stale workflow/agent templates. Patch-only drift is INFO; minor-or-major drift is IMPORTANT.
3. **`.claude/rules/workflow.md` content markers** — checks for presence of v6.7+ guidance markers (`Implements:`, `rationale gate`, `DEPRECATED`, `unconditional`). Missing markers indicate workflow.md was last refreshed under a pre-v6.7 framework — orchestrator does not see plan-spec consistency / rationale gate / v6.9 deprecation guidance.

**Output buckets:** CRITICAL (drift blocks pipeline structurally, rare) / IMPORTANT (drift compromises guard coverage or orchestrator guidance, most common) / INFO (patch-level, non-blocking) / CLEAN (project tracks current baseline).

**Recovery:** all drift findings point to `/apd-setup` (v6.10+ auto-fixes settings.json missing patterns + refreshes workflow.md + bumps `APD_VERSION` in `.apd-config`). Manual fixes are documented per item in the drift script output.

**Exit code:** drift script exits 1 if any CRITICAL or IMPORTANT finding, 0 if only INFO or CLEAN. Use in CI / pre-commit hooks if desired.

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

Result: X findings (Y critical, Z important)
```

## Common rationalizations

| Excuse | Reality |
|--------|---------|
| "verify-apd passes so it's fine" | verify-apd checks structure, not content quality |
| "Agents work, no need to audit" | Wrong model or missing maxTurns wastes time and money |
| "CLAUDE.md looks ok" | Missing sections mean orchestrator skips important rules |
| "I'll fix it when it breaks" | Broken pipeline produces broken code silently |

## Examples

**Example 1 — Builder agent missing maxTurns.**

*Input:* `.claude/agents/backend-api.md` frontmatter has `model: sonnet`, `effort: xhigh`, `permissionMode: bypassPermissions`, but no `maxTurns:` line. Pipeline has been re-dispatching builders 2–3× per task.

*Output:*
```
IMPORTANT:
  1. [.claude/agents/backend-api.md:5] maxTurns missing — defaults to 20
     Effect: builders hit maxTurn limit before finishing 3+ R-criteria → re-dispatch overhead
     Fix: add `maxTurns: 40` after `effort: xhigh`
```

**Example 2 — Stale skill references in CLAUDE.md.**

*Input:* `CLAUDE.md` `### Mandatory skills` table lists `/apd-init` and `/github-projects` as required. Both were renamed (`/apd-setup`, `/apd-github`).

*Output:*
```
CRITICAL:
  1. [CLAUDE.md:142] References renamed skill /apd-init
     Effect: orchestrator looks for a non-existent skill, falls back to ad-hoc setup
     Fix: replace `/apd-init` → `/apd-setup`, `/github-projects` → `/apd-github`
```

**Example 3 — Orphaned scope path on a builder.**

*Input:* `.claude/agents/frontend-web.md` has `scope: src/components/**` but the project moved to `app/components/`. `verify-apd` passed because the agent file exists; `guard-scope` blocks every builder write.

*Output:*
```
CRITICAL:
  1. [.claude/agents/frontend-web.md:8] Scope path src/components/** does not exist
     Effect: every builder write blocked by guard-scope — pipeline cannot ship
     Fix: update to `scope: app/components/**` (or run /apd-setup gap analysis)
```

## Exit criteria

You're done when:
- Every agent has been opened and its frontmatter checked against the matrix in §2
- Every required section in CLAUDE.md is present and free of unreplaced `{{PLACEHOLDER}}` values
- `.claude/settings.json` has all four required keys (env, attribution, enabledPlugins, hooks)
- `apd pipeline status` runs without error
- Findings are sorted into CRITICAL / IMPORTANT / CLEAN buckets in the output format
- If any CRITICAL is reported, the user has been told what to fix and in what order

## Hand-off

- After audit completes with CRITICAL findings → invoke `/apd-setup` to regenerate missing pieces
- After audit completes clean → continue with normal development
- If audit reveals a structural finding not covered by `/apd-setup` → escalate to user with concrete file:line references
