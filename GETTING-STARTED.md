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
> bash .claude/bin/apd verify
```

> **Expected result:** All checks pass across 10 categories (prerequisites, structure, hooks, placeholders, CLAUDE.md, agents, guards, pipeline E2E, verify-all.sh, gitignore). The verification runs 50+ checks — the exact number depends on your agent count.

If you see any FAIL items, follow the instructions in the output to fix them.

---

## Step 5 — Your first pipeline task

### 5.1 Write the spec card

Write `.claude/.pipeline/spec-card.md` with acceptance criteria using R* format:

```markdown
## Add user login endpoint
**Goal:** POST /api/auth/login accepting email + password, returning JWT.
**Effort:** high
**Out of scope:** Registration, password reset.
**Acceptance criteria:**
- R1: Returns 200 with JWT on valid credentials
- R2: Returns 401 on invalid credentials
- R3: Password compared via bcrypt
**Affected modules:** src/Auth/
**Risks:** None — new endpoint, no existing code affected.
**Rollback:** Delete the handler file.
**Human gate:** No — new endpoint, does not change existing API.
```

Share with the user. Wait for approval before proceeding. Then advance:

```console
> bash .claude/bin/apd pipeline spec "Add user login endpoint"

  APD ■ Spec: "Add user login endpoint"
  ■ spec → ■ builder → □ reviewer → □ verifier → commit

    Next steps:
    1. Write .pipeline/implementation-plan.md (files + changes + ### Agents section)
    2. Dispatch project builders: Agent({ subagent_type: "<agent-name>", ... })
    3. Dispatch project reviewer: Agent({ subagent_type: "code-reviewer", ... })
       NEVER use superpowers: or feature-dev: agents — pipeline will BLOCK
```

> **Max 7 acceptance criteria per spec.** Larger features must be decomposed into smaller pipeline cycles. The spec is frozen after this step — cannot be modified mid-pipeline.

### 5.2 Write the implementation plan

Write `.claude/.pipeline/implementation-plan.md`:

```markdown
## Implementation Plan: Add user login endpoint

### Agents
- backend-builder

### Files to create
- `src/Auth/LoginHandler.cs` — POST endpoint, validates credentials, returns JWT

### Files to modify
- `src/Auth/AuthModule.cs` — register the new endpoint

### Notes
- Use bcrypt for password comparison (existing UserService.VerifyPassword)
```

### 5.3 Dispatch a builder

```console
> dispatch backend-builder with the approved spec and plan
```

The builder agent will:
- Read the implementation plan and spec card
- Implement the code (max 3–4 edit operations)
- Add `@trace R1`, `@trace R2`, `@trace R3` markers in test files
- Stay within its allowed scope (`guard-scope` enforces this)
- Not commit anything (`guard-git` blocks it)

When done:

```console
> bash .claude/bin/apd pipeline builder

  APD ■ Builder Complete  +4m 12s
  ■ spec → ■ builder → ■ reviewer → □ verifier → commit
```

### 5.4 Run the reviewer

```console
> dispatch code-reviewer to review the builder's changes
```

The reviewer looks for bugs, edge cases, and security issues. It does not suggest style changes. If the reviewer finds issues, the builder fixes them. Then:

```console
> bash .claude/bin/apd pipeline reviewer

  APD ■ Reviewer Complete  +3m 33s
```

### 5.5 Run the verifier

```console
> bash .claude/bin/apd pipeline verifier

  APD ■ COMMIT ALLOWED  total: 9m 20s
  ■ spec → ■ builder → ■ reviewer → ■ verifier → commit
    Ready: APD_ORCHESTRATOR_COMMIT=1 git commit ...
```

### 5.6 Commit

```console
> git add src/Auth/LoginHandler.cs tests/Auth/LoginTests.cs
> APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: add user login endpoint"
```

The commit will:
1. Check that all 4 pipeline steps are complete (`pipeline-gate`)
2. Run build + test verification (`verify-all.sh`)
3. Check spec traceability — all R* criteria have @trace markers in tests
4. If everything passes — commit succeeds
5. Pipeline resets automatically, session log entry generated

You are now ready for the next task.

---

## What happens if you skip a step?

```
> APD_ORCHESTRATOR_COMMIT=1 git commit -m "feat: something"

BLOCKED: Pipeline steps not completed!
  [DONE] spec
  [DONE] builder
  [----] reviewer ← MISSING
  [----] verifier ← MISSING
```

The commit is blocked. Complete the missing steps first.

## What happens if an agent misbehaves?

```
# Agent tries to commit:
BLOCKED: git commit is only allowed with APD_ORCHESTRATOR_COMMIT=1 prefix.

# Agent writes outside its scope:
BLOCKED: File apps/frontend/App.tsx is outside allowed scope.
   Allowed paths: src/ tests/

# Agent tries to read secrets:
BLOCKED: Access to sensitive files not permitted.

# Orchestrator writes directly to .pipeline/:
BLOCKED: Bash write to protected pipeline state directory.
   Do not write directly to .pipeline/ — use pipeline-advance instead.
```

All blocks are logged to `guard-audit.log` with agent ID and timestamp.

---

## Diagnostics

```console
> bash .claude/bin/apd doctor
```

Shows: pipeline state, spec card validation, spec freeze hash, implementation plan, agent registry, guard coverage, trace coverage, adversarial review, GitHub sync, plugin version. Identifies problems with fix instructions.

---

## Quick reference

| Command | What it does |
|---------|-------------|
| `apd pipeline spec "Task"` | Start a new task (requires spec-card.md) |
| `apd pipeline builder` | Mark builder step complete (requires implementation-plan.md) |
| `apd pipeline reviewer` | Mark reviewer step complete |
| `apd pipeline verifier` | Mark verifier step complete |
| `apd pipeline status` | Show current pipeline state |
| `apd pipeline rollback` | Undo the last step |
| `apd pipeline metrics` | Show pipeline performance dashboard |
| `apd doctor` | Full pipeline diagnostics |
| `apd verify` | Full setup verification (50+ checks) |
| `apd trace` | Check spec traceability coverage |
| `apd init` | Initialize or update APD in a project |

All commands: `bash .claude/bin/apd <command>`

---

## Next steps

- Read the full [README](README.md) for architecture details and integration guides
- Explore the [example project](examples/nodejs-react/) to see a fully configured setup
- Try the [interactive demo](https://zstevovich.github.io/claude-apd/demo/)
