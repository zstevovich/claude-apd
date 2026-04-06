# Getting Started with APD

From zero to your first pipeline commit in 5 minutes.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- `jq` installed (`brew install jq` on macOS, `apt install jq` on Linux)
- A git repository with some code in it

---

## Step 1 — Copy the template

```console
~/Projects $ cp -r apd-template/.claude/ my-project/.claude/
~/Projects $ cp apd-template/CLAUDE.md my-project/
~/Projects $ cp apd-template/.mcp.json.example my-project/.mcp.json
~/Projects $ cp -r apd-template/docs/ my-project/docs/
```

## Step 2 — Initialise

Open Claude Code in your project directory and run:

```console
~/Projects/my-project $ claude
> /apd-init
```

The skill will ask for:
- Project name and path
- Stack (backend, frontend, database)
- Ports
- Figma URL (optional)
- Miro board URL (optional)
- GitHub Projects URL (optional)

It will then:
- Replace all `{{PLACEHOLDER}}` values
- Detect your directory structure and propose agents
- Create agent files with correct scope and hooks
- Configure build/test commands

## Step 3 — Verify the setup

```console
~/Projects/my-project $ bash .claude/scripts/verify-apd.sh
```

> **Expected result:**
>
> | Check | Result |
> |-------|--------|
> | Project | YourProject |
> | Agents | 4 (backend-builder, frontend-builder, testing, devops) |
> | Scripts | 10/10 |
> | Guards | git, scope, bash-scope, lockfile, secrets |
> | Pipeline | functional (E2E + rollback) |
> | verify-all.sh | active (2 checks) |
> | Memory files | 4/4 |
> | Gitignore | local.json, .pipeline/ |
> | Attribution | empty (OK) |
> | **Result** | **PASS: 51 · FAIL: 0 · WARN: 0** |

If you see any FAIL items, follow the instructions in the output to fix them.

---

## Step 4 — Your first pipeline task

### 4.1 Create a spec

```console
~/Projects/my-project $ bash .claude/scripts/pipeline-advance.sh spec "Add user login endpoint"
Pipeline započet: Add user login endpoint [2026-04-06 10:00:00]
  [DONE] spec   2026-04-06 10:00:00
  [----] builder
  [----] reviewer
  [----] verifier
```

Then write the spec card for the user to approve:

> **Add user login endpoint**
>
> **Goal:** POST /api/auth/login accepting email + password, returning JWT.
> **Effort:** high
> **Out of scope:** Registration, password reset.
> **Acceptance criteria:**
> - Returns 200 with JWT on valid credentials
> - Returns 401 on invalid credentials
> - Password compared via bcrypt
>
> **Affected modules:** src/Auth/
> **Risks:** None — new endpoint, no existing code affected.
> **Rollback:** Delete the handler file.
> **Human gate:** No — new endpoint, does not change existing API.

Share with the user. Wait for approval before proceeding.

### 4.2 Dispatch a builder

```console
> dispatch backend-builder with the approved spec
```

The builder agent will:
- Read the spec
- Implement the code (max 3–4 edit operations)
- Stay within its allowed scope (`guard-scope.sh` enforces this)
- Not commit anything (`guard-git.sh` blocks it)

When done:

```console
~/Projects/my-project $ bash .claude/scripts/pipeline-advance.sh builder
Pipeline: builder završen. [2026-04-06 10:04:12] (spec→builder: 4m 12s)
  [DONE] spec
  [DONE] builder   2026-04-06 10:04:12
  [----] reviewer ← NEXT
  [----] verifier
```

### 4.3 Run the reviewer

```console
> dispatch code-reviewer to review the builder's changes
```

The reviewer looks for bugs, edge cases, and security issues. It does not suggest style changes.

If the reviewer finds issues, the builder fixes them. Then:

```console
~/Projects/my-project $ bash .claude/scripts/pipeline-advance.sh reviewer
Pipeline: reviewer završen. [2026-04-06 10:07:45] (builder→reviewer: 3m 33s)
```

### 4.4 Run the verifier

```console
~/Projects/my-project $ bash .claude/scripts/pipeline-advance.sh verifier
Pipeline: verifier završen. COMMIT DOZVOLJEN. [2026-04-06 10:09:20]
  (reviewer→verifier: 1m 35s | ukupno: 9m 20s)
```

### 4.5 Commit

```console
~/Projects/my-project $ git add src/Auth/LoginHandler.cs tests/Auth/LoginTests.cs
~/Projects/my-project $ APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: add user login endpoint"
Pipeline + Verifikacija prošli — commit dozvoljen.
[main abc1234] feat: add user login endpoint
 2 files changed, 85 insertions(+)
Pipeline resetovan posle uspešnog commita.
```

The commit will:
1. Check that all 4 pipeline steps are complete (`pipeline-gate.sh`)
2. Run build + test verification (`verify-all.sh`)
3. If everything passes — commit succeeds
4. Pipeline resets automatically (`pipeline-post-commit.sh`)
5. Session log entry is auto-generated with summary

You are now ready for the next task.

---

## What happens if you skip a step?

```console
~/Projects/my-project $ APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: something"
⛔ BLOKIRANO: Pipeline koraci nisu završeni!

  Pipeline: Spec → Builder → Reviewer → Verifier → Commit

  [DONE] spec
  [DONE] builder
  [----] reviewer ← MISSING
  [----] verifier ← MISSING
```

The commit is blocked. Complete the missing steps first.

## What happens if an agent misbehaves?

```console
# Agent tries to commit:
builder-agent $ git commit -m "feat: I'll just commit directly"
⛔ BLOCKED: Commit without APD_ORCHESTRATOR_COMMIT=1 prefix.

# Agent writes outside its scope:
builder-agent $ Write → apps/frontend/App.tsx
⛔ BLOCKED: File apps/frontend/App.tsx is outside allowed scope.
   Allowed paths: src/ tests/

# Agent tries to read secrets:
builder-agent $ Read → .env.production
⛔ BLOCKED: Access to sensitive files not permitted.

# Agent tries mass staging:
builder-agent $ git add .
⛔ BLOCKED: Mass staging not allowed. Add files explicitly.
```

All blocks are logged to `guard-audit.log` with agent ID and timestamp.

---

## Quick reference

| Command | What it does |
|---------|-------------|
| `pipeline-advance.sh spec "Task"` | Start a new task |
| `pipeline-advance.sh builder` | Mark builder step complete |
| `pipeline-advance.sh reviewer` | Mark reviewer step complete |
| `pipeline-advance.sh verifier` | Mark verifier step complete |
| `pipeline-advance.sh status` | Show current pipeline state |
| `pipeline-advance.sh rollback` | Undo the last step |
| `pipeline-advance.sh metrics` | Show pipeline performance dashboard |
| `pipeline-advance.sh skip "Reason"` | Emergency hotfix bypass (logged) |
| `verify-apd.sh` | Full setup verification (51 checks) |
| `verify-contracts.sh be/ fe/` | Cross-layer type check |

---

## Next steps

- Read the full [README](README.md) for architecture details, CQRS patterns, and integration guides
- Explore the [example project](examples/nodejs-react/) to see a fully configured setup
- Try the [interactive demo](https://zstevovich.github.io/claude-apd/demo/)
