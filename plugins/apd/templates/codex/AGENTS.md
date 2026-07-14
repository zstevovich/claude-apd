# {{PROJECT_NAME}}

This project uses the **APD framework** (Agent Pipeline Development) for
disciplined, test-driven work on Codex. Read this file at the start of every
session — it defines the enforced workflow you must follow.

## Stack

| Area | Project value | Notes |
|------|---------------|-------|
| Stack | Project-specific | Fill during project setup with languages, frameworks, and package managers. |
| Entry points | Project-specific | Name the app, CLI, worker, or service entry points. |
| Test command | Project-specific | Name the fastest useful test command and the full verifier. |
| Conventions | Project-specific | Name formatting, architecture, and review conventions. |

## APD

Codex is the APD orchestrator for this project. It owns the pipeline state,
calls the APD MCP tools, performs the inline builder/reviewer work unless the
user explicitly asks for subagents, and never bypasses the mechanical gates.

### Communication discipline

Lines the orchestrator writes between tool calls reach the user.

- No end-of-turn lessons-learned recaps, no "what I did + next steps" multi-bullets, no self-narration of intent ("I'll now do X" — just do X).
- One-sentence end-of-turn maximum: what changed and the next step. Nothing more.
- If you have a lesson worth keeping, write it to memory; do not narrate it.

### Pipeline

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
| `apd_adversarial_pass(total, accepted, dismissed, notes="")` | Record adversarial review outcome — `notes` is REQUIRED when `total=0` (>= 80 chars) so the server can tell a real "0 findings" pass from a rubber-stamp. When `total>0`, you MUST also write `.apd/pipeline/.adversarial-rationale.md` with one block per finding (Severity / Status / Rationale fields) — the verifier hard-blocks otherwise (v6.7 rationale gate). Treat reviewer-self-dismissed entries as `**Status:** reviewer-self-dismissed` to avoid false-triggering the 100%-orchestrator-dismiss gate (T≥3 && A==0 && Do≥1) |
| `apd_list_agents()` | List every agent definition in `.apd/agents/` with scope, model, maxTurns — call once to discover which roles exist; scope is enforced by `apd_guard_write` itself, not by re-sending it |
| `apd_pipeline_state()` | Structured snapshot of the current pipeline: which `.done` files exist, spec-card criteria count + freeze hash, implementation-plan presence, adversarial summary, reviewed-files count, verifier cache age, the next step to advance, and a `budgets` field (spec criteria, reviewed files, verifier duration) with advisory green/yellow/red status to inform the Lean vs Full choice |

### Guardrails

- `apd_advance_pipeline` is the only supported way to sign APD gate files.
- `apd_guard_write` must clear every implementation file before editing it.
- `spec-card.md` is frozen after the spec gate; scope changes require rollback.
- Reviewer and adversarial phases are read-only unless the task loops back to builder.
- The verifier gate must run full verification before commit.
- To inspect pipeline state use `apd pipeline status` / `apd pipeline show [spec|plan|state]` — do NOT `cat`/`ls` files under `.apd/pipeline/` (guard-bash-scope blocks bash access to protected state; it cannot tell a read from a fabrication attempt).
- After `apd_adversarial_pass` with `total > 0`, write `.apd/pipeline/.adversarial-rationale.md` BEFORE running `apd_advance_pipeline("verifier")`. Format: `## Finding N — <title>` + `**Severity:** critical|important|minor` + `**Status:** accepted|dismissed|reviewer-self-dismissed` + `**Rationale:** <text ≥40 chars for dismissed/self-dismissed>`. Verifier hard-blocks on missing file, count mismatch, malformed fields, or the 100%-orchestrator-dismiss pattern.
- Three finding dispositions: **accept** (real + in scope) / **dismiss** (not real) / **spinoff** (real BUT out of THIS task's declared scope — often the ones surfacing AT the cycle cap). Do NOT expand the task and do NOT disable APD to cram an out-of-scope fix in; record a follow-up task seed and continue in scope: `apd pipeline spinoff-finding <id> "<why out of scope + the follow-up>"` (backlog: `apd pipeline show deferred`). In `.adversarial-rationale.md` a spun-off finding is still `**Status:** accepted` (it's real — counts in `A`); `spinoff-finding` is the deferral record, NOT a rationale status (the gate only knows accepted/dismissed/reviewer-self-dismissed). The spinoff becomes its own APD task next (spec + fresh adversarial + red-green). When you ask the user what to do about an out-of-scope finding at the cap, list spinoff FIRST and recommend it.

### Mandatory skills

| Situation | Read/use |
|-----------|----------|
| EVERY new task, before spec-card.md — unconditional, no skip | `apd-pipeline-guide` |
| Vague, broad, or multi-option task — before the guide | `apd-brainstorm` and `.apd/rules/brainstorm.md` |
| Implementing or fixing code | `apd-tdd` and `.apd/rules/tdd.md` |
| Test failure, build failure, verifier block, or critical review finding | `apd-debug` and `.apd/rules/debug.md` |
| Pipeline complete and commit made | `apd-finish` and `.apd/rules/finish.md` |

### Human gate

Ask before broadening scope, skipping adversarial outside the Lean rules,
pushing to a remote, opening a PR, or discarding work. Destructive git actions
require explicit user confirmation.

## Platform portability (macOS/BSD vs Linux)

You are most likely on **macOS (Darwin, BSD userland)**, NOT Linux. GNU/Linux-isms fail here — often **silently** (a backgrounded `timeout` that never starts). `guard-bash-portability` hard-blocks the worst on macOS. Run `apd env` for the full table. Key swaps: `timeout`→`gtimeout` (or bg+kill), `tac`→`tail -r`, `nproc`→`sysctl -n hw.ncpu`, `date -d`→`date -v`/`date -j -f`, `stat -c`→`stat -f`, `grep -P`→`grep -E`, `readlink -f`→`realpath`, `sed -i 's/…'`→`sed -i '' 's/…'`.

**Never pipe the build/verifier through `head`/`tail`** — the pipe's exit code is the tail's, not the command's (a failure reads as success). Capture to a file and read it; use `set -o pipefail`. When something looks stuck, poll the pipeline's own signal (`.done` files / `apd pipeline status`), do not eyeball hidden output and re-run blindly.

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

0. **MANDATORY load `apd-pipeline-guide` skill BEFORE writing spec-card.md.**
   Unconditional, every new task, NO skip argument (v6.15). The guide is the
   APD operating manual: gate at each advance, plan **Implements:** header
   contract, adversarial rationale .md contract, common BLOCKs + recovery,
   `apd pipeline show` read path. It writes `.apd/pipeline/.guide-marker`;
   `apd_advance_pipeline('spec', ...)` hard-BLOCKS without it. "The task is
   already clear" is NOT a reason to skip — the guide is not a brainstorm,
   it is the contract.

   **If the task scope is vague** (broad, "improve X", multiple reasonable
   interpretations) → load `apd-brainstorm` FIRST: interactive one-question-
   at-a-time clarification converging on a user-approved design. Optional when
   scope is already aligned (1:1 mirror, fully specified task, approved
   informal design) — skipping brainstorm never skips the guide.

1. **Write the spec card** at `.apd/pipeline/spec-card.md`. Each requirement
   must be on its own line in the `Acceptance criteria` section as
   `- R1: <short>`, `- R2: ...`. Maximum 7 `R*:` items per task — decompose
   larger work into multiple pipeline cycles.
   **DO NOT write `adversarial: max_defects=...`** — field is DEPRECATED as
   of v6.9, will be removed in v7.0. Continues to function in v6.9 (verifier
   gate + immutability check) but emits a deprecation warn on every spec
   advance. Rationale gate (v6.7) structurally covers the misuse pattern.
   **Declare a `**Regression surface:**`** — what the task touches INDIRECTLY
   (shared modules) that must not regress, each `- RS<N>:` with a `**Cover:**`
   value, or `none — <reason>` if self-contained. On a Human-gate path each RS
   item also needs `**Evidence:**` (≥40 chars). `verify-regression-surface`
   checks this in the builder advance (mode `regression_gate:`, default warn).
2. **Advance the spec gate:** `apd_advance_pipeline("spec", "<task-name>")`.
3. **Write the implementation plan** at
   `.apd/pipeline/implementation-plan.md` — a bulleted list of files you
   will touch with one-sentence reasons. This is required before builder.
   **MANDATORY** — every `### Section` MUST start with `**Implements:** R1, R3`
   (or `**Implements:** none` for scaffolding sections — file lists, agents,
   notes). Write headers FROM THE START — `verify-plan-spec` strict mode
   (v6.8.1+ default) hard-BLOCKS `apd_advance_pipeline("builder")` otherwise.
   Override via `plan_consistency_gate: strict|warn|off` in spec-card.md.
4. **Implement.** By default the Codex orchestrator acts as the builder.
   Use Codex subagents only when the user explicitly asks for delegated work,
   and keep APD scope enforcement on every file they touch. Before every write, call
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
10. **Reset before the next task:** `apd_advance_pipeline("reset")` —
    archives metrics + agent history, writes session-log summary
    (defaults "New rule" to "None"; pass a learning string as 2nd arg
    to capture a real one, e.g.
    `apd_advance_pipeline("reset", "always run composer dump-autoload after model changes")`),
    clears pipeline artifacts. Skipping the call causes telemetry loss
    and stale spec-card state.

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
