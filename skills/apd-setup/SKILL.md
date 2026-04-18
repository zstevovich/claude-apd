---
name: apd-setup
description: Use when setting up APD in a new project or maintaining an existing one. Generates CLAUDE.md, agents, rules, memory, verify-all.sh. Also runs gap analysis and fixes missing pieces on existing projects.
disable-model-invocation: true
effort: max
---

# APD Setup

**Step 1 — MANDATORY: Run the init script AND session-start. Do this FIRST before anything else.**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/core/apd-init"
bash "${CLAUDE_PLUGIN_ROOT}/bin/core/session-start"
```

Do NOT skip this. Do NOT do your own analysis. Run both scripts and read their output.
The second script creates the `apd` shortcut and loads project context.

**Step 2 — Only if the script says CLAUDE.md or agents are missing:**

Generate project-specific files that the script cannot create (they require analysis):

## What gets generated (in the project)

| File | Content |
|------|---------|
| `CLAUDE.md` | Project instructions — generated from user responses |
| `.claude/agents/*.md` | Agents with scopes and `${CLAUDE_PLUGIN_ROOT}` hook paths |
| `.claude/rules/principles.md` | Rules for the user's stack and language |
| `.claude/scripts/verify-all.sh` | The only script in the project — build/test commands for the stack |
| `.claude/memory/MEMORY.md` | Project memory index |
| `.claude/memory/status.md` | Current status |
| `.claude/memory/session-log.md` | Session log (empty) |
| `.claude/memory/pipeline-skip-log.md` | Skip log (empty) |
| `.claude/settings.json` | Minimal hooks (Notification) + env + attribution |
| `.claude/.apd-config` | PROJECT_NAME, APD_VERSION, STACK (CC-native activation marker) |
| `.claude/.apd-version` | APD plugin version |

> **Dual activation paths.** APD recognizes two locations for the config file:
> - `.claude/.apd-config` — CC-native (what this skill generates; used on all CC-enabled projects)
> - `.apd/config` — runtime-neutral, used on pure-Codex projects that never create `.claude/` (auto-seeded by `apd cdx init`)
>
> The framework reads either; write to whichever matches the host runtime. Hybrid projects work with either.

## What does NOT get generated (lives in the plugin)

Guard scripts, pipeline scripts, workflow.md, skills — all live in the plugin and are used via `${CLAUDE_PLUGIN_ROOT}`.

## Steps

### 1. Detect existing environment

Check whether `.claude/` or `CLAUDE.md` already exists:

- **If NOT present** → clean init (full generation flow below)
- **If PRESENT** → run **gap analysis** and offer to fill missing pieces:

#### Gap analysis checklist

| Check | File | If missing |
|-------|------|------------|
| Reviewer agent | `.claude/agents/code-reviewer.md` | Generate from `${CLAUDE_PLUGIN_ROOT}/templates/reviewer-template.md` |
| Builder maxTurns | `.claude/agents/*.md` frontmatter | Add `maxTurns: 40` (builders) / `30` (reviewers) — bumps legacy 20/15 defaults |
| Reviewer model | `code-reviewer.md` frontmatter | Must be `model: opus`, `effort: max`, `permissionMode: plan` |
| Workflow rules | `.claude/rules/workflow.md` | Copy from `${CLAUDE_PLUGIN_ROOT}/rules/workflow.md` |
| Principles | `.claude/rules/principles.md` | Generate from template |
| Memory files | `.claude/memory/` (4 files) | Generate missing ones |
| .apd-config | `.claude/.apd-config` | Generate with project name, version, stack |
| verify-all.sh | `.claude/scripts/verify-all.sh` | Generate from stack template |
| CLAUDE.md sections | Orchestrator role, model discipline | Add missing sections |
| Superpowers disabled | `.claude/settings.json` has `superpowers: false` | Add `"superpowers@claude-plugins-official": false` to enabledPlugins |

Show the analysis to the user:
```
APD gap analysis:
  ✓ CLAUDE.md exists
  ✓ 3 builder agents
  ✗ code-reviewer.md MISSING — will generate (opus/max/read-only)
  ✗ maxTurns missing in builder agents — will add (40 builders / 30 reviewers)
  ✓ workflow.md exists
  ✓ verify-all.sh configured
  ✓ Memory files (4/4)

Fix 2 gaps? (yes/no)
```

Generate ONLY what is missing. Do NOT overwrite existing files.

### 2. Gather information from the user

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

### 3. Auto-detect agents from project structure

Read the structure with `ls -d */` and suggest agents:

| Detected directory | Suggested agent | Scope |
|-------------------|----------------|-------|
| `src/` or `server/` or `backend/` or `api/` | backend-builder | detected dir |
| `client/` or `frontend/` or `web/` or `apps/frontend/` | frontend-builder | detected dir |
| `mobile/` or `apps/mobile/` | mobile-builder | detected dir |
| `tests/` or `__tests__/` or `test/` or `src/test/` | testing | detected dir |
| `docker/` or `.github/` or `deploy/` or `infra/` | devops | detected dirs |
| `src/Commands/` + `src/Queries/` | CQRS agents | by responsibility |

Show the suggestion — user approves or adjusts.

### 4. Generate files

#### 4.1 CLAUDE.md

Generate with sections (ALL populated, NO placeholders):
- `# {Name}` + `> {Description}`
- `## Critical rules` — language, author, style
- `## Stack` — table with layers (backend, database, frontend, mobile, design, board, tracking)
- `## Ports` — table
- `## Architecture` — `ls` output
- `## APD` — orchestrator role, pipeline, guardrails, agents table (with Model + Effort columns), model discipline, human gate, session memory
- `## Memory` — `@.claude/memory/` references
- `## Rules` — references to rules
- `## Figma design` — only if present
- `## Miro board` — only if present
- `## GitHub Projects` — only if present
- `## Anti-patterns`

#### 4.2 Agents

**Builder agents** — one per domain, from `${CLAUDE_PLUGIN_ROOT}/templates/agent-template.md`:
- Frontmatter: name, description, tools (Read/Write/Edit/Glob/Grep/Bash), **model: sonnet**, **effort: xhigh**, maxTurns: 40, permissionMode: bypassPermissions
- **color:** assign per role — backend: `purple`, frontend: `blue`, testing: `green`, other: `cyan`
- Hooks with `${CLAUDE_PLUGIN_ROOT}/bin/core/` paths
- guard-scope and guard-bash-scope with exact SCOPE_PATHS
- Body: role, stack, workflow, FORBIDDEN

**Reviewer agent** — ALWAYS generated, from `${CLAUDE_PLUGIN_ROOT}/templates/reviewer-template.md`:
- Frontmatter: name: code-reviewer, tools (Read/Glob/Grep/Bash — **NO Write/Edit**), **model: opus**, **effort: max**, maxTurns: 30, **permissionMode: plan** (read-only), **color: orange**
- NO guard-scope (reviewer reads everything, writes nothing)
- Body: review checklist, output format, verdict

The reviewer is **mandatory** — every project gets one. It uses opus/max because finding bugs requires deeper reasoning than writing code.

GENERATE agents from the templates — do not copy literally.

#### 4.3 verify-all.sh

Read the snippet from `${CLAUDE_PLUGIN_ROOT}/templates/verify-all/{stack}.sh`.
Generate `.claude/scripts/verify-all.sh` with:
- Shebang + header comment
- Verifier cache check block
- Stack-specific build/test snippet
- Error reporting footer
- `chmod +x`

#### 4.4 Rules

**workflow.md** — Copy from the plugin (rules are NOT auto-loaded from plugins):
```bash
cp "${CLAUDE_PLUGIN_ROOT}/rules/workflow.md" .claude/rules/workflow.md
```

**principles.md** — Read `${CLAUDE_PLUGIN_ROOT}/templates/principles/{language}.md`.
Adapt for the stack — add architectural pattern and port range.
Place in `.claude/rules/principles.md`.

#### 4.5 Memory files

Generate in `.claude/memory/`:
- `MEMORY.md` — name, agents, stack, port range
- `status.md` — initial phase
- `session-log.md` — empty with header
- `pipeline-skip-log.md` — empty with header and table

#### 4.6 Configuration

`.claude/settings.json` — Must include env, attribution, notification, AND disable superpowers:
```json
{
  "env": {
    "APD_PROJECT_NAME": "{name}"
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": false
  },
  "attribution": {
    "commit": "",
    "pr": ""
  },
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo '[{name}] Claude needs attention'"
          }
        ]
      }
    ]
  }
}
```

`.claude/.apd-config`:
```
PROJECT_NAME={name}
APD_VERSION={from plugin.json}
STACK={stack}
```

`.claude/.apd-version`: current version from plugin.json

#### 4.7 Gitignore

Add entries from `${CLAUDE_PLUGIN_ROOT}/templates/gitignore-entries.txt` if missing.

#### 4.8 MCP Configuration

Based on the project's stack and integrations, recommend and generate `.mcp.json`.

**Always recommend:**

| MCP Server | Command | Why |
|---|---|---|
| context7 | `npx -y @upstash/context7-mcp@latest` | Library documentation lookup — works for any stack |

**Recommend based on stack:**

| If stack includes | MCP Server | Command |
|---|---|---|
| PostgreSQL | postgres | `npx -y @modelcontextprotocol/server-postgres "postgresql://user@localhost:{port}/{db}"` |
| Docker | docker | `docker ai mcp-server` |

**Recommend based on integrations:**

| If configured | MCP Server | Command |
|---|---|---|
| GitHub Projects URL | github | `npx -y @modelcontextprotocol/server-github` (envCommand: `gh auth token`) |
| Miro board URL | miro | HTTP transport: `https://mcp.miro.com` |

**Procedure:**

1. Present recommendations as a checklist based on detected stack:
```
Recommended MCP servers for your stack (Node.js + PostgreSQL):
  ✓ context7 — library docs (always recommended)
  ✓ postgres — direct database access
  ✓ github — issues, PRs (GitHub Projects detected)
  ○ docker — skip (no Docker detected)
  ○ miro — skip (no Miro board)

Include all recommended? (yes / adjust)
```

2. For database MCP servers, ask for connection details:
   - Host (default: localhost)
   - Port (from project Ports table)
   - User (default: postgres / root)
   - Database name (from project name, lowercase)
   - **Do NOT ask for password** — leave empty, user fills in later

3. Generate `.mcp.json` in project root:
```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"]
    },
    "postgres": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-postgres",
        "postgresql://postgres@localhost:5433/mycrm"
      ]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "envCommand": "bash -c 'echo GITHUB_PERSONAL_ACCESS_TOKEN=$(gh auth token)'"
    }
  }
}
```

4. Add `.mcp.json` to `.gitignore` if not already there (may contain credentials).

### 5. Verify

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/core/verify-apd
```

## Example

```
User: /apd-setup
Claude: What is the project name?
User: MyCRM
Claude: Stack?
User: Node.js + Express, React + Vite, PostgreSQL
Claude: Ports?
User: 3000 API, 5433 PG, 6380 Redis, 5173 Frontend
Claude: Figma?
User: https://www.figma.com/design/abc123
Claude: Miro?
User: No
Claude: Reading structure...

  Suggested agents:
  | Agent             | Scope          |
  | backend-builder   | server/        |
  | frontend-builder  | client/        |
  | testing           | tests/         |
  | devops            | docker/ .github/ |

  Approve or adjust:
User: Ok

Claude:
  Recommended MCP servers for Node.js + PostgreSQL:
    ✓ context7 — library docs
    ✓ postgres — database access (localhost:5433/mycrm)
    ✓ github — issues, PRs
    ○ docker — skip
    ○ miro — skip
User: Ok

Claude:
  ✓ CLAUDE.md generated
  ✓ 4 agents created
  ✓ verify-all.sh configured for Node.js
  ✓ principles.md generated
  ✓ Memory initialized
  ✓ .apd-config created
  ✓ .mcp.json generated (3 servers)

  verify-apd: 52 PASS, 0 FAIL
```
