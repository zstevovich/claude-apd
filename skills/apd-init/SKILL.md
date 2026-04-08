---
name: apd-init
description: Initialize APD environment — generates CLAUDE.md, agents, rules, memory and verify-all.sh. Scripts live in the plugin.
effort: max
---

# APD Init — Generator

Generates a complete APD environment for a project. Scripts live in the plugin (`${CLAUDE_PLUGIN_ROOT}/scripts/`), this skill creates only project-specific files.

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
| `.claude/.apd-config` | PROJECT_NAME, APD_VERSION, STACK |
| `.claude/.apd-version` | APD plugin version |

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
| Builder maxTurns | `.claude/agents/*.md` frontmatter | Add `maxTurns: 20` to each builder agent |
| Reviewer model | `code-reviewer.md` frontmatter | Must be `model: opus`, `effort: max`, `permissionMode: plan` |
| Workflow rules | `.claude/rules/workflow.md` | Copy from `${CLAUDE_PLUGIN_ROOT}/rules/workflow.md` |
| Principles | `.claude/rules/principles.md` | Generate from template |
| Memory files | `.claude/memory/` (4 files) | Generate missing ones |
| .apd-config | `.claude/.apd-config` | Generate with project name, version, stack |
| verify-all.sh | `.claude/scripts/verify-all.sh` | Generate from stack template |
| CLAUDE.md sections | Orchestrator role, model discipline | Add missing sections |

Show the analysis to the user:
```
APD gap analysis:
  ✓ CLAUDE.md exists
  ✓ 3 builder agents
  ✗ code-reviewer.md MISSING — will generate (opus/max/read-only)
  ✗ maxTurns missing in builder agents — will add (20)
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
- Frontmatter: name, description, tools (Read/Write/Edit/Glob/Grep/Bash), **model: sonnet**, **effort: high**, maxTurns: 20, permissionMode: bypassPermissions
- Hooks with `${CLAUDE_PLUGIN_ROOT}/scripts/` paths
- guard-scope.sh and guard-bash-scope.sh with exact SCOPE_PATHS
- Body: role, stack, workflow, FORBIDDEN

**Reviewer agent** — ALWAYS generated, from `${CLAUDE_PLUGIN_ROOT}/templates/reviewer-template.md`:
- Frontmatter: name: code-reviewer, tools (Read/Glob/Grep/Bash — **NO Write/Edit**), **model: opus**, **effort: max**, maxTurns: 15, **permissionMode: plan** (read-only)
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

`.claude/settings.json` — Must include env, attribution, and notification:
```json
{
  "env": {
    "APD_PROJECT_NAME": "{name}"
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
APD_VERSION=3.0.0
STACK={stack}
```

`.claude/.apd-version`: `3.0.0`

#### 4.7 Gitignore

Add entries from `${CLAUDE_PLUGIN_ROOT}/templates/gitignore-entries.txt` if missing.

### 5. Verify

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify-apd.sh
```

## Example

```
User: /apd-init
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
  ✓ CLAUDE.md generated
  ✓ 4 agents created
  ✓ verify-all.sh configured for Node.js
  ✓ principles.md generated
  ✓ Memory initialized
  ✓ .apd-config created

  verify-apd.sh: 52 PASS, 0 FAIL
```
