---
name: apd-setup
description: Use when setting up APD in a new project for the first time or maintaining an existing APD-enabled project — generates CLAUDE.md, per-agent .md files, rules, memory, verify-all.sh, and runs gap analysis to fix missing pieces. Triggers on "setup APD", "init APD", "scaffold APD", "configure APD", "first run", "install APD", "apd init", "set up the framework", "APD missing", any project where .apd/ is incomplete or absent.
disable-model-invocation: true
effort: max
allowed-tools: Read Glob Grep Bash Edit Write
---

# APD Setup

> Manual-only skill (`disable-model-invocation: true`). The user invokes it
> with `/apd-setup`. CC-only — on Codex use the `apd cdx init` CLI.

## When to use / When to skip

**Use when:**
- Setting up APD in a new project for the first time
- Maintaining an existing APD project (gap analysis fills missing pieces)
- After a major framework upgrade — gap analysis flags deprecated patterns
- After manually editing `.claude/` and wanting to validate

**Skip when:**
- The project is already fully configured and `apd-audit` is clean — nothing to do
- You're inside an active pipeline cycle — wait for the cycle to close
- The project is Codex-only — use `apd cdx init` CLI instead, this skill writes `.claude/` paths

## What gets generated (in the project)

| File | Content |
|---|---|
| `CLAUDE.md` | Project instructions — generated from user responses |
| `.claude/agents/*.md` | Agents with scopes and `${CLAUDE_PLUGIN_ROOT}` hook paths |
| `.claude/rules/principles.md` | Rules for the user's stack and language |
| `.claude/scripts/verify-all.sh` | Build/test commands for the stack |
| `.claude/memory/MEMORY.md` | Project memory index |
| `.claude/memory/status.md` | Current status |
| `.claude/memory/session-log.md` | Session log (empty) |
| `.claude/memory/pipeline-skip-log.md` | Skip log (empty) |
| `.claude/settings.json` | Minimal hooks (Notification) + env + attribution |
| `.claude/.apd-config` | `PROJECT_NAME`, `APD_VERSION`, `STACK` (CC-native activation marker) |
| `.claude/.apd-version` | APD plugin version |

> **Dual activation paths.** APD recognizes two locations for the config file:
> - `.claude/.apd-config` — CC-native (what this skill generates; used on all CC-enabled projects)
> - `.apd/config` — runtime-neutral, used on pure-Codex projects that never create `.claude/` (auto-seeded by `apd cdx init`)
>
> The framework reads either; write to whichever matches the host runtime. Hybrid projects work with either.

## What does NOT get generated (lives in the plugin)

Guard scripts, pipeline scripts, workflow.md, skills — all live in the plugin and are used via `${CLAUDE_PLUGIN_ROOT}`.

## Steps

### 1. Run the init scripts FIRST — do not analyse the project before this

```bash
bash "${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/apd-init"
bash "${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/session-start"
```

Do NOT skip this. Do NOT do your own analysis instead. Run both scripts and read their output. The second script creates the `apd` shortcut and loads project context. Only proceed to step 2 if the scripts report missing files.

### 2. Detect existing environment

Check whether `.claude/` or `CLAUDE.md` already exists:

- **If NOT present** → clean init (continue to step 3)
- **If PRESENT** → run gap analysis and offer to fill missing pieces

**Gap analysis checklist + example output:** See [reference/init-checklist.md](reference/init-checklist.md).

Show the analysis to the user, generate ONLY what is missing, and never overwrite existing files.

### 3. Gather information from the user

Some values come pre-filled from plugin userConfig (set at `plugin enable` time):

- **Project name** — read from `$CLAUDE_PLUGIN_OPTION_PROJECT_NAME` (confirm with user)
- **Stack** — read from `$CLAUDE_PLUGIN_OPTION_STACK` (confirm with user)
- **Author** — read from `$CLAUDE_PLUGIN_OPTION_AUTHOR_NAME` (confirm with user)

Ask only for values NOT provided by userConfig:

- Project description (one sentence)
- Ports (API, database, cache, frontend)
- Documentation language (English/Serbian)
- Figma URL (optional)
- Miro board URL (optional)
- GitHub Projects URL (optional)

### 4. Auto-detect agents from project structure

Read the layout with `ls -d */` and propose builder agents.

**Detection rules + per-role agent specs (builder + reviewer):** See [reference/agent-templates.md](reference/agent-templates.md).

Show the suggestion — the user approves or adjusts before generation.

### 5. Generate files

Generate each file from the per-role and per-template rules:

- **Agents (builder + reviewer):** See [reference/agent-templates.md](reference/agent-templates.md).
- **CLAUDE.md, verify-all.sh, rules, memory, settings, gitignore, MCP recommendations:** See [reference/rules-templates.md](reference/rules-templates.md).

The reviewer agent is mandatory — every project gets one with `opus / max / plan / orange / maxTurns: 80`.

### 6. Verify

```bash
bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/verify-apd
```

The check must report `0 FAIL` before this skill finishes. If a FAIL surfaces, escalate to the user with the concrete file and line — do NOT silently rerun.

## Anti-patterns

- **Don't** start asking the user questions before running `apd-init` and `session-start` **→ Do** run the scripts first; they may already have set up most of the project
- **Don't** overwrite existing files during gap analysis **→ Do** generate ONLY missing files; touch existing ones only if they're literally empty or marked stale
- **Don't** populate `CLAUDE.md` with `{{PLACEHOLDER}}` values **→ Do** ask the user (or read from `CLAUDE_PLUGIN_OPTION_*` env vars) and fill every placeholder
- **Don't** assume the stack from one folder name **→ Do** read enough of the project (`package.json`, `pom.xml`, `Cargo.toml`, etc.) to confirm before suggesting agents
- **Don't** generate the reviewer agent with `model: sonnet` **→ Do** use `model: opus, effort: max, permissionMode: plan` — this is the one agent where shortcuts matter

## Exit criteria

You're done when:
- `apd-init` and `session-start` ran successfully and the `apd` shortcut works
- For new setup: every file in the "What gets generated" table exists with no placeholders left
- For maintenance: every gap analysis row is either ✓ or has been fixed
- `bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/verify-apd` passes (X PASS / 0 FAIL)
- The reviewer agent exists with `opus / max / plan / orange / maxTurns: 80`
- `.claude/.apd-config` (or `.apd/config`) is present with `PROJECT_NAME`, `APD_VERSION`, `STACK`
- `.mcp.json` recommendations have been presented to the user (and either accepted or skipped explicitly)

## Hand-off

- After successful setup → invoke `apd-audit` to confirm content quality (mechanical checks just passed; quality is a separate gate)
- After audit clean → start your first pipeline cycle with `apd pipeline spec "<task>"`
- If `verify-apd` still has FAILs after this skill runs → escalate to user with concrete file:line references; do NOT silently rerun the skill
