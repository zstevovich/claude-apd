# apd-setup — File generation reference

Specs for every non-agent file that `apd-setup` writes. Loaded on demand by SKILL.md.

## CLAUDE.md

Generate with these sections, all populated, no `{{PLACEHOLDER}}` left behind:

- `# {Name}` + `> {Description}`
- `## Critical rules` — language, author, style
- `## Stack` — table with backend, database, frontend, mobile, design, board, tracking
- `## Ports` — table
- `## Architecture` — `ls` output of the project root
- `## APD` — orchestrator role, pipeline reference, guardrails, agents table (with Model + Effort columns), model discipline, human gate, session memory
- `## Memory` — `@.claude/memory/` references
- `## Rules` — references to rules files
- `## Figma design` — only if a Figma URL was provided
- `## Miro board` — only if a board URL was provided
- `## GitHub Projects` — only if a board URL was provided
- `## Anti-patterns`

## verify-all.sh

Read the snippet from `${CLAUDE_PLUGIN_ROOT}/plugins/apd/templates/verify-all/{stack}.sh`. Generate `.claude/scripts/verify-all.sh` with:

- Shebang + header comment
- Verifier cache check block
- Stack-specific build/test snippet (from the template)
- Error reporting footer
- `chmod +x` after write

## Rules

**`workflow.md`** — copy verbatim from the plugin (rules are NOT auto-loaded from plugins, they live per-project):

```bash
cp "${CLAUDE_PLUGIN_ROOT}/plugins/apd/rules/workflow.md" .claude/rules/workflow.md
```

**`principles.md`** — read `${CLAUDE_PLUGIN_ROOT}/plugins/apd/templates/principles/{language}.md`. Adapt for the stack — add the architectural pattern and port range. Place in `.claude/rules/principles.md`.

## Memory files

Generate four files under `.claude/memory/`:

| File | Initial content |
|---|---|
| `MEMORY.md` | Project name, agents list, stack, port range |
| `status.md` | Initial phase ("Setup complete — ready for first pipeline cycle") |
| `session-log.md` | Empty file with header |
| `pipeline-skip-log.md` | Empty file with header + table column row |

## Configuration

**`.claude/settings.json`** — must include env, attribution, notification, AND disable superpowers:

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

**`.claude/.apd-config`:**

```
PROJECT_NAME={name}
APD_VERSION={read from plugin VERSION file}
STACK={stack}
```

**`.claude/.apd-version`** — current version string from `plugins/apd/VERSION`.

## Gitignore

Add entries from `${CLAUDE_PLUGIN_ROOT}/plugins/apd/templates/gitignore-entries.txt` if missing — never duplicate. Add `.mcp.json` to `.gitignore` separately if MCP setup ran (it may contain credentials).

## MCP recommendations

Generate `.mcp.json` based on the project's stack and configured integrations.

**Always recommend:**

| MCP Server | Command | Why |
|---|---|---|
| context7 | `npx -y @upstash/context7-mcp@latest` | Library docs lookup — works for any stack |

**Stack-driven:**

| If stack includes | MCP Server | Command |
|---|---|---|
| PostgreSQL | postgres | `npx -y @modelcontextprotocol/server-postgres "postgresql://user@localhost:{port}/{db}"` |
| Docker | docker | `docker ai mcp-server` |

**Integration-driven:**

| If configured | MCP Server | Command |
|---|---|---|
| GitHub Projects URL | github | `npx -y @modelcontextprotocol/server-github` (envCommand: `gh auth token`) |
| Miro board URL | miro | HTTP transport: `https://mcp.miro.com` |

**Procedure:**

1. Present recommendations as a checklist:
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
   - **Do NOT ask for password** — leave empty, the user fills it in later

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

4. Add `.mcp.json` to `.gitignore` if not already there.
