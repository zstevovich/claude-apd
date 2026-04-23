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
| `apd_guard_write(apd_role, file_path)` | MUST call before every file write — scope is read server-side from `.apd/agents/<apd_role>.md`; exit 2 = BLOCK. The argument is `apd_role` not `role` to dodge Codex's multi_agent role-mismatch approval prompt |
| `apd_verify_step(scope="full")` | Run project `.codex/bin/verify-all.sh` (or framework fallback). `scope="fast"` exposes `APD_VERIFY_SCOPE=fast` to the verifier so a customised verify-all.sh can run build + targeted tests only — use during builder REFACTOR iteration. Default `"full"` runs the complete suite and is what the pre-commit gate uses |
| `apd_adversarial_pass(total, accepted, dismissed, notes="")` | Record adversarial review outcome — `notes` is REQUIRED when `total=0` (>= 80 chars) so the server can tell a real "0 findings" pass from a rubber-stamp |
| `apd_list_agents()` | List every agent definition in `.apd/agents/` with scope, model, maxTurns — call once to discover which roles exist; scope is enforced by `apd_guard_write` itself, not by re-sending it |
| `apd_pipeline_state()` | Structured snapshot of the current pipeline: which `.done` files exist, spec-card criteria count + freeze hash, implementation-plan presence, adversarial summary, reviewed-files count, verifier cache age, the next step to advance, and a `budgets` field (spec criteria, reviewed files, verifier duration) with advisory green/yellow/red status to inform the Lean vs Full choice |

## Recon (before the spec card)

Before writing the spec card you need enough context to draft precise
acceptance criteria. Recon is the single biggest source of wasted context
on Codex — the orchestrator is prone to opening files it does not need.
Be sharp here and every downstream gate is cheaper.

Order:

1. **Structural tools first.** Call `apd_list_agents()` to see which roles
   and scopes exist, and `apd_pipeline_state()` for the current pipeline
   snapshot. These are cheap and give the shape of the work before any
   file read.
2. **Grep over Read.** Use `grep`/`rg` to locate the relevant symbol,
   function, or config. Only `Read` a full file when you must understand
   a specific function in its surrounding context.
3. **Stay in the green zone: ≤ 7 file reads before the spec card.** If
   you are about to open an 8th file, stop and ask whether the task is
   too broad for one pipeline cycle — decompose it instead. Genuine
   exceptions (unfamiliar codebase, truly cross-cutting change) exist
   but should be rare.

## Lean vs Full pipeline

Not every task needs every gate. Choose the mode at spec time:

- **Full** (default): spec → builder → reviewer → adversarial → verifier
  → commit. Use whenever the work touches a migration, auth or session
  handling, a public API or wire protocol, a security-sensitive path, or
  a cross-module refactor.
- **Lean**: spec → builder → reviewer → verifier → commit. Skip
  adversarial for genuinely small, contained work — a trivial feature or
  bugfix of fewer than 5 files that does NOT fall into any Full category
  above.

Default to Full. Pick Lean only when ALL of these are true: single narrow
change, no migration, no auth, no public-API change, no security
surface, no cross-module refactor. When in doubt, pick Full — adversarial
is cheap insurance against the regressions it catches.

### Opting into Lean

Add this line anywhere in `.apd/pipeline/spec-card.md`:

```
adversarial: skip — <one-sentence reason>
```

The reviewer gate then advances straight to verifier without setting the
adversarial-pending flag. **Mechanical cap: the opt-out is only honored
when the spec has ≤ 2 `R*:` criteria.** A 3+ criterion spec is
substantial enough that the adversarial gate stays on regardless — the
`adversarial: skip` line is ignored in that case.

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
   `apd_guard_write(apd_role="<role-name>", file_path="<path>")`. The server
   reads scope from `.apd/agents/<role-name>.md` frontmatter; you cannot
   widen it from the call.
5. **Advance the builder gate:** `apd_advance_pipeline("builder")`.
6. **Review the diff inline.** Walk the diff like a hostile reviewer.
   Advance: `apd_advance_pipeline("reviewer")`.
7. **Adversarial pass (Full mode only):** consider regressions,
   concurrency, edge cases, contract drift, security surface. Record the
   outcome with `apd_adversarial_pass(total, accepted, dismissed, notes)`.
   If you genuinely find nothing (`total=0`), `notes` becomes mandatory
   (>= 80 chars) — write what categories you actually examined and why
   they came up clean. The server rejects empty 0/0/0 records. In Lean
   mode, skip this step — the reviewer gate does not set the
   adversarial-pending flag when `adversarial: skip` is accepted.
8. **Verify:** `apd_advance_pipeline("verifier")`. This runs
   `apd_verify_step()` internally (always with `scope="full"`), which
   blocks on build or test failure. In Full mode, it also blocks when
   step 7 was not recorded. For quick checks during a builder REFACTOR
   cycle — before you're ready to advance the gate — call
   `apd_verify_step(scope="fast")` directly.
9. **Commit** with a short, imperative-mood message in the repo's style.

## Rules and memory

> **Hybrid vs pure-Codex layout.** On a hybrid project (`.claude/` AND
> `.codex/` present) the **CC-native paths under `.claude/` are
> authoritative** for workflow rules and memory — APD doesn't duplicate
> them. On a pure-Codex project (`.codex/` only) the same content lives
> under `.apd/`. The phase rules below are Codex-native either way and
> always live under `.apd/rules/` because CC reads them as slash-skills
> instead of inline files.
>
> Resolution rule: if a path under `.claude/...` exists, prefer it.
> Otherwise fall back to the matching `.apd/...` path.

### Workflow rules (always-on)

- **`.claude/rules/workflow.md`** (hybrid) **or** **`.apd/rules/workflow.md`**
  (pure-Codex) — authoritative workflow rules. Read before starting any
  task. If any rule conflicts with this file, `workflow.md` wins.

### Phase-specific rules (read when entering each phase)

On Codex the orchestrator plays every role, so it must pull in the rule
file for the phase it is in. These always live under `.apd/rules/`:

| Phase trigger | Read this |
|---------------|-----------|
| Task is vague, broad, or "improve X" style — before writing the spec card | **`.apd/rules/brainstorm.md`** |
| About to implement or fix code — builder phase | **`.apd/rules/tdd.md`** |
| Test failure, build failure, verifier block, critical review finding | **`.apd/rules/debug.md`** |
| Pipeline cycle complete — before push/PR/keep decision | **`.apd/rules/finish.md`** |

Load the matching file once per phase; keep its constraints in mind
throughout that phase.

### Memory (living context)

Same hybrid resolution as workflow rules — prefer `.claude/memory/` when
it exists, otherwise `.apd/memory/`:

- **`MEMORY.md`** — index of cross-session learnings, references,
  anti-patterns. Consult before proposing an approach.
- **`status.md`** — current in-progress work.
- **`session-log.md`** — append-only log. Fill in the previous entry
  before starting the next task.

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

`apd_guard_write(apd_role, file_path)` reads that frontmatter itself on
every call — pass only the role name and the target path. Use
`apd_list_agents()` to discover which roles are defined; the scope list
is informational, not a parameter you forward. A role with
`readonly: true` blocks every write
regardless of scope.

## Project context

<!-- Replace this block with stack, entry points, test commands, conventions. -->

- **Stack:** <fill in>
- **Entry points:** <fill in>
- **Run tests:** <fill in>
- **Conventions:** <fill in>
