# TaskFlow

> Task management platform with real-time collaboration, team boards, and automated workflows.

## Critical Rules

- **Language:** English
- **Author:** Alex Morgan — NO AI signatures/watermarks
- **Style:** Professional, concise, human style

## Stack

| Layer | Technology |
|-------|------------|
| Backend | Node.js 20 + Express 5 + TypeScript |
| Database | PostgreSQL 16 + Prisma ORM |
| Frontend | React 19 + Vite + TypeScript + TailwindCSS |
| Mobile | — |
| Design | https://www.figma.com/design/xK9mR2p/TaskFlow |
| Board | https://miro.com/app/board/uXjVNq8/TaskFlow-Architecture |

## Ports (local development)

| Service | Port |
|---------|------|
| API | 3000 |
| Database | 5433 |
| Cache | 6380 |
| Frontend | 5173 |

## Architecture

```
taskflow/
├── server/
│   ├── src/
│   │   ├── routes/
│   │   ├── services/
│   │   ├── repositories/
│   │   ├── middleware/
│   │   ├── validators/
│   │   └── types/
│   ├── prisma/
│   │   ├── schema.prisma
│   │   └── migrations/
│   └── tests/
├── client/
│   ├── src/
│   │   ├── components/
│   │   ├── pages/
│   │   ├── hooks/
│   │   ├── services/
│   │   └── types/
│   └── tests/
├── docker/
│   └── docker-compose.yml
└── .github/
    └── workflows/
```

## APD — Agent Pipeline Development

### YOU ARE THE ORCHESTRATOR — follow this flow for EVERY task

```
1. RECEIVE TASK → analyze requirements
2. WRITE SPEC → present to user → WAIT FOR APPROVAL
3. WRITE PLAN → break into micro-tasks for agents
4. DISPATCH BUILDER → agent implements (you do NOT write code)
5. DISPATCH REVIEWER → agent finds bugs (opus/max, read-only)
6. RUN VERIFIER → build + test
7. COMMIT → only after all steps pass
```

**NEVER implement code directly. ALWAYS dispatch the appropriate agent.**
**NEVER proceed past step 2 without user approval.**
**ONE FEATURE = ONE COMMIT. Do not commit after each micro-task.**
**Do NOT use superpowers:subagent-driven-development or ask which approach to use. APD IS the approach. Just follow the flow above.**

### Pipeline — TECHNICALLY ENFORCED

Spec → Builder → Reviewer → Verifier → Commit

- **Hooks BLOCK commits** if pipeline steps are not completed
- Each step: `bash ${CLAUDE_PLUGIN_ROOT}/bin/pipeline-advance.sh {step}`
- There is NO skip command — every feature goes through the full pipeline
- `init` is for first project setup ONLY — not for features

### Guardrails

- `guard-git.sh` — git protection (commit/push orchestrator only, no force push, no mass staging)
- `guard-scope.sh` — file scope per agent (Write/Edit)
- `guard-bash-scope.sh` — bash write scope
- `guard-secrets.sh` — sensitive files
- `guard-lockfile.sh` — lock files
- `verify-all.sh` — build + test before commit
- `pipeline-advance.sh` + `pipeline-gate.sh` — pipeline flag system
- `rotate-session-log.sh` — automatic session log archival

### Agents

| Agent | Domain | Scope | Model | Effort |
|-------|--------|-------|-------|--------|
| backend-builder | API, services, repositories | server/ | sonnet | high |
| frontend-builder | React components, pages, hooks | client/ | sonnet | high |
| testing | Unit + integration tests | server/tests/ client/tests/ | sonnet | high |
| devops | Docker, CI/CD | docker/ .github/ | sonnet | high |
| **code-reviewer** | **Finds bugs, risks, security issues** | **reads all** | **opus** | **max** |

**For every task, dispatch the appropriate agent(s) above. Do not implement yourself.**

### Model discipline

| Role | Model | Effort |
|------|-------|--------|
| Orchestrator (you) | opus | max |
| Builder agents | sonnet | high |
| Reviewer | opus | max |

**Never use sonnet for review. Never use opus for building.**

### Human gate

API changes, migrations, auth logic, deploy → user MUST approve before action.

### Session memory

After EVERY task → append to .claude/memory/session-log.md

## Memory

@.claude/memory/MEMORY.md
@.claude/memory/status.md
@.claude/memory/session-log.md

## Rules

- `.claude/rules/workflow.md` — APD pipeline rules (copied from plugin during /apd-setup)
- `.claude/rules/principles.md` — language, code, git conventions

## Figma design

- **Figma file:** https://www.figma.com/design/xK9mR2p/TaskFlow
- Use `figma:figma-implement-design` skill for implementation from Figma
- Before implementing a UI component — always check if a Figma design exists
- Builder agent working on frontend MUST use `get_design_context` for design context
- Design tokens and colors from Figma are the source of truth — do not invent values

## Miro board

- **Miro board:** https://miro.com/app/board/uXjVNq8/TaskFlow-Architecture
- Miro MCP reads board content — sticky notes, frames, diagrams, documents
- Before creating a spec card — check if relevant content exists on the Miro board
- Orchestrator can read tasks, flow diagrams, and architecture directly from the board
- For architecture or process visualization — create a diagram on the Miro board
- Installation: `claude mcp add --transport http miro https://mcp.miro.com`

## Anti-patterns

```
❌ AI signatures in code/documentation → ✅ Human style
❌ Commit without pipeline             → ✅ Spec → Builder → Reviewer → Verifier
❌ Agent writes outside its scope      → ✅ guard-scope.sh blocks it
❌ git add . / git add -A              → ✅ Explicit staging per file
❌ --no-verify                         → ✅ Hooks must pass
```
