# Getting Started with APD

From zero to your first pipeline commit in 5 minutes.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) **v2.1.89+** recommended (v2.1.32+ minimum)
- `jq` installed (`brew install jq` on macOS, `apt install jq` on Linux)
- A git repository with some code in it

> APD checks your Claude Code version automatically on session start. If it is below the recommended version, you will see a warning with instructions to update.

---

## Step 1 — Add the marketplace (one time)

```console
> /plugin marketplace add zstevovich/claude-apd
```

## Step 2 — Install for your project

Open Claude Code **in your project directory** and install at project scope:

```console
~/Projects/my-project $ claude
> /plugin install claude-apd@zstevovich-plugins
```

Select **"Install for all collaborators on this repository (project scope)"**. This ensures hooks only fire in this project and teammates get the plugin automatically.

## Step 3 — Initialise

Start a new session, then run:

```console
~/Projects/my-project $ claude
> /apd-setup
```

> **Note:** Start a new session after installing — skills register on session start.

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

## Step 4 — Verify the setup

```console
~/Projects/my-project $ bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify-apd.sh
```

> **Expected result:** All checks pass across 10 categories (prerequisites, structure, hooks, placeholders, CLAUDE.md, agents, guards, pipeline E2E, verify-all.sh, gitignore). The verification runs 50+ checks — the exact number depends on your agent count.

If you see any FAIL items, follow the instructions in the output to fix them.

---

## Step 5 — Your first pipeline task

### 4.1 Create a spec

```console
~/Projects/my-project $ bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh spec "Add user login endpoint"
Pipeline started: Add user login endpoint [2026-04-06 10:00:00]
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
~/Projects/my-project $ bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh builder
Pipeline: builder completed. [2026-04-06 10:04:12] (spec→builder: 4m 12s)
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
~/Projects/my-project $ bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh reviewer
Pipeline: reviewer completed. [2026-04-06 10:07:45] (builder→reviewer: 3m 33s)
```

### 4.4 Run the verifier

```console
~/Projects/my-project $ bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh verifier
Pipeline: verifier completed. COMMIT ALLOWED. [2026-04-06 10:09:20]
  (reviewer→verifier: 1m 35s | total: 9m 20s)
```

### 4.5 Commit

```console
~/Projects/my-project $ git add src/Auth/LoginHandler.cs tests/Auth/LoginTests.cs
~/Projects/my-project $ APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: add user login endpoint"
Pipeline + Verification passed — commit allowed.
[main abc1234] feat: add user login endpoint
 2 files changed, 85 insertions(+)
Pipeline reset after successful commit.
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
⛔ BLOCKED: Pipeline steps not completed!

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
| `pipeline-advance.sh init "Description"` | First setup only |
| `verify-apd.sh` | Full setup verification (51 checks) |
| `verify-contracts.sh be/ fe/` | Cross-layer type check |

---

## Next steps

- Read the full [README](README.md) for architecture details, CQRS patterns, and integration guides
- Explore the [example project](examples/nodejs-react/) to see a fully configured setup
- Try the [interactive demo](https://zstevovich.github.io/claude-apd/demo/)
