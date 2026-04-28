# apd-setup — Gap analysis & verification reference

Loaded on demand by SKILL.md. Use during Step 2 (gap analysis on existing projects) and Step 6 (verification).

## Gap analysis checklist

When CLAUDE.md or `.claude/` already exists, run these checks. Generate ONLY missing pieces — never overwrite existing files.

| Check | File | If missing |
|---|---|---|
| Reviewer agent | `.claude/agents/code-reviewer.md` | Generate from `${CLAUDE_PLUGIN_ROOT}/plugins/apd/templates/reviewer-template.md` |
| Builder maxTurns | `.claude/agents/*.md` frontmatter | Add `maxTurns: 40` (builders) / `30` (reviewers) — bumps legacy 20/15 defaults |
| Reviewer model | `code-reviewer.md` frontmatter | Must be `model: opus`, `effort: max`, `permissionMode: plan` |
| Workflow rules | `.claude/rules/workflow.md` | Copy from `${CLAUDE_PLUGIN_ROOT}/plugins/apd/rules/workflow.md` |
| Principles | `.claude/rules/principles.md` | Generate from template |
| Memory files | `.claude/memory/` (4 files) | Generate the missing ones only |
| `.apd-config` | `.claude/.apd-config` | Generate with `PROJECT_NAME`, `APD_VERSION`, `STACK` |
| `verify-all.sh` | `.claude/scripts/verify-all.sh` | Generate from the stack template |
| CLAUDE.md sections | Orchestrator role, model discipline | Add the missing sections inline |
| Superpowers disabled | `.claude/settings.json` has `superpowers: false` | Add `"superpowers@claude-plugins-official": false` to `enabledPlugins` |

Show the analysis to the user before fixing anything:

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

Only proceed after explicit user approval.

## Example walkthrough — fresh init

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

## Verification

After all generation steps, run the mechanical check:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/verify-apd
```

The check must report `0 FAIL` before the skill finishes. If a FAIL is reported, escalate to the user with the concrete file and line — do NOT silently rerun the skill or attempt to patch the failure on the fly.
