# {{PROJECT_NAME}}

This project uses the **APD framework** (Agent Pipeline Development) for
disciplined, test-driven work on Codex. Read this file at the start of every
session — it defines the enforced workflow you must follow.

## Pipeline model

Every change moves through four gates:

  **spec → builder → reviewer → verifier → commit**

Do not skip a gate. Each gate is enforced by the APD MCP server through
these tools:

| Tool | Purpose |
|------|---------|
| `apd_ping` | Health check — verify APD is wired before using other tools |
| `apd_doctor` | Pipeline diagnostics — run before and after large steps |
| `apd_advance_pipeline(step, arg?)` | Move the pipeline forward one gate |
| `apd_guard_write(role, file_path)` | MUST call before every file write — scope is read server-side from `.apd/agents/<role>.md`; exit 2 = BLOCK |
| `apd_verify_step()` | Run project `.codex/bin/verify-all.sh` (or framework fallback) |
| `apd_adversarial_pass(total, accepted, dismissed)` | Record adversarial review outcome |
| `apd_list_agents()` | List every agent definition in `.apd/agents/` with scope, model, maxTurns — call once to discover which roles exist; scope is enforced by `apd_guard_write` itself, not by re-sending it |
| `apd_pipeline_state()` | Structured snapshot of the current pipeline: which `.done` files exist, spec-card criteria count + freeze hash, implementation-plan presence, adversarial summary, reviewed-files count, verifier cache age, and the next step to advance |

## Order of operations for a task

1. **Write the spec card** at `.apd/pipeline/spec-card.md`. Each requirement
   must be on its own line in the `Acceptance criteria` section as
   `- R1: <short>`, `- R2: ...`. Maximum 7 `R*:` items per task — decompose
   larger work into multiple pipeline cycles.
2. **Advance the spec gate:** `apd_advance_pipeline("spec", "<task-name>")`.
3. **Write the implementation plan** at
   `.apd/pipeline/implementation-plan.md` — a bulleted list of files you
   will touch with one-sentence reasons. This is required before builder.
4. **Implement.** On Codex the orchestrator IS the builder — there is no
   sub-agent dispatch. Before every write, call
   `apd_guard_write("<role>", "<file_path>")`. The server reads scope from
   `.apd/agents/<role>.md` frontmatter; you cannot widen it from the call.
5. **Advance the builder gate:** `apd_advance_pipeline("builder")`.
6. **Review the diff inline.** Walk the diff like a hostile reviewer.
   Advance: `apd_advance_pipeline("reviewer")`.
7. **Verify:** `apd_advance_pipeline("verifier")`. This runs
   `apd_verify_step()` internally, which blocks on build or test failure.
8. **Adversarial pass (optional but recommended):** consider regressions,
   concurrency, edge cases, contract drift. Record the outcome with
   `apd_adversarial_pass(total, accepted, dismissed)`.
9. **Commit** with a short, imperative-mood message in the repo's style.

## Rules and memory

### Workflow rules (always-on)

- **`.apd/rules/workflow.md`** — authoritative workflow rules. Read before
  starting any task. If a rule conflicts with this file, `workflow.md` wins.

### Phase-specific rules (read when entering each phase)

On Codex the orchestrator plays every role, so it must pull in the rule
file for the phase it is in:

| Phase trigger | Read this |
|---------------|-----------|
| Task is vague, broad, or "improve X" style — before writing the spec card | **`.apd/rules/brainstorm.md`** |
| About to implement or fix code — builder phase | **`.apd/rules/tdd.md`** |
| Test failure, build failure, verifier block, critical review finding | **`.apd/rules/debug.md`** |
| Pipeline cycle complete — before push/PR/keep decision | **`.apd/rules/finish.md`** |

Load the matching file once per phase; keep its constraints in mind
throughout that phase.

### Memory (living context)

- **`.apd/memory/MEMORY.md`** — index of cross-session learnings, references,
  anti-patterns. Consult before proposing an approach.
- **`.apd/memory/status.md`** — current in-progress work.
- **`.apd/memory/session-log.md`** — append-only log. Fill in the previous
  entry before starting the next task.

## Agent scope

Even though Codex has no sub-agent dispatch, APD's agent definitions in
`.apd/agents/` define the **scope each role may write to**. When you act as
a builder, your writes must stay inside the scope declared for the matching
role. When you act as a reviewer or adversarial-reviewer, do not write at
all — those roles are read-only.

Scope lives in the YAML frontmatter:

```yaml
scope:
  - src/
  - config/
```

`apd_guard_write(role, file_path)` reads that frontmatter itself on every
call — pass only the role name and the target path. Use `apd_list_agents()`
to discover which roles are defined; the scope list is informational, not a
parameter you forward. A role with `readonly: true` blocks every write
regardless of scope.

## Project context

<!-- Replace this block with stack, entry points, test commands, conventions. -->

- **Stack:** <fill in>
- **Entry points:** <fill in>
- **Run tests:** <fill in>
- **Conventions:** <fill in>
