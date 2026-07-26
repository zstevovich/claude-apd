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
| Agents have model? | Agents have correct model/effort/color? |
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

**Roles that must EXIST** — check presence before quality:
- `code-reviewer` — missing → the reviewer advance BLOCKs
- `adversarial-reviewer` — missing → the reviewer advance BLOCKs (`adversarial-agent-missing`).
  Until v7.0 its absence silently disabled the whole adversarial layer, so a project
  that has been running "clean" without this file was running without the layer.
- `supervisor` — missing → `supervision-missing` at the verifier (every profile since v7.0)

**Frontmatter check:**
- `model:` — **full ids only, never a bare alias.** `opus`/`sonnet` resolve to whatever
  the runtime maps them to today, which is how a corpus moved between model generations
  unnoticed. Builders `claude-sonnet-5`, `code-reviewer` `claude-opus-5`,
  `adversarial-reviewer` `claude-sonnet-5`, `supervisor` `claude-opus-5`.
  **Do not "fix" a model a profile owns:** `apd profile status` shows which roles the
  declared `MODEL_PROFILE` manages. A conf with no row for a role means the template pin
  stands — flag a mismatch, do not rewrite it.
- `effort:` — builders `xhigh`; `code-reviewer`, `adversarial-reviewer` and `supervisor` `max`
- `color:` — should be set (purple/blue/green/cyan for builders, orange for reviewer)
- `permissionMode:` — builders `bypassPermissions`, reviewers `plan`
- `memory:` — `project` for builders, but **`none` for `adversarial-reviewer` and
  `supervisor`**. Those two carry the decontextualization contract; flagging them for a
  missing `memory: project` inverts the thing that makes them worth dispatching.

**Hook check:**
- `if:` field must be inside hook objects, NOT at matcher level
- No env var prefixes in `if` patterns (e.g., `Bash(git *)` not `Bash(APD_ORCHESTRATOR_COMMIT=1 git *)`)
- Guard paths use `${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/adapter/cc/` (the CC shims;
  `bin/core/` holds the runtime-neutral implementations they call)
- Builders declare: guard-scope, guard-bash-scope, guard-secrets, guard-git
- Reviewers declare: guard-secrets, guard-git (NO guard-scope — read-only)
- `adversarial-reviewer` must carry the `guard-spec-blind` marker (v7.0)

> **The per-agent `hooks:` block is DATA, not execution.** It never fires (measured on
> CC 2.1.220) — enforcement runs session-level from `hooks/hooks.json`. But
> `bin/lib/agent-scope.sh` resolves an agent's writable scope by reading the `guard-scope`
> command out of that block when no YAML `scope:` key exists. So a wrong SCOPE_PATHS list
> there is a live enforcement defect, and a missing block on a writable agent fails closed.

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
- `### Mandatory skills` — the table must name **`apd-pipeline-guide`** (mandatory before
  every task since v6.15, hard-gated by `.guide-marker`); brainstorm is advisory, not the gate
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
- `permissions.allow` includes `Edit(.claude/memory/**)` and every pipeline file the
  framework mandates writing: `spec-card.md`, `implementation-plan.md`,
  `.adversarial-summary`, `.adversarial-rationale.md`, `.supervision-summary`,
  `.supervision-rationale.md`, `.guide-marker`
- **`Edit(...)` only — never ask for a `Write(...)` twin.** Since CC 2.1.208 `Edit(path)`
  covers every file-editing tool and a `Write(path)` rule is inert for file-permission
  checks; `apd-init` strips legacy APD Write twins on each run, so demanding them here
  would make the audit and init undo each other on every session-start
- Notification hook configured

### 5. Workflow Rules

Read `.claude/rules/workflow.md` and verify:
- Uses `apd pipeline` commands (not `apd-pipeline`)
- Has step 9 (finish)
- Has the mandatory skills section (apd-pipeline-guide first — it carries the gate contract)
- Model discipline table present, written with full model ids (never bare aliases). The
  orchestrator's own model is not APD-managed; `MODEL_PROFILE` governs agents only

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
3. **`.claude/rules/workflow.md` content markers** — checks presence of six guidance markers (`Implements:`, `rationale gate`, `DEPRECATED`, `unconditional`, `apd-pipeline-guide`, `SUPERVISION`). Missing markers mean workflow.md was last refreshed under an older framework, so the orchestrator never sees plan-spec consistency, the rationale gate, the v6.15 guide gate or the v6.30 supervision layer. Read the marker list from the script rather than this page if they disagree — the script is the authority.

4. **Feature claim drift** (v6.12.3+) — scans `workflow.md` and `CLAUDE.md` for orchestrator confabulation patterns claiming features the framework does not ship. Specifically: any line that mentions BOTH a contracts command (`verify-contracts`, `apd contracts`) AND an unsupported language (PHP/Python/Java/Go/Ruby/Kotlin/Rust). First documented instance: Festico apd-setup (2026-05-28) — orchestrator wrote "apd verify-contracts automatically checks PHP DTO ↔ TS types" which is false; framework supports TS ↔ C# only. Detection prevents silent gaps in cross-layer review coverage where humans rely on a feature that errors at runtime.

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
| "Agents work, no need to audit" | Wrong model or unbounded scope wastes time and money |
| "CLAUDE.md looks ok" | Missing sections mean orchestrator skips important rules |
| "I'll fix it when it breaks" | Broken pipeline produces broken code silently |

## Examples

**Example 1 — Builder agent missing scope.**

*Input:* `.claude/agents/backend-api.md` frontmatter has `model`, `effort`, `permissionMode: bypassPermissions`, but no `scope:` line. The builder can write anywhere in the repo.

*Output:*
```
IMPORTANT:
  1. [.claude/agents/backend-api.md] scope missing — builder writes are unbounded
     Effect: out-of-scope edits slip past the guard that keys on declared scope
     Fix: declare the builder's scope paths (the `{{SCOPE_PATHS}}` the guard-scope
     and guard-bash-scope hooks enforce) so writes outside them are blocked
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
