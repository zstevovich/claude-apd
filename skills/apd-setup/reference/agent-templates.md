# apd-setup — Agent generation reference

Detailed specs for agents that `apd-setup` generates. Loaded on demand by SKILL.md.

## Auto-detect agents from project structure

Read the layout with `ls -d */` and suggest agents based on directory names. Show the suggestion to the user — they approve or adjust before generation.

| Detected directory | Suggested agent | Scope |
|---|---|---|
| `src/` or `server/` or `backend/` or `api/` | `backend-builder` | detected dir |
| `client/` or `frontend/` or `web/` or `apps/frontend/` | `frontend-builder` | detected dir |
| `mobile/` or `apps/mobile/` | `mobile-builder` | detected dir |
| `tests/` or `__tests__/` or `test/` or `src/test/` | `testing` | detected dir |
| `docker/` or `.github/` or `deploy/` or `infra/` | `devops` | detected dirs |
| `src/Commands/` + `src/Queries/` | CQRS agents (one per responsibility) | by responsibility |

Confirm the stack (`package.json`, `pom.xml`, `Cargo.toml`, etc.) before suggesting — directory names alone are not enough. A `src/` folder in a Java project is not the same as `src/` in a Node project.

## Builder agents

Generated from `${CLAUDE_PLUGIN_ROOT}/plugins/apd/templates/agent-template.md`. One per detected domain.

**Frontmatter:**

| Field | Value |
|---|---|
| `name` | `<domain>-builder` (e.g. `backend-builder`) |
| `description` | One-line role summary |
| `tools` | `Read, Write, Edit, Glob, Grep, Bash` |
| `model` | `claude-sonnet-5` — **full id, never the bare alias `sonnet`** |
| `effort` | `xhigh` |
| `permissionMode` | `bypassPermissions` |
| `color` | `purple` (backend), `blue` (frontend), `green` (testing), `cyan` (other) |

**Hooks:** all paths use the `${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/adapter/cc/` prefix (the CC shims — `bin/core/` holds the runtime-neutral implementations those shims call). The builder MUST register `guard-scope` (file scope enforcement) and `guard-bash-scope` (Bash scope enforcement) with the exact same SCOPE_PATHS list — never a superset.

> **The hook block is DATA, not execution.** Per-agent frontmatter `hooks:` never fire (measured on CC 2.1.220), so enforcement runs session-level from `hooks/hooks.json`. But `bin/lib/agent-scope.sh` resolves each agent's writable scope by reading the `guard-scope` hook command out of this very file when no YAML `scope:` key is present. So the block must still be written, and its SCOPE_PATHS must be exactly right — it is the registry the guard consults, not a formality.

**Body:** role description, stack notes, workflow reference, FORBIDDEN section listing what the builder must NOT do (commit, push, edit out-of-scope files, run destructive commands).

## Reviewer agent

ALWAYS generated, regardless of stack. Generated from `${CLAUDE_PLUGIN_ROOT}/plugins/apd/templates/reviewer-template.md`.

**Frontmatter:**

| Field | Value |
|---|---|
| `name` | `code-reviewer` |
| `tools` | `Read, Glob, Grep, Bash` — **no Write or Edit** |
| `model` | `claude-opus-5` — **full id, never the bare alias `opus`** |
| `effort` | `max` |
| `permissionMode` | `plan` (read-only) |
| `color` | `orange` |

**Hooks:** registers `guard-secrets` and `guard-git` only. **Never** registers `guard-scope` — the reviewer needs to read the entire repo, not just the builder's scope.

**Body:** review checklist, output format (CRITICAL / IMPORTANT / SUGGESTIONS), final verdict (PASS / FAIL).

The reviewer is mandatory because finding bugs requires deeper reasoning than writing code — opus/max is the right tool, not a cost shortcut.

## Generation rule

GENERATE agents from the templates with placeholder substitution — do not copy template files literally. Every `{{PLACEHOLDER}}` must be filled before the file is written.
