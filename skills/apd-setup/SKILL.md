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

The reviewer agent is mandatory — every project gets one with `opus / max / plan / orange`.

### 5b. Stack-aware scaffolding (v6.12+)

After base agents + skills exist, detect project stacks and offer to generate stack-specific agents + skills. This produces Festico-level richness automatically instead of requiring 50-100h of manual customization.

```bash
# 1. Detect what stacks are in the repo
bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/pipeline-stack-detect
```

This lists detected stacks (e.g., `.NET high`, `PHP/Symfony high`, `KMP/Compose high`) with confidence + signal file locations. Multi-stack monorepos show every detected stack.

For each detected stack with available templates (use `apd scaffold --list-stacks` to enumerate), ask the user:

> "Detected `.NET` stack with high confidence (signals: src/PLAZMA.Loyalty.sln, ...).
> Generate 3 .NET-specific agents (backend-api, database, test-guardian) + 2 skills (dotnet-conventions, ef-core-migrations)? **[Y/n]**"

If user confirms:

```bash
# 2. Dry-run first (shows what would be created/skipped)
bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/pipeline-stack-scaffold dotnet --dry-run

# 3. Actual scaffold (additive — skips existing files)
bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/pipeline-stack-scaffold dotnet
```

**Additive policy:** files that already exist in `.claude/agents/` or `.claude/skills/` are SKIPPED. Combined with v6.10 drift detection (which flags stale existing files), the user gets a safe upgrade path:

1. New file → created from stack template
2. Existing file matching baseline → kept (no churn)
3. Existing file stale per template → drift detection flags separately, user decides whether to `pipeline-stack-scaffold dotnet --force` (with `.bak.preaudit` backup)

**Multi-stack handling:** repeat per detected stack. User may opt out of any (e.g., already has custom backoffice agent — skip Node/React scaffolding for that project).

**Scope path defaults** can be overridden via environment variables before invoke (e.g., `APD_SCOPE_BACKEND=src/MyApp/`) when project layout differs from defaults.

**Supported stacks (v6.12+):** `dotnet`. Roadmap: `node-react`, `php-symfony`, `kmp-compose`, `python-django` (v6.13+).

### 5c. Reconcile the project 1:1 with the framework (v7.0.3+)

**This step is setup's job, not `apd-init`'s.** Init deliberately never rewrites a model once a profile is declared (`apd-init:336` — rewriting a hand-picked model on every session-start is the footgun v6.16.1 removed). The consequence: when the plugin changes what it ships — as v7.0 did, replacing every bare alias with a full id (`claude-opus-5`, `claude-sonnet-5`), moving the supervisor to `claude-opus-5`, and deleting guidance that v6.31 retracted — **nothing carries that into an existing project.** Setup is the only place that reconciles it, and it does so by asking.

Measured cost of not doing it (Bambi, 2026-07-26, hours after v7.0.2): 7 of 9 agents on stale models, the supervisor still on a model no profile names, `workflow.md` 103 lines behind and still instructing the orchestrator to raise `maxTurns` — a field proven inert on 2026-07-09. Every mechanical check said the project was fine.

**Gather all four before asking anything.** One report, one question.

```bash
# 1. Models vs the declared profile
bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/pipeline-model-profile status
bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/pipeline-model-profile <declared> --dry-run   # writes nothing

# 2. Config, permissions, workflow.md content
bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/pipeline-audit-drift
```

3. **Agent frontmatter vs the shipped template** — compare every agent against `reference/agent-templates.md`: `tools`, `permissionMode`, `memory`, `color`, and `memory: none` on the adversarial reviewer. `scope` is project-specific and NEVER reset; `model`/`effort` belong to the profile (item 1), not the template.

4. **Fields the framework no longer ships** — anything in an agent that the current template has no line for. `maxTurns` is the live example: removed in v6.31 after a controlled test proved CC ignores it (a subagent with `maxTurns: 3` ran 34 turns and finished). Carrying it is not harmful, but it is not configuration either, and any prose telling the user to tune it is wrong.

Present ONE report and ask once. The recommendation is **full 1:1 alignment** — never a subset, never a per-item negotiation:

> "Project declares profile `cruise`. Four things differ from framework v7.0.2:
> - **Models:** 6 builders + code-reviewer `opus / xhigh` → `claude-opus-5 / high`; supervisor `claude-fable-5 / max` → `claude-opus-5 / max`
> - **workflow.md:** 103 lines behind — still documents `maxTurns` tuning, which v6.31 removed
> - **Agent frontmatter:** 2 agents missing `permissionMode`, adversarial missing `memory: none`
> - **Dead fields:** `maxTurns` on 8 agents — no longer part of the template
>
> Recommended: align all four 1:1 with v7.0.2. Apply? **[Y/n]**"

- **User accepts** → apply all four: `apd profile <declared>` (owned roles), unowned roles to their template pin, refresh `workflow.md` from the shipped copy (init keeps `workflow.md.bak.preaudit`), fix frontmatter fields, strip dead fields. Then say the session must be restarted — agent definitions are cached at session start, and `apd profile` drops `.apd/.pending-reload` so the PreToolUse guard blocks dispatch until `apd reload-done` or a fresh session.
- **User declines** → change nothing and say so plainly. A declined reconcile is a valid end state; do not re-ask later in the same run, and do not apply "just the safe half".

**Where references collide, name the authority instead of guessing.** `model-profiles.conf` is authoritative for `model`/`effort` — a missing row means "this profile does not mention that role", never "reset it to the default row", so a declared `cruise` builder is NOT dragged down to the template's `claude-sonnet-5`. The template is authoritative for structural fields. If a project rule and a framework file genuinely conflict, report the conflict in the same report rather than silently picking a side.

If everything is in sync, say so in one line and move on.

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
- **Don't** generate the reviewer agent with a cheap or unpinned model **→ Do** use `model: claude-opus-5, effort: max, permissionMode: plan` — this is the one agent where shortcuts matter
- **Don't** hand-edit a `model:` line for a role the profile owns, and **don't** offer partial alignment ("update the builders, leave the supervisor") **→ Do** run `apd profile <declared>`, which moves every owned role at once. A profile the project only half-matches is worse than a declared drift: `apd profile status` then reports IN SYNC for a state nobody chose
- **Don't** leave a declared-but-drifted profile unmentioned because init printed "managed by profile" **→ Do** run step 5c. Init says who owns the model, not whether the value is right — reconciling is setup's job
- **Don't promise framework features that don't exist in generated CLAUDE.md / workflow.md.** Especially: `apd verify-contracts` supports **TypeScript ↔ C# only** (v6.12+). For PHP/Python/Java/Go/Ruby/Kotlin/Rust backends, the verifier ERRORS — do NOT write "apd verify-contracts automatically checks <X> DTO ↔ TS types" in generated docs for those stacks. Instead write "Cross-layer type mapping is manual — see the workflow.md section 7 table". This anti-pattern was observed in Festico apd-setup (2026-05-28) — orchestrator confabulated PHP support claim that does not exist. When uncertain about framework feature scope, read `${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/<command>` script header for exact supported scope, or `docs/SPEC.md`.

## Exit criteria

You're done when:
- `apd-init` and `session-start` ran successfully and the `apd` shortcut works
- For new setup: every file in the "What gets generated" table exists with no placeholders left
- For maintenance: every gap analysis row is either ✓ or has been fixed
- `bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/verify-apd` passes (X PASS / 0 FAIL)
- The reviewer agent exists with `opus / max / plan / orange`
- `.claude/.apd-config` (or `.apd/config`) is present with `PROJECT_NAME`, `APD_VERSION`, `STACK`
- `.mcp.json` recommendations have been presented to the user (and either accepted or skipped explicitly)
- If a profile is declared, `pipeline-model-profile status` was run and its verdict acted on: IN SYNC reported in one line, or DRIFTED presented as a single full-alignment offer that the user explicitly accepted or declined

## Hand-off

- After successful setup → invoke `apd-audit` to confirm content quality (mechanical checks just passed; quality is a separate gate)
- After audit clean → start your first pipeline cycle with `apd pipeline spec "<task>"`
- If `verify-apd` still has FAILs after this skill runs → escalate to user with concrete file:line references; do NOT silently rerun the skill
