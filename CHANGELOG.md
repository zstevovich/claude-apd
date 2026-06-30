# Changelog

## v6.28.1 — 2026-07-01

**eco/cruise Sonnet slots pinned to Claude Sonnet 5.** Anthropic released Claude Sonnet 5 (`claude-sonnet-5`) — same standard price as Sonnet 4.6 ($3/$15 per MTok; introductory $2/$10 through Aug 31 2026), a newer knowledge cutoff (Jan 2026 vs Aug 2025), 1M context / 128k output, adaptive thinking, no breaking API changes. A clean drop-in for the Sonnet-tier profile slots.

`model-profiles.conf` previously used the CC `sonnet` alias in those slots; the alias resolves at session time, so the served Sonnet generation was neither pinned nor recorded. This pins `claude-sonnet-5` explicitly in the three Sonnet slots — `cruise` adversarial, `eco` builder, `eco` adversarial — making the served model knowable per run (the same per-run model-attribution concern behind the `MODEL_PROFILE` audit entry). `eco` benefits most: its builder moves from Sonnet 4.6 to Sonnet 5 (smarter + fresher knowledge at the same or lower cost). The adversarial slot is risk-free — adversarial value is positional (fresh context over model tier), so a smarter Sonnet there is at worst neutral. `opus` / `fable` rows stay as aliases (only deliberately-chosen models are pinned).

### Implementation

- **data(model-profiles.conf):** `cruise|adversarial`, `eco|default`, `eco|adversarial` → `claude-sonnet-5` (effort levels unchanged: `max` / `xhigh`). Pure template-data change; no script, guard, or hook logic touched.

### Tests

- `test-codex-adapter` **787 / 0** (§83 asserts row presence, not literal model strings; live-apply tests use their own fixtures).

**Migration:** none. CC only. Re-apply with `apd profile eco` (or `cruise`) + reload. `effort: max`/`xhigh` acceptance on Sonnet 5 verifies on the first live `eco`/`cruise` dispatch (high confidence — Sonnet 4.6 supports both with the same effort parameter).

## v6.28.0 — 2026-06-29

**Hook-non-delivery: a clear recovery hint at the builder/reviewer gates.** When CC's SubagentStart/Stop hooks silently don't fire (background dispatch / harness), the `.agents` evidence ledger stays empty even though agents ran, and `apd pipeline builder` / `reviewer` would BLOCK with a confusing "no agent dispatched". The gate now detects the on-disk CC transcripts and, if any exist for the current task, BLOCKs with a clear hint pointing at the explicit recovery — run `apd pipeline reconstruct-agents`, then re-run.

It deliberately does **not** auto-apply the reconstruction. The CC transcript directory is orchestrator-writable (`guard-bash-scope` only protects `.apd/pipeline/`), so silently trusting transcripts inside a gate would be a fabrication-assist path — an adversarial orchestrator could forge a transcript with two `printf`s. So the detect runs in dry-run mode (counts, writes nothing) and recovery stays an explicit, visible operator step. The enforcement floor is unchanged: the gate still BLOCKs; nothing is auto-trusted.

(An auto-apply design was built first, then caught by the independent pre-commit audit — a reminder that enforcement-code changes need an independent reviewer.)

### Implementation

- **feat(pipeline-advance):** the shared `_reconstruct_from_transcripts` gains a dry-run / detect-only mode (`RA_DRY_RUN=1`); the builder and reviewer gates call it on an empty-`.agents` BLOCK and append a `reconstruct-agents` hint when transcripts exist. The subcommand and the gates share the one reconstruct path (single source of truth).
- **docs:** SPEC.md gate detect+hint note (with the transcript-writability caveat); workflow.md safety-net line.

### Tests

- **test(test-codex-adapter §93):** BLOCK + hint with no auto-apply and `.agents` left untouched; explicit `reconstruct-agents → builder` still recovers (escape hatch); no-transcript → BLOCK without a false hint. **787 / 0.**

**Migration:** none. CC only.

## v6.27.0 — 2026-06-28

**Agent-reload drift gate — now actually prevents the dispatch.** v6.26.0 placed the gate on the `SubagentStart` hook, which fires AFTER the subagent has already spawned: `exit 2` there only prints to stderr while the agent runs to completion. So the v6.26 gate was a *detector*, not a preventer — the first dispatch after a forgotten reload still ran the stale model. (Found on a live run, then confirmed against CC's hook docs: `SubagentStart` "shows stderr only" vs `PreToolUse` "blocks the tool call".)

v6.27 moves the gate to **`PreToolUse` on the `Agent` tool** — which is PRE-spawn, so `exit 2` genuinely blocks the dispatch before the subagent starts. Verified empirically before shipping: a `PreToolUse(Agent)` exit-2 hook stops the dispatch with no `SubagentStart`/`SubagentStop` ever firing (and the subagent-dispatch matcher is confirmed to be `Agent`).

Everything else is unchanged: `apd profile` still drops `.apd/.pending-reload`, `apd reload-done` and a `startup` session clear it, compaction leaves it, and `APD_SKIP_RELOAD_GATE=1` opts out.

### Implementation

- **feat(guard-agent-reload):** new `bin/core/guard-agent-reload` (the gate logic: `APD_ACTIVE` short-circuit → opt-out → marker → exit 2) + CC adapter shim `bin/adapter/cc/guard-agent-reload` (drains the PreToolUse payload, forwards to core).
- **feat(hooks.json):** new `PreToolUse` matcher `Agent` → `guard-agent-reload`.
- **fix(track-agent):** removed the (post-spawn) SubagentStart blocking gate; replaced it with a lightweight **canary** — it only WARNS (never blocks) and still records the start, firing solely if the pre-spawn guard ever fails to fire (e.g. a future CC build renaming the `Agent` matcher). A stale-run signal instead of silent zero-protection.
- **docs:** SPEC.md guard table + guard-detail row + profile/reload-done/state-file rows updated to `PreToolUse(Agent)`/`guard-agent-reload`, with the canary fallback noted.

### Tests

- **test(test-codex-adapter §92) rewritten:** the gate is exercised through the new guard + its shim (block exit 2, opt-out, `reload-done` clear, `--startup` clear, compaction leaves, dormant-no-config short-circuit) plus a canary test (SubagentStart with marker → warns, exit 0, still records the start). **775 → 782 PASS / 0 FAIL.**

**Migration:** zero action. Same trigger (a forgotten reload after `apd profile`), now blocked before the subagent runs instead of after. CC only.

## v6.26.0 — 2026-06-28

**Agent-reload drift gate.** When `apd profile` rewrites agent models mid-session, the running session keeps the OLD agents — CC caches agent definitions at session start, and the orchestrator can't run `/reload-plugins` itself (only you can). Until now a forgotten reload meant a silent stale-model run. Now APD blocks it loudly.

We confirmed empirically this session that **`/reload-plugins` does NOT fire the `SessionStart` hook**, so APD can't observe a reload — the design is marker-based:

- `apd profile <name>` drops a `.apd/.pending-reload` marker when it actually changes agents (with the changed agent names).
- The **SubagentStart guard hard-blocks every dispatch** while the marker stands, with an actionable message: run `/reload-plugins`, then `apd reload-done` — or restart (a fresh session clears the marker automatically). Override with `APD_SKIP_RELOAD_GATE=1`.
- Compaction-reinjection does NOT clear the marker (it doesn't reload agents); only a real cold start (`startup`) does.

So a profile switch that you forget to activate surfaces as a clear block at dispatch time, not as agents silently running the wrong model.

### Implementation

- **feat(pipeline-model-profile):** writes `.apd/.pending-reload` (outside `pipeline/`, survives `pipeline reset`) on `changed>0`; the final message now says the reload is yours to run and points at `apd reload-done`.
- **feat(track-agent):** SubagentStart drift-guard — blocks (exit 2) while the marker exists, runs before the start event is logged so a blocked dispatch leaves no record. `APD_ACTIVE=false` short-circuits first, so dormant/Codex paths are untouched.
- **feat(session-start):** clears the marker on the `--startup` invocation only (hooks.json now passes `--startup` on the `startup` matcher); the compaction-reinjection invocation leaves it.
- **feat(reload-done):** new `bin/core/reload-done` + dispatcher `reload-done|rd` + `apd help` line.
- **docs:** SPEC.md `reload-done` row, profile drift-guard note, `.pending-reload` state-file row, hooks `--startup` note; `apd-profile` skill (reload is the user's step; drift-guard explained; anti-patterns).

### Tests

- **test(test-codex-adapter §92) +10:** 3 static (reload-done + dispatcher, track-agent guard + opt-out, hooks `--startup` wiring) + 7 live (marker written with names; SubagentStart → BLOCK exit 2 with actionable message; opt-out env passes; `reload-done` clears + unblocks; `--startup` clears; no-arg session-start leaves it). **765 → 775 PASS / 0 FAIL.**

**Migration:** zero action. The gate only triggers after `apd profile` changes agents; it's the moment you'd have needed to reload anyway. CC only (profiles + SubagentStart are CC).

## v6.25.0 — 2026-06-28

Two additions to the role lifecycle, both advisory — never gates.

`apd sync-role` is the **middle** of the role lifecycle (`run-role` → work → **sync-role** → `merge-role`). Run from inside a producer worktree, it merges the integration branch (auto-detected develop → main → master, or `--from`) **into** the worktree's branch — `git merge`, not rebase — so divergence surfaces small and early, in the worktree where the domain context is, instead of one big conflict at merge time. Unlike `merge-role` (which never merges, that direction is irreversible) sync-role **runs** the merge: merging integration into a feature branch is reversible (`git merge --abort` on conflict, `git reset --hard` when clean). On conflict it **stops and leaves the merge in progress** — a conflict here is a *signal*, not a failure; it never auto-resolves or auto-aborts. The producer charter now tells the agent to run it periodically.

A **model-profile reminder** at `spec` advance: right after the Next-steps block, the pipeline prints the current profile and the eco/cruise/burn fit for the task. It's advice at the decision point (a passive line in CLAUDE.md gets skipped), and it **never blocks** — the profile is an economic judgment, not a safety floor; the floor (guards + quality gates) stays enforced regardless.

### Implementation

- **feat(sync-role):** new `plugins/apd/bin/core/sync-role` + dispatcher `sync-role|sr` + `apd help` line. Guards: not a git repo / invoked from the main checkout (must be in a worktree) / detached HEAD / dirty tree / no integration branch → exit 1; conflict → exit 2 (merge left in progress).
- **feat(run-role):** producer charter (`_role_charter`) recommends running `apd sync-role` periodically; operator charter unchanged.
- **feat(pipeline-advance):** advisory model-profile reminder emitted after a successful `spec` advance (reads `MODEL_PROFILE` from config; exit unchanged).
- **docs:** SPEC.md `sync-role` row + §6.5 lifecycle middle + profile row reminder note; `roles guide` step 5 (replaces the bare `git merge develop` tip); README + GETTING-STARTED "Parallel work".

### Tests

- **test(test-codex-adapter §91) +9:** sync-role — 4 static (executable, dispatcher wiring, merges-not-rebases + `--abort` recovery, producer-charter recommendation) + 5 live (already-up-to-date → exit 0; run from main → block; non-conflicting merge → pulled in; dirty → block; **conflict → exit 2 with the merge left in progress, MERGE_HEAD preserved**).
- **test(test-codex-adapter §32) +1:** spec advance emits the profile reminder **and still exits 0** (advisory, not a gate). **755 → 765 PASS / 0 FAIL.**

**Migration:** zero action. Both additions are advisory; nothing existing changes behavior. CC (worktrees + profiles are git/CC).

## v6.24.0 — 2026-06-27

`apd run-role` becomes a **role launcher with charter injection**. `run-role <role> --launch` now enters a Claude Code session *as* the role: it builds the role's charter — workspace + scope + boundary + profile — automatically from `roles.conf` and passes it to `claude --append-system-prompt`, so the session knows what it is and what it may touch without you typing a prompt. The role carries its own identity.

This also unifies producers and operators behind one launcher. Previously `run-role` hard-blocked operator roles (`worktree=no`). Now an operator (devops/debug/master) gets no worktree but **charter-launches in the main checkout** — the worktree is producer-only, but the charter is for every role. `run-role devops --launch` finally does what the name implies.

### Implementation

- **feat(run-role):** new `_role_charter()` builds the charter from the role's own `roles.conf` fields; `--launch` injects it via `claude --append-system-prompt` (producers also scrub `APD_PROJECT_DIR` + `CLAUDE_PLUGIN_ROOT` and `exec` in the worktree, R6).
- **feat(run-role):** operator roles are no longer blocked — the old E2 hard-block is now the operator branch (no worktree, charter-launch in the main checkout, exit 0). Without `--launch` it prints how to charter-launch.
- **docs:** SPEC.md `run-role` row + §6.5 charter-launch note; README "Parallel work" section; GETTING-STARTED command table + parallel-work note; `apd help`, `run-role --help`, `roles guide`, and the `apd roles` header refreshed (dropped the stale "read-only in this milestone — run-role is a later milestone" line).

### Tests

- **test(test-codex-adapter §88/§89) +3:** operator role → no worktree + charter-launch guidance (exit 0, was a hard block); 2 static (charter built from `roles.conf`, injected via `--append-system-prompt`); producer `--launch` now also asserts the injected charter names the role; new operator `--launch` live test (spawns in the main checkout, charter injected, no worktree created). **752 → 755 PASS / 0 FAIL.**

**Migration:** zero action. Additive — producer behaviour is unchanged (just carries its charter now), and operator `run-role` goes from a block to a working charter-launch. CC only (worktrees + `--launch` are git/CC; Codex unchanged).

## v6.23.0 — 2026-06-26

`apd roles guide` — an in-CLI, step-by-step walkthrough of the role workflow, so the team-of-orchestrators recipe is at your fingertips, not only in the README. It prints the lifecycle as numbered steps (roles list → run-role → work in the isolated worktree → optional sync → merge-role gate → you merge → cleanup), with the producer/operator split and the shared-resource caveat.

### Implementation

- **feat(roles):** new `guide` action in `bin/core/roles` (read-only — prints the workflow, exit 0). `roles` now exposes `list` / `status [<role>]` / `<role>` / `guide`.
- **docs:** SPEC.md §2 roles sub-commands.

### Tests

- **test(test-codex-adapter §87) +1:** `roles guide` prints the workflow (run-role → merge-role). **751 → 752 PASS / 0 FAIL.**

**Migration:** zero action. Read-only addition. CC + Codex (the command works in both).

## v6.22.0 — 2026-06-26

`apd merge-role` (Milestone D1) — a read-only merge gate, the exit side of the role lifecycle (`run-role` is the entry). It tells you whether a producer role's `<role>-work` branch is ready to merge back, and prints the command — it **never runs `git merge` itself**. The merge is irreversible and, unlike commit/push, `git merge` is not guarded — so the human pulls that trigger. APD advises, you merge.

### What it checks (all read-only)

- `<role>-work` branch exists and is **ahead** of the integration branch (auto-detected develop → main → master, or `--into <branch>`)
- the worktree is **clean** (no uncommitted work to lose)
- the pipeline is **idle** — no active `spec-card.md`. It reads git state + idle, NOT `verifier.done`: the post-commit reset deletes the `*.done` flags, so a "passed" flag is gone by merge time; git provenance is the durable signal.
- whether the target moved (**behind**) → prints sync-first guidance: `git merge <target>` in the worktree (NOT rebase — rebase needs force-push, which is guarded), resolve conflicts where the domain context is, re-run the verifier, re-check.

When ready it prints `git checkout <target> && git merge <branch>` + the pre-merge target SHA (for `git reset --hard` recovery). It does not run it.

### Implementation

- **feat(merge-role):** new `plugins/apd/bin/core/merge-role`. Resolves the main root via the shared git-common-dir so it works from the main checkout or a worktree. Guards: unknown role / operator role / non-git / missing `<role>-work` branch → exit 1.
- **feat(apd dispatcher):** `merge-role|mr` case + help line.
- **docs:** SPEC.md §2 row + §6.5 D1 note.

### Tests

- **test(test-codex-adapter §90) +9:** 3 static (executable, dispatcher wiring, read-only invariant) + 6 live (READY → exit 0 + merge guidance; **read-only proof — develop SHA unchanged after the gate ran**; unknown role; operator role; missing branch; BEHIND → sync-first + exit 1). **742 → 751 PASS / 0 FAIL.**

**Migration:** zero action. Read-only; the human runs the merge. CC only.

## v6.21.0 — 2026-06-26

`apd run-role --launch` (Milestone C2) — opt-in flag that spawns Claude Code in the prepared worktree, so a producer role goes from "no worktree" to "working in its session" in one command. C1 prepared the worktree and printed `cd <path> && claude`; C2 does that last step for you when you ask.

### What it does

- `apd run-role <role> --launch` prepares the worktree (same as C1: create/reuse + bootstrap + dev-env) and then enters it: it scrubs `APD_PROJECT_DIR` + `CLAUDE_PLUGIN_ROOT` from the environment and `exec claude` from inside the worktree, so the new session resolves the worktree as its **own** project root rather than inheriting a leaked main-checkout root (R6). Without `--launch`, behaviour is unchanged (prepare-only, prints the command).

### Implementation

- **feat(run-role):** `--launch` flag. After prepare: if `claude` is on PATH, `cd` into the worktree, `unset APD_PROJECT_DIR CLAUDE_PLUGIN_ROOT`, `exec claude`. If not (E11), degrade to prepare-only with a warning + the manual command. Spawning CC from a script is an established pattern in-tree (`skill-eval` runs `claude -p`).
- **docs:** SPEC.md §2 row + §6.5 C2 note.

### Tests

- **test(test-codex-adapter §89) +6:** 4 static (`--launch` parsed, `exec claude`, env scrub, E11 `command -v claude` guard) + 2 live via a mock `claude` (—launch spawns in the worktree with `APD_PROJECT_DIR` scrubbed to EMPTY; no `--launch` → prepare-only, does NOT spawn). **736 → 742 PASS / 0 FAIL.**

**Migration:** zero action. `--launch` is opt-in; default behaviour is unchanged. CC only.

## v6.20.0 — 2026-06-26

`apd run-role` (Milestone C1) — prepare a git worktree for a producer role. The step after the v6.19 role registry: where `apd roles` *describes* the roles, `run-role` *puts a producer role to work* in its own isolated worktree (feature branch + folder + isolated APD pipeline). Prepare-only — it sets up the worktree and prints the launch command; spawning Claude Code is an opt-in `--launch` flag in a later patch (different reversibility class).

### What it does

- `apd run-role <role>` creates (or reuses) `.claude/worktrees/<role>-work` on branch `<role>-work`, bootstraps APD config into it (**never** the pipeline state), runs the project's `.apd/dev-env-setup` if present, and prints `cd <path> && claude`. Only producer roles (`worktree=yes`) are eligible; operator roles (devops/debug/master) run in the main checkout.

### Why APD owns the worktree lifecycle

CC native `claude --worktree` was measured to be create-only (fatals on an existing worktree) and to leave stray directories on exit. So run-role drives `git worktree add` itself with a stable `<role>-work` convention and reuses an existing worktree instead of recreating it.

### Dev-env

A fresh worktree checks out only tracked files — deps/DB/secrets are missing. If the project ships a tracked, idempotent `.apd/dev-env-setup` (typically a thin call to its own `run.sh` / `start_apps.sh`), run-role runs it. APD doesn't know the stack; the project does. (Note: a worktree isolates code + pipeline, NOT shared external resources — a local DB/Redis/fixed ports are shared across worktrees; parallel producers that write the same DB must coordinate or isolate it in their dev-env-setup.)

### Implementation

- **feat(run-role):** new `plugins/apd/bin/core/run-role` (prepare-only). Guards: E1 inside-worktree → BLOCK exit 2; E2 operator role → BLOCK exit 1; E4 stray dir → BLOCK exit 2 (**never auto-deletes** — global rule 1); E7 non-git → exit 1; E9 unknown role → exit 1; E3 active pipeline → warn; E6 dirty main → warn. Reuses `worktree-bootstrap` for config.
- **feat(apd dispatcher):** `run-role|rr` case + help line.
- **docs:** SPEC.md §2 CLI row + §6.5 C1 note (incl. why Milestone B — scope→agent scaffolding — was skipped as redundant: scope already flows through `{{SCOPE_PATHS}}`/`{{SCOPE_*}}` and `roles.conf` carries the charter).

### Tests

- **test(test-codex-adapter §88) +12:** 3 static (executable, dispatcher wiring, never-auto-delete invariant) + 9 live (E9 unknown, E2 operator, producer create, worktree registered + config bootstrapped + pipeline NOT leaked, dev-env hook ran, reuse idempotent, E1 inside-worktree, E4 stray dir, E7 non-git). **724 → 736 PASS / 0 FAIL.**

**Migration:** zero action. CC only (worktrees need `git`; Codex has no `--worktree`). Operator roles and non-git projects are unaffected (guarded).

## v6.19.0 — 2026-06-26

Generic role registry (`apd roles`) — Milestone A of the team-of-orchestrators model. Roles are the second axis next to model profiles (v6.16): a profile says how strong a brain the agents carry; a role says which domain + which workspace an orchestrator owns. This ships the registry as read-only DATA; worktree creation (`run-role`) and scope→agent scaffolding are later milestones in the chain.

### What it does

- `apd roles list` / `roles status` / `roles status <role>` inspect 8 generic, tech-agnostic developer roles in two classes: **producer** (backend, frontend, mobile, backoffice, reporting — `worktree=yes`, get their own git worktree in a later milestone) and **operator** (devops, debug, master — `worktree=no`, run from the main checkout). Governing principle: a worktree belongs to producers of an artifact, not to integrators or operators.

### Implementation

- **feat(roles.conf):** new `plugins/apd/templates/roles.conf` — DATA, pipe-delimited `role|worktree|default_profile|scope|boundary`. Each role carries a scope charter + boundary. Per-project override `.apd/roles.conf` wins wholesale (mirrors `model-profiles.conf`). **role ≠ agent**: a role is a workspace/domain, an agent is a pipeline executor; one producer role runs a full pipeline dispatching many agents.
- **feat(roles):** new `plugins/apd/bin/core/roles` — read-only `list` / `status` / `status <role>` / `<role>` shorthand. Mirrors the read side of `pipeline-model-profile` (awk row parsing, project-override precedence). No mutation in this milestone.
- **feat(apd dispatcher):** `roles|rl` case + help line.
- **docs:** SPEC.md §2 CLI row + new §6.5 (Role registry).

### Tests

- **test(test-codex-adapter §87) +12:** 6 static (script executable, conf present, 8 roles, 5-field rows, worktree class flags, dispatcher wiring) + 6 live via `APD_PROJECT_DIR` isolation (list, status summary 5/3, status backend=producer, debug shorthand=operator, unknown→exit 1, project override wins). **712 → 724 PASS / 0 FAIL.**

**Migration:** zero action. Read-only; `roles.conf` is a plugin template read directly, no project scaffolding. The command works in CC + Codex; producer-role worktrees are CC-only, a later milestone.

## v6.18.0 — 2026-06-24

Parallel sessions via git worktree — make APD activate inside a fresh worktree so two independent pipelines can run on one repo without colliding. CC has native worktree support (`claude --worktree`), and the git-toplevel resolver already isolates pipeline state per-worktree (proven empirically: two concurrent pipelines, distinct commits, main untouched). The gap was config bootstrap: a real project gitignores the whole `.claude/` tree, so a fresh worktree starts without APD config/agents and session-start exits early. This closes that gap. Additive, CC-side — no existing gate touched.

### What it does

- A linked worktree (`claude --worktree X` → `.claude/worktrees/X/`) gets APD config/agents copied from the main checkout on first session-start, so APD is fully live there (agents, guards, pipeline). The pipeline **state** is never copied — each worktree keeps its own isolated pipeline.

### Implementation

- **feat(worktree-bootstrap):** new `plugins/apd/bin/core/worktree-bootstrap`. Copies `.claude`/`.apd` config + agents + rules + skills from the main checkout (`dirname(git-common-dir)`) into the worktree. Three safety guards: acts only in a linked worktree (`git-dir != git-common-dir`), only when config is absent (idempotent), never the main checkout; **never copies `.apd/pipeline/`**. Does not source the resolver (which would walk up to main).
- **fix(resolve-project.sh):** new `_apd_is_linked_worktree()` — a linked worktree resolves to itself even without an APD marker, instead of walking up to the main checkout (which would make APD silently operate on main state). `.worktreeinclude` alone is insufficient here: a dir-level `.claude/` gitignore collapses the tree, so CC copies nothing inside it.
- **feat(session-start):** calls `worktree-bootstrap` before the `APD_ACTIVE` gate, then re-sources the resolver.
- **docs:** SPEC.md §16.5 + new §16.6.

### Tests

- **test(test-codex-adapter §86) +8:** 3 static (helper executable, resolver detection, pipeline never in copy list) + 5 live (clean worktree resolves to itself, APD_ACTIVE=false; bootstrap copies config+agents, pipeline NOT leaked; APD_ACTIVE=true after; main no-op; idempotent).
- **fix(test):** maxturns fixture used a hardcoded date inside a rolling 30-day window (time-bomb — silently expired once the date fell outside 30 days). Now relative to today. **704 → 712 PASS / 0 FAIL.**

**Migration:** zero action. Bootstrap is a no-op outside a linked worktree and on projects without APD. CC only (Codex has no `--worktree`/`.worktreeinclude`).

## v6.17.0 — 2026-06-20

Regression surface gate — make collateral regression a declared, mechanically-checked concern. When a task reaches into a shared module to do its own job, the surrounding behaviour of that module must stay provably intact. The adversarial reviewer is the only existing defence and it is not exhaustive on the first pass (corpus evidence: a "clean" 5:3:2 run shipped a latent `OperationCanceledException`-swallow caught only by a later sibling task). New verifier + spec-card block = minor. Additive enforcement — no existing gate touched.

### What the gate does

Three graduated levels; strictness is **derived from risk**, not chosen by the orchestrator:

- **Declaration (always)** — spec-card.md gains a `**Regression surface:**` block naming what the task touches indirectly. Empty is allowed only as an explicit, justified `none — <reason>` (forces awareness, not silence).
- **Coverage anchor (default)** — every `- RS<N>:` item must carry a `**Cover:**` value (existing test / `new <name>` / `none: <reason>`), modelled on the plan-spec `**Implements:**` check.
- **Execution evidence (escalation)** — derived from the existing `**Human gate:**` field (yes/required → API/migration/auth/deploy). Each RS item then also needs an `**Evidence:**` attestation (≥40 chars). The gate checks the attestation is **present**, exactly like the verifier checks `.adversarial-rationale.md` exists — it never maps module→suite nor runs tests (cross-stack confabulation trap). The builder runs and attests.

Anti-gaming: Human gate set + no surface declared → issue. A `regression_gate: off` opt-out is **ignored on a Human-gate path** — the sensitive path cannot opt out.

### Implementation

- **feat(verify-regression-surface):** new `plugins/apd/bin/core/verify-regression-surface`. Reads spec-card.md; parses the surface block + risk signal; coverage + escalation + anti-gaming checks; mode from `regression_gate: strict|warn|off`; logs `regression-surface` to guard-audit on strict BLOCK.
- **feat(pipeline-advance):** called in the builder phase after `verify-plan-spec`, with a copy-paste actionable BLOCK message.
- **Rollout default = `warn`** (grace window — existing E2E fixtures are unaffected without edits, same staged approach as verify-plan-spec v6.8.0). Flip to `strict` on live evidence.
- **docs:** `apd-pipeline-guide` (CC + Codex + openai.yaml) new Regression surface contract section + phase-map + Common BLOCKs row; `workflow.md` spec-card skeleton + section; `AGENTS.md` step 1; `apd-brainstorm` (CC + Codex) Converge template nudge; `SPEC.md` verifier row + §24 callsite note.

### Tests

- **test(test-codex-adapter §85) +15 assertions:** 5 static (binary, Cover check, Evidence escalation, mode parser, warn default) + 10 live (covered pass, missing-Cover BLOCK, escalated-missing-Evidence BLOCK, escalated-with-Evidence pass, anti-gaming BLOCK, self-contained `none` pass, off opt-out, off-ignored-on-Human-gate, default-warn safety, bare-`none` BLOCK). **689 → 704 PASS / 0 FAIL.**

**Migration:** zero action. The gate ships `warn` by default and is a no-op on specs without a `**Regression surface:**` block. Adopt incrementally; set `regression_gate: strict` per spec to opt a project in early.

## v6.16.1 — 2026-06-12

Hot-fix: `apd init` update mode now actually repairs what `apd audit-drift` detects. Live trigger (FiscalFusionAI, 2026-06-12): after `init --quick` AND a `/apd-setup` re-run, all three drift findings persisted unchanged (APD_VERSION=4.7.8, 4/8 deny patterns, workflow.md with 0/5 guidance markers) — the documented recovery was structurally a no-op for existing projects.

### `apd-init` update mode reconciles drift dimensions

- **fix(permissions, dim A):** the merge probe checked three ALLOW patterns only — any pre-v6.10 install already had them, so the probe never re-entered the merge and projects stayed at 4/8 deny patterns forever (this retroactively explains the Bambi/Festico "4/8 after multiple re-inits" mystery: v6.10 fixed the LIST, not the CONDITION). The probe now includes a deny sentinel (`Bash(mkdir .apd/pipeline)`).
- **fix(.apd-config, dim B):** `APD_VERSION` was written only at scaffold time. Update mode now syncs a stale value to the live plugin version (replace or append).
- **fix(workflow.md, dim C):** refresh used to trigger only on stale PATHS (`CLAUDE_PLUGIN_ROOT`, `.claude/.pipeline`); content-stale copies (still instructing the removed `--skip-brainstorm`) were kept forever. Update mode now also refreshes when any of the five guidance markers is missing (same list as audit-drift dimension C, kept in sync), with a first-wins `workflow.md.bak.preaudit` backup.
- **fix(model repairs × v6.16 profiles):** update mode force-reset code-reviewer→opus and adversarial→sonnet — and session-start runs init every session, so a `burn`/`eco` model profile would have been silently reverted on the next session start. When `MODEL_PROFILE` is declared, the model repairs are skipped (`apd profile` owns models); the adversarial `memory: none` contract still gets a warn.

Net effect: the next session-start auto-heals all three drift dimensions on every stale project, and the drift Recovery text ("re-run init/setup") is now true. Idempotent — second run applies zero fixes.

### Tests

- **test(test-codex-adapter §84) +10 assertions:** 4 static + 6 live (version bump, 4→8 deny merge despite present allow entries, marker-driven workflow refresh + backup, legacy model repair without profile, no-revert with profile declared, idempotency). **679 → 689 PASS / 0 FAIL.**

**Migration:** zero action — the repair runs automatically at next session start. Projects with a customized workflow.md get it refreshed; the original is preserved at `workflow.md.bak.preaudit`.

## v6.16.0 — 2026-06-11

Agent model profiles — an economy vs quality dial for the pipeline. One command switches every agent's `model:`/`effort:` between named profiles, and every switch is recorded so pipeline runs finally carry model attribution. New subcommand + skill = minor. Enforcement floor untouched (pure config/telemetry layer).

### `apd profile` — model profiles for pipeline agents

**Why:** model per agent was hand-edited frontmatter scattered across N files, and the empirical corpus (Opus 4.8 era) had a known gap — "model version is not logged per run", which kept the speed/quality delta evidence at n=1. Profiles make the switch mechanical and the attribution automatic.

- **feat(templates/model-profiles.conf):** profiles are DATA, not code. Ships `burn` (launch-critical: `claude-fable-5`/high, adversarial `opus`/max), `cruise` (daily default: `opus`/xhigh, adversarial `sonnet`/max), `eco` (small pre-scoped work: `sonnet`/xhigh, adversarial `sonnet`/max). A project may override the whole table via `.apd/model-profiles.conf`. Design rule encoded in the defaults: builders carry the tier (context-heavy), the adversarial reviewer may sit one tier BELOW — its value is positional (fresh context), not model-tier.
- **feat(pipeline-model-profile):** new `apd profile` / `apd pf` — `list`, `status`, `<name> [--dry-run]`. Role resolution by agent file name: `adversarial-reviewer` → adversarial row, `code-reviewer` → reviewer row (falls back to default), `apd-verify-*` reserved namespace never touched, everything else → default (builder class). Rewrites `model:` + `effort:` in the first frontmatter block only (inserts `effort:` when absent; body untouched).
- **Telemetry:** apply records `MODEL_PROFILE=<name>` in the APD config and writes a `model-profile-switch` INFO entry to guard-audit.log (routed through `_audit_type`, so `apd verify` self-tests tag SYNTHETIC). Runs between two switches are attributable to a profile.
- **Refuses mid-pipeline:** active `spec-card.md` → exit 2. A mid-task model swap would pollute the run's model attribution and change agents under a running cycle.
- **Drift detection:** `apd profile status` compares actual frontmatter against the declared profile and flags hand-edited agents as DRIFTED.
- **feat(skills/apd-profile):** new CC-only skill — shows status + profiles, asks the user to pick, applies, and mandates the session-restart reminder (agent definitions load at session start; no hot-reload claim).
- **CC-only v1:** Codex `.codex/agents/*.toml` (gpt-* model namespace) are explicitly unsupported with a clear message — no silent pretending (v6.12.2 lesson). Deferred to v2: Codex support, per-profile maxTurns (waits for the Phase 2 maxTurns calibration), pipeline-metrics column.

### Tests

- **test(test-codex-adapter §83) +14 assertions:** 5 static (script, conf rows, dispatcher wire, skill, SPEC) + 9 live (role split on apply, effort insert + body preservation, reserved-namespace skip, config + audit entry, status IN SYNC, hand-edit DRIFTED, mid-pipeline refuse exit 2, unknown-profile exit 1 + dry-run writes nothing, project override wins). **665 → 679 PASS / 0 FAIL.**

**Migration:** zero impact — nothing changes until you run `apd profile <name>`. After a switch, restart the CC session.

## v6.15.0 — 2026-06-10

The brainstorm/tutor split: a new mandatory `apd-pipeline-guide` skill takes over the pipeline-contract education that v6.8.4 had bolted onto `apd-brainstorm`, and the spec gate moves to its marker — unconditionally, with no skip flag. Plus a three-way guard message for pipeline-state blocks and a batch of pre-release audit fixes. New skill + gate swap = minor.

### `apd-pipeline-guide` — the pipeline operating manual (new skill, mandatory)

**Why (root cause, empirical):** `apd-brainstorm` carried two unrelated roles — interactive scope clarification (legitimately skippable when scope is pre-aligned) and the pipeline tutor (never legitimately skippable). The skip valve discarded education along with ceremony: an orchestrator with a clear task rationally skips a skill NAMED "brainstorm", unaware it carries the gate contract. Bambi 2026-06-09/10: 8/8 runs skipped with textbook-legitimate reasons — and the residual skip→BLOCK tail (~19%, forgotten `**Implements:**` headers) was exactly education-shaped. The v6.8.8 TWO-PART CHECK ("scope AND APD config clear") was this disease's patch: the guide function smuggled into a skip condition, recited rather than loaded.

- **feat(skills/apd-pipeline-guide):** new skill, CC + Codex mirror (with `agents/openai.yaml`). Content: pipeline phase map with the gate at each advance, implementation-plan `**Implements:**` contract (NO RESERVED NAMES), adversarial rationale `.md` contract, common BLOCKs + recovery table, and the sanctioned `apd pipeline show` read path. Exit step writes `.apd/pipeline/.guide-marker` (`<task-name>|<ISO-8601>`).
- **feat(pipeline-advance):** spec advance requires `.guide-marker` matching the task name — **unconditional, NO skip flag** (`guide-marker-missing` BLOCK). Reading the contract is cheaper than negotiating about it (~10× cheaper than one BLOCK loop). The BLOCK message routes vague scope to `/apd-brainstorm` FIRST, then the guide.
- **feat(skills/apd-brainstorm):** redesigned to pure clarification (CC + Codex) — its original identity. Marker mechanics, TWO-PART CHECK, and all `--skip-brainstorm` content removed; hand-off now goes through the guide. Description states explicitly: skipping brainstorm never skips the guide.
- **BREAKING-ish:** `--skip-brainstorm` is REMOVED. A hard-error shim (kept until v7.0) explains the change and points at the guide — a silent fallback would resurrect the no-education path. The `brainstorm-skipped` INFO emitter is gone (historical log entries remain parseable). Legacy `.brainstorm-marker` stays guard-allowlisted until v7.0 for mid-flight upgrade tasks but does NOT satisfy the gate.
- **Guards:** `guard-pipeline-state` / `guard-bash-scope` / `guard-file-edit` allowlist `.guide-marker`. Reset wipes both markers. `verify-apd` Section 8 pre-writes the guide marker (SPEC §24 callsite grep done).
- **docs:** workflow.md step 1 + mandatory-skills table, Codex AGENTS.md step 0 + table, SPEC.md (lifecycle, skills 10 CC / 8 Codex, `.guide-marker` state row), README skills + enforcement tables, GETTING-STARTED first-task walkthrough.
- **Enforcement floor unchanged:** same trust model as the old marker — the split raises EDUCATION, not enforcement; the floor stays on the existing guards.

**Migration:** load `/apd-pipeline-guide` before every spec advance (~2 min). Projects mid-task during upgrade hit ONE `guide-marker-missing` BLOCK; recovery is loading the guide. Any automation passing `--skip-brainstorm` gets a hard error with instructions.

### Three-way guard message for pipeline-state blocks (#5)

Cross-project telemetry showed the most common real block is `pipeline-state-write` — and the orchestrator mostly READS (`cat .reviewed-files`), burning a turn per block because the old message ("use the apd command instead") pointed at the wrong channel. Live evidence (Bambi 2026-06-10, v6.13+): the workflow.md instruction alone did not change behavior; the message at the moment of error is the lever.

- **fix(guard-bash-scope):** new `_pipeline_block_guidance()` emitted from all 3 pipeline-state BLOCK branches (write-op, redirect, runtime-write): READ → `apd pipeline show [spec|plan|state]`, WRITE allowlisted file → Write/Edit tool, ADVANCE → `apd pipeline <phase>`. Enforcement-neutral (wording only).

### Pre-release framework audit (9 findings, all fixed)

- **fix(pipeline-advance):** 3 hardcoded `.claude/bin/apd` BLOCK-message paths → `$APD_SHORTCUT_DISPLAY` (one dated back to v6.8.3; misdirected Codex projects).
- **fix(pipeline-audit-drift):** dimension B read the hardcoded legacy `.claude/.apd-config` instead of the resolver's `$APD_CONFIG_FILE` — pure-Codex projects (config at `.apd/config`) were misreported. Labels now dynamic; drift test fixtures repointed to the realistic installer layout.
- **docs(GETTING-STARTED):** the first-task walkthrough would have BLOCKed as documented — no guide-load step, and the implementation-plan example lacked `**Implements:**` headers (stale since the v6.8.1 strict default). Both fixed; guard example message updated to the three-way guidance.
- **docs:** MCP tool count corrected to 9 at six stale sites (GETTING-STARTED said 6; README ×2, SPEC ×2, CLAUDE.md said 8 — stale since v6.2 added `apd_pipeline_metrics`).
- **fix(cdx/skills-install):** `ALL_SKILLS` list 4 → 8 (stale since v5.0.7 added audit/github/miro; now includes the guide).
- **fix(test-system):** repaired — broken since v6.8.1/v6.8.11 (un-run E2E surface): marker pre-writes + plan `Implements` fixtures added (15 FAIL on the old HEAD → only pre-existing environment failures remain).
- **docs(SPEC/CLAUDE.md):** stale test-suite counts refreshed.

### Tests

- `_v6811_marker` helper → `_guide_marker` (20 fixture callsites). §63/§64/§66/§67/§70/§71/§78/§80/§82 rewritten or extended for the split + #5 lock-in (incl. name-mismatch and legacy-marker-does-not-satisfy live checks). Drift fixtures updated for the new workflow marker (`apd-pipeline-guide`). **667 → 665 PASS / 0 FAIL** (rewritten sections carry slightly fewer, stronger assertions).

## v6.14.0 — 2026-06-04

A new recovery command (`reconstruct-agents`), an apd-brainstorm skill audit fix, and a CHANGELOG language cleanup. The new subcommand makes this a minor.

### `apd pipeline reconstruct-agents` — recovery for CC SubagentStop hook non-delivery

**Trigger (BambiProject, 2026-06-04):** Claude Code stopped firing the SubagentStop hook for a session while still firing other hooks (the security-guidance Stop hook ran cleanly). Subagents genuinely ran (full transcripts on disk — migration, review, tests passed) but `.agents` stayed empty, so the builder gate could not confirm a builder was dispatched and the whole chain blocked. Confirmed CC-side (not APD): `track-agent` logs its payload as its first action, and zero entries after the freeze means CC never invoked the hook; `track-agent` was byte-identical across versions and stable for days; security-guidance does not register SubagentStop.

- **feat(pipeline-advance):** new `apd pipeline reconstruct-agents` case. Rebuilds `.apd/pipeline/.agents` from CC subagent transcripts at `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/<slug>/<session>/subagents/agent-<id>.jsonl` (+`.meta.json` for `agentType`). Writes a start+stop pair ONLY for agent-ids whose transcript file exists (CC ground truth the orchestrator cannot fabricate) and whose completion is after `spec.done`. Skips already-recorded ids. Guarantees start < stop (non-zero duration). Loud `INFO|reconstruct-agents|...` audit entry.
- **Integrity:** a phantom agent with no transcript is never reconstructed — so a genuine hook-failure is recoverable while fabrication stays blocked. This is the distinction a hand-written `.agents` (which the guard blocks, and which is a social-engineering risk) cannot make: the transcript-existence precondition mechanizes the check instead of trusting the premise.
- **docs(SPEC.md):** `reconstruct-agents` row in the pipeline subcommand list, with the CC-bug diagnosis.

### apd-brainstorm skill audit

Audit found two defects in the shipped skill (CC + Codex mirror), both fixed:

- **Language:** Serbian prose had crept into the shipped skill during the Serbian-chat period (CLAUDE.md requires English docs). Translated to English; content/structure unchanged. (Note: `apd-toggle`'s Serbian is intentional — multilingual trigger phrases the skill must recognize — and is left as-is.)
- **Stale `max_defects` in the `--skip-brainstorm` reason:** the override checklist + example modeled confirming `max_defects=unlimited`, contradicting the skill's own "DEPRECATED — DO NOT write" guidance (v6.9). Removed from the checklist and example; the adversarial budget is simply the default (no field).
- **test(test-codex-adapter §82):** asserts both apd-brainstorm SKILL.md files are free of Serbian markers + the skip-reason carries no deprecated `max_defects`.

### CHANGELOG language cleanup

- **docs(CHANGELOG):** the v6.8.0–v6.12.3 entries (and a stray word in v5.0.2) were written in Serbian; translated to English preserving all technical tokens, tables, and code blocks. The v6.13.0 entry was likewise rewritten to English.

### Tests

- **test-codex-adapter §81–§82:** +11 assertions. **656 → 667 PASS / 0 FAIL.**

## v6.13.0 — 2026-06-02

Three **enforcement-neutral** improvements derived from cross-project log analysis (Bambi/.NET, FiscalFusionAI/Python-ML, ig-commerce/Next.js) under Opus 4.8. All three are observability / audit / UX — **the enforcement floor is unchanged** (the cross-project comparison showed the floor holds uniformly; only the bypass *style* varies per project). Minor: new features, backward-compatible.

### #1 — verify-apd self-test no longer pollutes guard-audit telemetry

Every `apd verify` run fired ~10 guards in the guard-coverage section plus the Section 8 synthetic pipeline, writing ~10 real-looking `|BLOCK|` lines into the project's `guard-audit.log`. Historically: ~75 such sweeps in Bambi, ~17 in FFAI, ~11 in ig-commerce — `apd report` and any guard-audit analytics were misrepresenting the project.

- **feat(style.sh):** new `_audit_type()` helper — `log_block` resolves the log type (`BLOCK` → `SYNTHETIC` when `APD_AUDIT_SYNTHETIC=1`).
- **feat(guard-git):** guard-git carries its OWN `log_block` (does not source style.sh) and produces most of the sweep (commit-no-prefix / mass-staging / force-push / destructive-git) — mirrors the same flag inline.
- **feat(verify-apd):** `export APD_AUDIT_SYNTHETIC=1` — child guard/pipeline processes inherit it.
- **feat(pipeline-advance):** the two INFO writers (brainstorm-skipped, max-defects-deprecated) route through `_audit_type`.
- **fix(pipeline-report):** counts only `log_type==BLOCK` — excludes INFO/SYNTHETIC/PERMISSION_DENIED. **Bonus:** fixes a pre-existing bug where INFO entries (brainstorm-skipped) were counted as guard blocks.
- The reset summary (v6.8.9) already cases on log_type with a default-ignore branch — `SYNTHETIC` falls out automatically.

### #2 — adversarial rationale archive (dismiss-heavy runs become retro-auditable)

Dismiss-heavy runs (PT.1 11:1:10, FFAI Hotfix 8:1:7 class) lost `.adversarial-rationale.md` on reset/re-advance → no retroactive audit possible; the in-flight gate (warns + A≥1) was the only check.

- **feat(pipeline-advance):** new `archive_rationale()` (mirrors the agent-history.log pattern) — on spec re-advance and reset, appends to a permanent `<memory>/adversarial-rationale-archive.md` BEFORE the wipe. Entry: `## Archived <ts> — <task>` + `**Summary:** ADVERSARIAL:T:A:D` + full rationale body. Task name from `spec.done`. Skipped under `APD_AUDIT_SYNTHETIC=1`. Does NOT archive on rollback (same-task re-run, intermediate noise). Cross-reference with `pipeline-metrics.log` by timestamp.

### #4 — sanctioned read-only pipeline state

The most frequent *real* `pipeline-state-write` BLOCK across all three projects was the orchestrator **reading** state via bash (`cat .reviewed-files`, `ls .apd/pipeline`) → BLOCK → recover, losing a turn each time. The guard correctly blocks bash access (a read can be recon for a fake-review bypass), but there was no clean read channel.

- **feat(pipeline-advance):** `apd pipeline show [spec|plan|state]` + a `print_pipeline_state()` digest (also shown by `status`). `spec`/`plan` = full echo (the orchestrator's own authored files); `state`/default = digest (criteria count, plan present?, reviewed-files COUNT, adversarial T:A:D, rationale findings + Do/Dr, cycle counts). Generated state is NEVER raw-dumped — counts/digest only (recon-bounded). **Guard untouched** — only a legitimate channel added.
- **docs(workflow.md + AGENTS.md):** "Inspecting pipeline state" — use `apd pipeline show`/`status`, do NOT bash cat/ls on `.apd/pipeline`.

### Other

- **docs(SPEC.md):** guard-audit `TYPE` (BLOCK/INFO/PERMISSION_DENIED/SYNTHETIC), `adversarial-rationale-archive.md`, `show` subcommand.
- **test(test-codex-adapter §78–§80):** +26 assertions (incl. guard-git static+live). **632 → 656 PASS / 0 FAIL.**

## v6.12.3 — 2026-05-28

Third hot-fix the same day, **structural instead of manual** after the user's point that "v6.12.2 prevents NEW confabulation but does not FIX existing ones". Implemented **drift dimension D — feature claim drift** in `pipeline-audit-drift` (v6.10 family).

**What dim D does:**

Scans `.claude/rules/workflow.md` + `.claude/CLAUDE.md` + `CLAUDE.md` (project root) for any line that mentions BOTH:
- a contracts command (`verify-contracts` or `apd contracts`)
- AND an unsupported language (PHP / Python / Java / Go / Ruby / Kotlin / Rust)

Match = IMPORTANT drift with a per-claim breakdown. awk-based detection (not a grep regex) because the pattern requires "both X and Y in the same line in any order" — a grep regex cannot express that cleanly.

**Sample output (synthetic confabulation):**

```
IMPORTANT:
  1. [.claude/rules/workflow.md] Feature claim drift — 3 unsupported language claim(s)
    - contracts command → PHP (verify-contracts supports TypeScript ↔ C# only as of v6.12+)
    - contracts command → Python (...)
    - contracts command → Go (...)
    Effect: orchestrator (or human reading docs) believes feature exists; relies on it; silent gap in cross-layer review coverage.
    Recovery: edit the file — replace 'apd verify-contracts ... <lang>' claims with 'manual cross-layer type mapping (see workflow.md sekcija 7 for the table)'. Framework reality: verify-contracts errors on unsupported langs (v6.12.2+ shows file-count + supported pairs).
```

**Why a structural fix over manual cleanup:**

User insight: the anti-pattern in the apd-setup skill (v6.12.2) prevents future confabulations but does not fix existing ones. An apd-setup re-run is not a reliable cleanup because it is additive (not destructive). A manual edit is a 2-minute job for one project, but the class of problem can recur — drift detection closes the **class**, not the instance.

**Validation:**

- Synthetic project with 3 false claims (PHP + Python + Go) → detected with a per-claim list
- Festico in its current state (section 7 has manual guidance) → NOT flagged (the manual "Backend DTO is source of truth" + "For each field, map the type" is not caught because there is no command+language combination on the same line)
- Clean workflow.md with "Manual cross-layer review — automatic verification only for TS ↔ C# pairs" → NOT flagged

**Highlights:**

- **feat(pipeline-audit-drift):** new `_check_feature_claims()` helper, iterates 7 unsupported languages × 2 file types (workflow.md + CLAUDE.md). awk-based both-on-same-line detection.
- **fix(skills/apd-audit/SKILL.md):** Section 8 dimension 4 documented (CC + Codex mirror)
- **test(test-codex-adapter §77) +8 assertions:** 5 static + 3 live (confabulation detected, clean guidance not flagged, CLAUDE.md scan covered)
- **Test count 624 → 632 PASS / 0 FAIL.**

**Migration:** projects with existing confabulation in workflow.md/CLAUDE.md will see IMPORTANT in `apd audit-drift`. The recovery action in the message explicitly states what to do — replace with a "manual cross-layer type mapping" reference.

**What this achieves structurally:**

v6.12.2 anti-pattern (prevent) + v6.12.3 drift detection (detect existing) = both layers covered for the confabulation pattern. A Festico-style problem can no longer slip through silently — either apd-setup does not write confabulation, or the audit catches it.

## v6.12.2 — 2026-05-28

Second hot-fix the same day, after Festico's second observation. `verify-contracts` has two fail-quietly patterns that create a **silent false-pass** illusion:

1. **`--changed` mode message is ambiguous** — "Changes do not affect types at layer boundaries" did not distinguish "no relevant change" from "language pair not supported". A user editing a PHP DTO gets this message and thinks "OK, nothing to do".
2. **Full directory mode error message is generic** — "Unrecognized backend language" does not tell the user what WAS detected (what exactly is failing).

Plus a documentation crisis: **Festico CLAUDE.md/workflow.md claim "apd verify-contracts checks PHP DTO ↔ TS automatically"** — that is the orchestrator's confabulation in apd-setup, not a framework template claim. The framework template does not mention verify-contracts at all. The orchestrator probably saw `apd verify` in the SPEC and invented the functionality.

**Highlights:**

### A. `--changed` mode — more precise detection

- **Added:** detection of `UNSUPPORTED_CHANGED` files — .php/.py/.java/.go/.rb/.kt/.rs inside backend/frontend dirs
- **Output:** when changes are detected in an unsupported language, emit explicit:
  ```
  Detected N changed file(s) in unsupported language(s).
    Sample (up to 5):
      backend/src/Module/Foo.php
    Contract verifier supports TypeScript ↔ C# only.
    PHP/Python/Java/Go/Ruby/Kotlin/Rust require manual cross-layer review.
    See workflow.md sekcija 7 (cross-layer type mapping) for the table.
  ```
- **Plus NOTE** after the "Changes detected in type files" hint: "verifier supports TypeScript ↔ C# only. For other backends, this command will error — see workflow.md section 7 for the manual review process."

### B. Full mode error enriched with `_lang_summary`

- **New helper function:** `_lang_summary()` uses `find -not -path` (no grep pipe with the pipefail problem) to count `.cs/.ts/.tsx/.php/.py/.java/.go/.rb/.kt/.rs` files
- **Error now shows:**
  ```
  ERROR: Unrecognized backend language in backend/src. Supported pairs: TypeScript ↔ C#.
    Detected: 0 .cs, 0 .ts/.tsx, 658 .php, 0 .py, 0 .java, ...
    PHP/Python/Java/Go/Ruby/Kotlin/Rust are not yet supported. For these stacks,
    see workflow.md sekcija 7 (cross-layer type mapping) — manual review process.
  ```

### C. Script header — explicit list

- "NOT supported (require manual cross-layer review): PHP, Python, Java, Go, Ruby, Kotlin, Rust"

### D. apd-setup skill anti-pattern

- New anti-pattern in `skills/apd-setup/SKILL.md`: "Don't promise framework features that don't exist in generated CLAUDE.md / workflow.md. Especially: `apd verify-contracts` supports TypeScript ↔ C# only (v6.12+)." Plus guidance: "When uncertain about framework feature scope, read `${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/<command>` script header for exact supported scope, or `docs/SPEC.md`."
- Empirical reference: Festico apd-setup 2026-05-28 (orchestrator confabulated a PHP support claim)

### E. Tests §76 +9 assertions

- 6 static (header lists unsupported langs, `_lang_summary` helper, full mode invokes helper, `--changed` detects UNSUPPORTED_CHANGED, workflow.md section 7 reference, apd-setup anti-pattern)
- 3 live (PHP diff → unsupported warning, full mode shows .php file count, TS-only diff → no false unsupported warning)

**Test count 615 → 624 PASS / 0 FAIL.**

**Cross-project verification:**

| Scenario | Pre-fix | Post-fix |
|---|---|---|
| Festico `backend/src` (658 .php) full mode | "Unrecognized backend language" (generic) | Explicit count + "see workflow.md sekcija 7" |
| `--changed` sa PHP diff | "Changes do not affect types" (misleading) | "Detected N changed file(s) in unsupported language(s)" |
| TS-only diff | works | still works (no false positive) |

**Festico cleanup:** the orchestrator's confabulation in Festico CLAUDE.md/workflow.md remains (a per-project artifact, not a framework bug). The user has already documented the limitation in Festico MEMORY.md. A future `apd-setup` re-run with v6.12.2+ should NOT re-confabulate because the anti-pattern in the skill is now explicit. Plus drift detection (v6.10) will flag a stale workflow.md if the orchestrator does not update it.

**Out of scope (deferred to v6.13/v6.14):**

- **PHP parser** — real feature work. Festico exists + v6.13 will likely have PHP/Symfony stack-aware scaffolding, so it can be grouped there. With the current `_lang_summary` helper, adding a PHP parser is incremental (an `extract_php_types` function + a "$BACKEND_LANG = php" branch).
- **Layout flexibility** (feature-folder DTO scan) — still deferred to v6.14+.

## v6.12.1 — 2026-05-28

Hot-fix for the `verify-contracts` script. Bug surfaced 2026-05-28 in BambiProject — `apd contracts <src> <dst>` reported the backend dir as "unknown" even though 100+ `.cs` files exist there.

**Two root causes in the `detect_language()` function:**

1. **`grep -qv X` exit 1 on empty stdin** — on empty input (no files matched by find), `grep -qv` emits a "no matches" exit 1. With `set -euo pipefail` that kills the script before it reaches the `elif` branch.
2. **`grep -q .` SIGPIPE on upstream find** — `grep -q .` reads the first line and exits, which triggers SIGPIPE on the upstream `find`. With `pipefail`, the whole pipe returns non-zero, and the if-branch evaluates as "no match" even when files exist.

**Fix:** capture the filtered output into a variable, check non-empty with `[ -n "$var" ]`. `|| true` on the pipe neutralizes the exit-1-on-no-matches from grep with empty input. Plus parentheses around the find `-o` operator for portability between GNU and BSD find implementations.

```bash
# Before (broken)
if find "$dir" -name "*.ts" -o -name "*.tsx" 2>/dev/null | grep -qv node_modules; then

# After (fixed)
local ts_files
ts_files=$(find "$dir" \( -name "*.ts" -o -name "*.tsx" \) 2>/dev/null | grep -v node_modules 2>/dev/null || true)
if [ -n "$ts_files" ]; then
```

**Verification cross-project:**

| Dir | Pre-fix | Post-fix |
|---|---|---|
| BambiProject `src/` (100+ .cs) | unknown ❌ | **csharp** ✓ |
| BambiProject `apps/backoffice/` | unknown ❌ | **typescript** ✓ |
| Festico `web/` (.ts/.tsx) | typescript (worked) | **typescript** ✓ |
| Empty dir | crash (set -e) | **unknown** ✓ (no crash) |

**Test §75 +5 assertions:** 3 static (no `grep -qv` in code, capture-into-var pattern, parens around find -o) + 2 live (detect_language under set -euo pipefail returns correct language tags on empty/csharp/typescript dirs; empty dir does not crash).

**Test count 610 → 615 PASS / 0 FAIL.**

**Out of scope (separate discussion for v6.13/v6.14):**

The user's second observation — `verify-contracts` full directory mode expects a "one backend types dir ↔ one frontend types dir" layout (e.g. `server/src/types/` ↔ `client/src/types/`). BambiProject has DTOs scattered across feature folders (`src/PLAZMA.Application/Features/**/*.cs`), and the backoffice uses `apps/backoffice/src/features/**/types.ts` plus `src/types/`. That is an architectural assumption, not a BSD grep bug — it requires a design change (multi-dir glob support, feature-folder DTO scan, or a config field `apd:contracts.layout`). For now: `--changed` mode (which uses git diff) is the usable path.

## v6.12.0 — 2026-05-26

Third minor in the v6.10-v7.0 setup+audit chain — **stack-aware template scaffolding**. .NET is the first target stack (BambiProject reference). Realizes the "knowledge encoding system" pillar: on `apd-setup` invocation the orchestrator gets stack-specific agents + skills automatically, instead of 50-100h of manual customization.

**Highlights:**

- **feat(templates/stack/dotnet/):** new directory with templates:
  - **Agents (3):** `backend-api.md.tmpl`, `database.md.tmpl`, `test-guardian.md.tmpl` with `{{SCOPE_BACKEND}}` / `{{SCOPE_INFRA}}` / `{{SCOPE_DOMAIN}}` / `{{SCOPE_TESTS}}` placeholders
  - **Skills (2):** `dotnet-conventions.md` (generic Result pattern, DDD aggregates, thin endpoints, EF Core defaults, FluentValidation pitfalls, customization checklist) + `ef-core-migrations.md` (naming, idempotency, down() requirement, two-chain testing, production deploy discipline, concurrency tokens)
- **feat(pipeline-stack-scaffold):** new bash script — copies templates into `.claude/{agents,skills}/` with placeholder substitution. Additive default (skip-if-exists). Flags: `--list-stacks`, `--dry-run`, `--force` (overwrite + `.bak.preaudit` backup, BambiProject pattern).
- **feat(apd dispatcher):** `apd scaffold` / `apd sc` sub-command. Help text updated.
- **fix(skills/apd-setup/SKILL.md):** new Section 5b "Stack-aware scaffolding (v6.12+)" — orchestrator invokes `pipeline-stack-detect` first, shows results, asks the user YES/NO per stack, runs `pipeline-stack-scaffold <stack> --dry-run` then the actual scaffold. Multi-stack opt-in handling.
- **docs(SPEC.md):** `apd scaffold` entry in the CLI subcommand table.
- **test(test-codex-adapter §74) +22 assertions:** 12 static (script + .NET template dir + 3 agents + 2 skills + placeholder usage + skill reference + flags + dispatcher + apd-setup skill) + 7 live (--list-stacks, scaffold empty project, placeholder substitution, re-run skip, --force overwrite, .bak.preaudit creation, unknown stack error).
- **Test count 588 → 610 PASS / 0 FAIL.**

**Generic vs project-specific extraction:**

Templates are **generic .NET clean-architecture patterns** — NOT PLAZMA-specific (Wolverine, i18n key formats, JWT role conventions). Those are per-project customizations the user adds after scaffolding. The dotnet-conventions skill has an explicit **"Customization Checklist"** section that guides the user through post-scaffold polish.

**Multi-stack support:**

`pipeline-stack-detect` (v6.11) detects all stacks in a monorepo. apd-setup asks per stack. Multi-stack projects like BambiProject (.NET + Node/Vite + KMP/Compose) get a scaffold per stack — the user can opt out of each one individually.

**Additive policy + drift detection synergy:**

- New file → created from template
- Existing file matching baseline → skipped (no churn)
- Existing file stale per template → drift detection (v6.10) flags it separately; the user decides whether to `--force` upgrade with a backup

This combines safety (no destructive surprise) with an upgrade path (drift visible, manual decision).

**v6.10-v7.0 chain progress:**

| Version | Content | Status |
|---|---|---|
| v6.10.0 | apd-audit drift detection + apd-init python merge fix | SHIPPED |
| v6.11.0 | Read-only stack detection mechanism | SHIPPED |
| **v6.12.0** | **Stack-aware template scaffolding (.NET first)** | **SHIPPED 2026-05-26** |
| v6.13 | Second stack (Node/React or PHP/Symfony — TBD after live test) | Backlog |
| v7.0 | max_defects parser removal + finalization | Backlog |

**Backlog open:**

- v6.12 live test in BambiProject — `apd scaffold dotnet --dry-run` to see what would happen (Bambi already has custom agents), then `--force` to compare generated vs existing
- Live test in Festico — can `apd scaffold` leave existing PHP/Symfony agents alone and just skip them (Festico has no .NET, nobody needs scaffold)
- v6.13 next stack — candidates Node/React (Festico Next + Bambi Vite ref) or KMP/Compose (Bambi mobile ref). User decision after v6.12 evaluation.

## v6.11.0 — 2026-05-26

Second minor in the v6.10-v7.0 setup+audit chain — **read-only stack detection mechanism**. Foundation for v6.12 stack-aware template scaffolding (.NET first target, BambiProject reference).

**Highlights:**

- **feat(pipeline-stack-detect):** new bash script detecting 7+ stack categories:
  - **.NET** (high confidence) — `*.sln` or `*.csproj`
  - **PHP/Symfony** (high) — `composer.json` + `symfony.lock` / `config/packages/` / `bin/console`
  - **PHP generic** (medium) — `composer.json` without Symfony markers
  - **Node/Next** (high) — `package.json` + `next.config.{js,ts,mjs}`
  - **Node/Vite** (high) — `package.json` + `vite.config.{js,ts,mjs}`
  - **Node/React** (medium) — `package.json` with `react` in dependencies
  - **Node generic** (low) — `package.json` without framework markers
  - **KMP/Compose** (high) — `settings.gradle.kts` + `composeApp/` or `commonMain/`
  - **Android (KMP-less)** (medium) — `build.gradle.kts` + `AndroidManifest.xml`
  - **Python/Django** (high) — `manage.py` + `requirements.txt`/`pyproject.toml`
  - **Python/FastAPI** (high) — `pyproject.toml`/`requirements.txt` with a `fastapi` dependency
  - **Python generic** (low) — `pyproject.toml`/`requirements.txt` without framework
- **Multi-stack monorepo support** — BambiProject (the only real-world test) detected as **3 stacks simultaneously** (.NET + Node/Vite + KMP/Compose). The script lists each with confidence + signal files.
- **Output modes:** human-readable by default (color-coded confidence column + signals path), `--json` flag for machine-readable output (v6.12 template scaffolding will consume it).
- **Internal dir exclusion:** the scan skips `.claude/`, `.apd/`, `audit/`, `node_modules/`, `vendor/`, `.git/`, `build/`, `dist/`, `target/`, `.next/`, `.gradle/` — focus on real project structure.
- **Exit code:** 0 always by default (informational, not a failure). `--strict` flag exits 1 if zero stacks are detected.
- **feat(apd dispatcher):** `apd stack` (alias `apd st`) sub-command + `apd audit-drift` (alias `apd drift`) sub-command. Help text updated.
- **docs(SPEC.md):** `apd stack` entry in the CLI subcommand table.
- **test(test-codex-adapter §73) +15 assertions:** 11 static (script exists, sources libs, 5 stack signal patterns, --json mode, internal dir exclusion, apd dispatcher wires stack + audit-drift) + 5 live (empty/strict/synthetic .NET/synthetic PHP-Symfony/JSON output).
- **Test count 572 → 588 PASS / 0 FAIL.**

**Live-tested empirical evidence:**

| Project | Detected | Notes |
|---|---|---|
| BambiProject | .NET (high) + Node/Vite (high) + KMP/Compose (high) | Real 3-stack monorepo correctly identified |
| Festico | PHP/Symfony (high) + Node/Next (high) | Real 2-stack project correctly identified |

**Why "v6.11 read-only":** detection is the foundation. v6.12 will consume the JSON output to pick templates on `apd-setup` invocation. Developing it as a separate phase enables empirical iteration — the user can now test detection on their own projects and report false positives/negatives before template scaffolding depends on it.

**Backlog open:**

- v6.11 live test in Bambi/Festico/Test (already ad-hoc validated through the development cycle)
- v6.12 stack-aware template scaffolding — `apd-setup` invokes pipeline-stack-detect, generates agents + skills + conventions per stack (.NET first target)
- v6.13 second stack (TBD after v6.12 evaluation)
- v7.0 max_defects parser removal

## v6.10.0 — 2026-05-26

First minor in the v6.10-v7.0 setup+audit improvement chain (per the project-v6.10-v7.0-setup-audit-roadmap memo). Drift detection in the `apd-audit` skill + a side-fix in `apd-init` that BambiProject + Festico evidence surfaced.

**Empirical trigger:**

BambiProject + Festico both had drift after multiple re-inits:
- `.claude/settings.json` deny patterns: **4/8** (only slash-prefixed; 4 bare-dir variants missing). That is a bypass vector: `mkdir .apd/pipeline` (without a leading slash) is not caught by the guard.
- BambiProject `.claude/.apd-config` `APD_VERSION=6.8.11` vs plugin v6.9.0 (1 minor stale)
- BambiProject `.claude/rules/workflow.md` 4 markers missing (`Implements:`, `rationale gate`, `DEPRECATED`, `unconditional`) — the workflow is from the v6.0/v6.5 era, not refreshed through the v6.7-v6.9 chain

**Root cause — apd-init python merge bug:** the `required_deny` python list in `apd-init` had only 4 patterns (slash-prefixed); the template literal had 8. Re-init reinforced only 4, a fresh init got 8. BambiProject + Festico both went through re-init during the v6.5-v6.9 period and stayed at 4.

**Highlights:**

### A. Pre-req fix: apd-init python merge

- **fix(apd-init):** `required_deny` python list 4 → 8 patterns (added 4 bare-dir variants). Closes the bypass vector + ensures v6.10 drift detection does not flag BambiProject/Festico as stale forever (once apd-setup is re-run).

### B. New script: pipeline-audit-drift

- **feat(pipeline-audit-drift):** new bash script with 3 drift dimensions:
  - settings.json deny patterns vs framework baseline (8 patterns hardcoded, SSOT with apd-init)
  - .apd-config APD_VERSION vs current plugin version (minor/major drift = IMPORTANT, patch-only = INFO)
  - workflow.md content markers (`Implements:`, `rationale gate`, `DEPRECATED`, `unconditional`) — framework workflow.md baseline as reference
- Severity buckets: CRITICAL / IMPORTANT / INFO / CLEAN, with a per-item recovery action
- Framework self-detection: skips drift checks when APD_FRAMEWORK_SELF=true (on the framework repo itself)
- Exit code: 1 if CRITICAL/IMPORTANT, 0 if INFO-only or CLEAN — usable in CI / pre-commit hooks

### C. Skill integration

- **fix(skills/apd-audit/SKILL.md):** new Section 8 "Drift Detection (v6.10+)" — describes the 3 dimensions, output buckets, recovery action (re-run `/apd-setup`)
- **fix(plugins/apd/skills/apd-audit/SKILL.md):** Codex mirror with the same section

### D. SPEC.md + tests

- **docs(SPEC.md):** `apd audit-drift` (v6.10) entry in the CLI subcommand table
- **test(test-codex-adapter §72) +13 assertions:** 8 static (script exists/executable, sources libs, deny patterns baseline, APD_VERSION check, workflow markers check, apd-init python merge lock-in 8 patterns, CC + Codex skill Section 8) + 5 live (clean project → exit 0, missing deny patterns → IMPORTANT, stale APD_VERSION minor → IMPORTANT, stale workflow markers → IMPORTANT, patch-only APD_VERSION → INFO + exit 0)
- **Test count 559 → 572 PASS / 0 FAIL.**

**Migration:**

Projects that re-inited through v6.5-v6.9 (probably most real projects) will see drift in `/apd-audit` until they re-run `/apd-setup` (v6.10+ now writes all 8 patterns). Run `bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/core/pipeline-audit-drift` to see the concrete missing items.

**Roadmap continuity:**

- **v6.11:** Stack detection mechanism (read-only) — detect .NET/PHP/Symfony/Node/Next/KMP signals
- **v6.12:** Stack-aware template scaffolding (.NET first, BambiProject reference)
- **v6.13:** Second stack (TBD after v6.12 evaluation)
- **v7.0:** max_defects parser removal + finalization

A phased approach enables empirical iteration between phases and risk amortization.

## v6.9.0 — 2026-05-24

Minor release — closes the v6.8 chain with three structural interventions:

1. **`adversarial: max_defects=N` field SOFT-DEPRECATED** — to be removed in v7.0. The field continues to function for a graceful transition (verifier gate v6.1 B2 + immutability check v6.3 D both active), but emits a deprecation WARN + INFO log entry on every spec advance where the field is present.
2. **`verify-apd` Section 8 lock-in** in `test-codex-adapter` §71 — closes the blind-spot from issues #10/#11 with static asserts on fixture content.
3. **Pre-bump checklist** codified in `docs/SPEC.md` §24 — a 3-step audit before any bump change that alters guard/gate/hook behavior.

**Why soft-deprecate `max_defects`:** the v6.8 chain (10 patches in 2 days) empirically validated the **rationale gate (v6.7) as sufficient standalone enforcement** for adversarial quality. Per-finding rationale ≥40 chars for dismissed findings + 100%-Do hard-block + bulk-accept rationale validation structurally covers the misuse pattern `max_defects` was meant to prevent. Plus empirical evidence (v6.8 dev cycle, 2026-05-22): tasks with `max_defects=0` ran 26-33 min with a 3-guard BLOCK cascade vs an identical task WITHOUT the field running 13 min clean. `max_defects` became redundant — the worst option is `=0` (forces accept-everything), and realistically any use of the field just serves RLHF anchoring versus the field not existing.

**Highlights:**

### A. max_defects soft deprecation

- **fix(pipeline-advance):** track `MAX_DEFECTS_PRESENT=true/false` before defaulting `CURRENT_MAX="unlimited"`. When the field is explicitly present (`adversarial: max_defects=N` or `=unlimited`), emit a deprecation WARN to stderr with explanation + migration instruction. Plus log an `INFO|orchestrator|max-defects-deprecated|task=X value=N` entry to `guard-audit.log` for telemetry. NO behavior change — verifier gate + immutability check both still active.
- **fix(rules/workflow.md):** §7 SEVERITY GATE reworded with a DEPRECATED v6.9 marker + migration instruction. Drop the polish-mode use-case prescription (the `pipeline_mode: polish` preset is now preferred).
- **fix(skills/apd-brainstorm/SKILL.md) CC + Codex mirror:** "Adversarial budget" section refactored as a DEPRECATED notice — preserves the empirical evidence references (Add contact form / Rate limit / Admin lista comparison) but explicitly says DO NOT WRITE. The "Common BLOCKs" table flags `max_defects-exceeded` + `max_defects-raised-mid-pipeline` as DEPRECATED + adds a migration instruction.
- **fix(templates/codex/AGENTS.md):** mirror the DEPRECATED wording in the step 1 spec card writing instructions.

### B. verify-apd Section 8 lock-in (issues #10 + #11 vector closed)

- **test(test-codex-adapter §71):** static asserts on fixture content in `verify-apd` Section 8 — `.brainstorm-marker` pre-write for APD-VERIFY-TEST + APD-VERIFY-OPT-OUT, `implementation-plan.md` with `**Implements:** R1` for both synthetic tasks, a synthetic `.adversarial-rationale.md` matching the ADVERSARIAL summary. **If someone next changes a gate in pipeline-advance and forgets to update verify-apd, test-codex-adapter will fail before push** — preventive lock-in vs a reactive hot-fix patch (like #12 + #13 that this avoids).

### C. Pre-bump checklist in SPEC.md §24

- **docs(SPEC.md):** new section §24 with **MANDATORY** 3-step audit commands (grep for pipeline-advance callsites + grep for synthetic fixtures + test-codex-adapter run). Plus deprecation policy: minor for warn, major for removal, 2-version graceful window.

### Tests

- **§71 (15 assertions):** 7 static for max_defects deprecation (markers + parser logic + WARN message + skill content) + 4 live behavioural (warn emits, INFO logs, no warn when field absent, verifier gate STILL active in v6.9) + 4 static for verify-apd Section 8 lock-in.
- **§63 Static I updated** for the generalized `DO NOT write adversarial: max_defects` wording (without `=0` specifically, since the whole field is deprecated).
- **Test count 544 → 559 PASS / 0 FAIL.**

**Migration (v6.9 → v7.0 transition):**

| Project state | What to do |
|---|---|
| Spec has no `max_defects` field | Nothing — already on v7.0 baseline |
| Spec has `adversarial: max_defects=N` (anywhere N≥0) | Remove the line. The rationale gate covers misuse structurally. |
| Spec has `adversarial: max_defects=unlimited` | Remove the line — explicit unlimited = default |
| `pipeline_mode: polish` projects | No change — polish preset is preferred for hotfixes, drops adversarial entirely |

v6.9 does NOT change behavior — it only emits a warn. v7.0 will remove the parser branches in `pipeline-advance` (lines ~311-345 immutability check + lines ~850-870 verifier severity gate) and the log entries.

**Backlog open after v6.9:**

- v6.9 live test in BambiProject — verify (a) WARN emit on max_defects use, (b) INFO entry in guard-audit, (c) field still works (verifier gate active).
- Phase 2 maxTurns calibration — 1-2 weeks of aggregated telemetry → workflow.md defaults update.
- v6.9.x patch chain if the live test reveals skill content gaps around skip-brainstorm wording (we now reference "max_defects=unlimited" in the canonical reason — needs an update).
- v7.0 plan — `max_defects` parser removal + BREAKING CHANGES section + test-codex-adapter §71 (a) part assertions deleted.

## v6.8.13 — 2026-05-23

Second hot-fix within the same hour, same class of problem as #10 (now #11) — the `apd verify` E2E test trips on a second gate. v6.8.12 fixed the brainstorm-marker gate in verify-apd Section 8, but the plan-spec consistency gate (v6.8.0) remained exposed because Section 8 writes a minimal plan (`echo "## Plan: APD-VERIFY-TEST" > implementation-plan.md`) without an `**Implements:**` header. After v6.8.12 the spec step passed but the builder blocks with `BLOCKED: Spec R1 not implemented by any plan section` → 12 cascading FAILs.

**Highlights:**

- **fix(verify-apd Section 8): pre-write a valid implementation-plan.md** for both synthetic task names (`APD-VERIFY-TEST` + `APD-VERIFY-OPT-OUT`). The format has `### Section 1 — verification stub` + `**Implements:** R1`, which satisfies the verify-plan-spec parser's bidirectional check (forward: R1 in Implements exists in spec; reverse: spec R1 covered in plan; symmetric: the single section has an Implements header).
- **Zero impact on test count.** `test-codex-adapter` stays 544/0 (a separate E2E surface).
- **Issue #11 closed** with the fix commit.

**Structural lesson (same pattern twice in the same hour):**

`apd verify` is structurally a blind-spot for all gate-affecting changes. The current workflow is: edit guard → update test-codex-adapter → ship. Now obvious: edit guard → update test-codex-adapter → **review every `pipeline-advance` callsite in `plugins/apd/bin/`** → ship. Pre-bump audit command:

```bash
grep -rn 'pipeline-advance\|pipeline-gate' plugins/apd/bin/
```

Next time we need to change a gate that affects `spec`/`builder`/`reviewer`/`verifier` advance, we must not only update the test-codex-adapter fixtures but also walk through verify-apd Section 8 manually. It may be worth considering integrating `apd verify` into the `test-codex-adapter` family or adding a pre-bump checklist to workflow.md.

## v6.8.12 — 2026-05-23

Hot-fix for a v6.8.11 oversight ([#10](https://github.com/zstevovich/claude-apd/issues/10)). v6.8.11 made the `brainstorm-marker` gate unconditional, but only the `test-codex-adapter` fixtures were covered. The other E2E test script — `verify-apd` (run via `apd verify`) — has a Section 8 that drives a synthetic spec advance without a marker. After the v6.8.11 deploy, `apd verify` on a clean project or after `apd pipeline reset` produces 13 cascading FAILs starting from `BLOCKED: Brainstorm marker missing for spec advance (1 R-criteria declared)`.

**Highlights:**

- **fix(verify-apd Section 8): pre-write a canonical `.brainstorm-marker`** for both synthetic task names (`APD-VERIFY-TEST` in the main flow, `APD-VERIFY-OPT-OUT` in the adversarial opt-out test). Format identical to what the skill writes on exit (`<task>|<iso-utc-timestamp>`). The existing `pipeline-advance reset` trap in Section 8 already deletes the marker — no new cleanup needed.
- **Zero impact on test count.** `test-codex-adapter` stays 544/0 — `verify-apd` Section 8 is not unit-tested in the test-codex-adapter family (a separate E2E surface).

**Issue analysis:**

The issue #10 diagnosis is correct: `pipeline-advance:230-265` enforces the marker for every spec advance with R-criteria; verify-apd's synthetic spec declares R1, trips the gate, exits non-zero, and all downstream tests in Section 8 cascade because spec.done was never written. Sections 1-7 + 9-10 pass clean (103 PASS) — only Section 8 affected.

**Fix choice:** marker write instead of the `--skip-brainstorm '<reason>'` opt-out (both valid per the issue). The marker write simulates the "orchestrator loads the skill" happy-path — representative of what the E2E test should cover. `--skip-brainstorm` would bypass the gate entirely, which is NOT what verify-apd Section 8 tests.

**Migration:** zero project-side impact. `apd verify` now runs clean through Section 8 on v6.8.12. Projects that ran `apd verify` on v6.8.11 and saw FAILs — re-run after the plugin update.

## v6.8.11 — 2026-05-23

Twelfth patch in the v6.8 chain — structural intervention on the entry discipline layer. Drop the R-count > 2 carve-out from the `brainstorm-marker` hard gate. The v6.8.5 gate was designed with an `R > 2` threshold as a "smart-friction" carve-out for trivial tasks; BambiProject 2026-05-23 evidence showed the threshold is gameable — the orchestrator atomizes non-trivial work into 2 R-criteria specifically to bypass the gate. v6.8.11 forces a brainstorm load on every spec advance regardless of declared R-count. Opt-out via `--skip-brainstorm '<reason>'` (v6.8.8 friction) preserved.

**Empirical trigger (BambiProject 2026-05-23, both on the v6.8.10 plugin):**

| Task | Declared R | Duration | Adversarial | Brainstorm gate |
|---|---|---|---|---|
| Photo Bill CTA | 2/2 | 32m 22s | N/A | not triggered |
| MS.4 Android Barkoder still-image | 2/2 | 40m 25s | N/A | not triggered |

Both pipelines really ran like a 4-6 R cycle (multi-layer mobile + tests + 6/3 files with 72% builder→reviewer iteration time); both should have routed through `/apd-brainstorm`. Plus secondary bypass evidence: the orchestrator tried `rm -rf .apd/pipeline && mkdir -p .apd/pipeline` to wipe the v6.3 max_defects immutability ledger + reset the audit trail (the `PROTECTED_PIPELINE` substring match misses the bare-dir form without a trailing slash).

**Strategic insight (user 2026-05-23):** APD enforcement layers (guards + rationale gates + plan-spec consistency + brainstorm marker) make the END quality of the cycle robust — the orchestrator hits BLOCKs, retries, converges to a clean commit. Quality is not the open problem. The open problem is the **resource cost** of indiscipline at entry. The cost of one BLOCK loop cycle (plan-spec + max_defects raise + rationale-missing + rm -rf attempt + reset cascade) is 30-100K tokens. The cost of one brainstorm load is 3-5K tokens. A per-task brainstorm load is ~10× cheaper than one BLOCK loop cycle that undisciplined entry triggers downstream.

**Highlights:**

- **fix(pipeline-advance): brainstorm-marker gate UNCONDITIONAL.** Drop `[ "$CRITERIA_COUNT" -gt 2 ]` from both checks (marker presence + `--skip-brainstorm` reason validation). The gate fires on every spec advance regardless of R-count. BLOCK message reworded: drop the "non-trivial task" branding and the "Trivial tasks (≤2 R-criteria) skip this gate automatically." line. Adds the BambiProject 2026-05-23 R-atomization empirical reference (30-40 min with adversarial N/A vs 10-15 min for brainstorm-loaded equivalents).
- **fix(skills/apd-brainstorm/SKILL.md) CC + Codex mirror: "Default: load on every new task" paragraph** at the top of the "When to use / When to skip" section. "Skip when" reworded to "Skip only when" + canonical skip cases enumerated (genuine 1:1 mirror of a just-completed task, single-line bug fix with one R-criterion, hotfix with pre-aligned scope).
- **fix(rules/workflow.md step 1 + templates/codex/AGENTS.md step 0): MANDATORY load wording reword** — "unconditional, every new task" instead of a conditional `>2 R-criteria` list. Plus BambiProject MS.4 + Photo Bill CTA empirical reference.
- **test(bin/core/test-codex-adapter):**
    - New `_v6811_marker DIR TASK` helper at the top of the file — writes a canonical `.brainstorm-marker` for fixtures that drive `pipeline-advance spec` without intending to test the gate. 11 fixtures updated across §31/§32/§38/§42/§43/§45/§51/§52 + the Python subdir MCP test.
    - §64 Live L flipped: was "trivial R≤2 bypasses gate", now "trivial R≤2 ALSO BLOCKs without marker per v6.8.11".
    - §64 Static E updated to recognize BambiProject MS.4 / Photo Bill CTA evidence references alongside the existing Bambi Cycle E.
    - **New §70 (11 assertions):** 7 static (gate condition no longer R>2, v6.8.11 comment marker, `--skip-brainstorm` reason unconditional, workflow.md unconditional wording, CC + Codex SKILL.md unconditional wording, AGENTS.md unconditional wording) + 4 live (R=1 no marker → BLOCK, R=1 + marker → passes, R=2 + `--skip-brainstorm` + reason → passes opt-out preserved, R=2 + `--skip-brainstorm` without reason → BLOCK).
- **Test count 533 → 544 PASS / 0 FAIL** (+11 new in §70, plus 1 modified in §64 Live L).
- **Migration:** projects that operated under the R≤2 carve-out will see a new BLOCK on the first spec advance per task. Recovery is the documented opt-out: load the `/apd-brainstorm` skill (recommended) OR `--skip-brainstorm '<concrete reason>'` (canonical use cases: 1:1 mirror, single-line bug fix, pre-aligned hotfix).

**Strategic pivot:** the previously-noted defensive guard for `rm -rf .apd/pipeline` is DEFERRED in favor of α (unconditional brainstorm load). Hypothesis: if the orchestrator knows the pipeline from the start, the nuclear-wipe escape valve becomes unnecessary. Re-evaluate after the BambiProject v6.8.11 live test.

**Twelve-patch v6.8 chain (retrospective):**

| Patch | Layer | Trigger |
|---|---|---|
| v6.8.0-1 | Guard | Discovery |
| v6.8.2 | Observability | Admin signals |
| v6.8.3 | UX | Rate limit |
| v6.8.4 | Education | CSRF ignored |
| v6.8.5 | Enforcement | "Without brainstorm" — R>2 gate |
| v6.8.6 | Polish | CSRF UX |
| v6.8.7 | Skill content | Soft-delete gaps |
| v6.8.8 | Override friction | Bambi Cycle E bypass |
| v6.8.9 | Telemetry polish | Product sort_order bug |
| v6.8.10 | MaxTurns telemetry | User-observed structural |
| **v6.8.11** | **Entry discipline** | **R-atomization bypass** |

## v6.8.10 — 2026-05-22

Eleventh same-day patch — a telemetry surface for empirical maxTurns calibration. User-observed structural problem: the current maxTurns values (60 builders / 80 reviewers from workflow.md) are set intuitively, not empirically calibrated. Empirical evidence: the Bambi v6.8 era (last 7 days) had 15 `mobile` rapid re-dispatch events (gap <120s = proxy for maxTurn exhaust). v6.8.10 adds read-only telemetry that calibrates per-agent values empirically. No behavior change — pure observability. Tests: 528 → 533 (+5 in §69).

- **feat(bin/core/pipeline-report-maxturns): new script for maxTurns telemetry.** Parses `agent-history.log`, computes per agent_type:
    - Total starts in the last N days (default 30)
    - Rapid re-dispatch count (gap <RAPID_THRESHOLD seconds, default 120)
    - Average gap between stop and the next start of the same agent_type
  Outputs a formatted table with color-coded counts:
    - red+bold: ≥5 rapid re-dispatches (likely exhaust, suggested action emitted)
    - yellow: 2-4 rapid re-dispatches (marginal)
    - dim: 1 rapid re-dispatch (incident)
    - green: 0 rapid re-dispatches (clean)
  Plus a suggested action per agent_type — reads the current `maxTurns` from `.claude/agents/<agent>.md` frontmatter and suggests raising +20 turns:
    ```
    + mobile — current maxTurns=60 → consider raising to 80
      Edit: .claude/agents/mobile.md frontmatter
    ```
- **feat(bin/core/pipeline-report): maxturns sub-command dispatcher.** `apd report maxturns` (or `apd report mt`) → exec pipeline-report-maxturns. Plus `--days N` and `--threshold-seconds S` overrides passed through the dispatcher.
- **docs(bin/apd): CLI help update.** Help comment adds a `report maxturns` entry for visibility.
- **Empirical baseline (Bambi v6.8 era, last 30 days):**
    | Agent | Starts | Rapid re-dispatch | Suggested |
    |---|---|---|---|
    | mobile | 295 | **15** | 60 → 80 |
    | devops | 169 | **7** | 60 → 80 |
    | code-reviewer | 413 | **5** | 80 → 100 |
    | backend-api | 265 | 2 | (marginal) |
    | testing/database/backoffice/adversarial | — | 0 | (clean) |
- **Tests:** `test-codex-adapter` §69 adds 5 assertions: script exists/executable, dispatcher case present, rapid counter logic present, maxTurns frontmatter parse present, live synthetic fixture with mobile re-dispatch returns expected output. Test count 528 → 533.
- **Migration:** zero project-side impact. Pure telemetry — read-only surface. User-driven calibration: after reviewing `apd report maxturns`, manually edit `.claude/agents/<name>.md` frontmatter with the suggested maxTurns value.
- **Strategic context:** v6.8.10 is a **Phase 1 telemetry-first** step toward eventual per-agent maxTurns calibration. Phase 2 (next 1-2 weeks of cross-project usage) — calibrate defaults in workflow.md based on aggregated telemetry. Phase 3 (potential v6.9+) — adaptive scaling per task complexity (R-criteria count → suggested adjustment).

## v6.8.9 — 2026-05-22

Tenth same-day patch — trivial session-log bug fix discovered in the Bambi Product sort_order task post-mortem. Pre-v6.8.9: `pipeline-advance reset` loops through `guard-audit.log` and counts ALL entries without filtering by the `log_type` field. INFO entries (`brainstorm-skipped` from v6.8.8) were counted as "blocks" → false positive `Problems: Guard blocks detected` for a task that was actually clean. Bambi Product sort_order (19m 12s, ZERO BLOCK, 1 INFO entry with a brainstorm skip reason) exposed the bug — session-log reported "Guard blocks detected" even though the pipeline passed correctly. Tests: 524 → 528 (+4 in §68).

- **fix(pipeline-advance reset): case-based `log_type` filter for guard-audit counting.**
    ```bash
    case "$log_type" in
        BLOCK)
            BLOCKS=$((BLOCKS + 1))
            BLOCK_REASONS="${BLOCK_REASONS}${log_reason}\n"
            ;;
        INFO)
            SKIP_EVENTS=$((SKIP_EVENTS + 1))
            SKIP_REASONS="${SKIP_REASONS}${log_reason}\n"
            ;;
        *) ;;  # PERMISSION_DENIED and others — ignored in summary
    esac
    ```
- **feat(pipeline-advance reset): SKIP_SUMMARY for INFO events.** After the BLOCKS counter logic, a parallel `SKIP_SUMMARY` builds the string "<N> info events: <top-3 reasons>". Visible in the session-log as a **separate** line (not as a false-positive guard block).
- **feat(session-log entry): conditional `**Skip events:**` line.** Added only when `SKIP_SUMMARY` is non-empty (no noise for tasks without INFO events; explicit visibility when present). Format example:
    ```
    **Guardrail that helped:** N/A
    **Skip events:** 1 info events: brainstorm-skipped (1x)
    ```
    Plus the `Problems:` field stays "No problems" (because GUARD_SUMMARY="N/A" — the BLOCK counter was not incremented).
- **Test §68 (4 static assertions):** case-based filter, SKIP_SUMMARY variable, conditional Skip events line, BLOCK/INFO counter increments in separate branches.
- **Test count 524 → 528 PASS / 0 FAIL.**
- **Migration:** zero project-side impact. Pre-v6.8.9 session-log entries have a "false positive" `Problems: Guard blocks detected` for tasks with only INFO events (e.g. brainstorm-skipped) — but those entries already exist + cannot be retroactively fixed. New entries after the v6.8.9 install show the correct semantics.

## v6.8.8 — 2026-05-22

Ninth same-day patch — structurally closing the `--skip-brainstorm` escape valve. Live evidence from the Bambi Cycle E task (2026-05-22, 3h cascade vs Test 20min clean the same day + Export CSV 15m clean): the orchestrator hit the brainstorm-marker BLOCK but bypassed it with the `--skip-brainstorm` flag. Self-reflective signal from the orchestrator: "the skill would be ceremony over an already-achieved alignment" but "the skill probably also checks things I miss... had I loaded it, I might have avoided the later max_defects problem". Tension: the skill content "When to skip" gently allows skipping for pre-aligned design, the hard gate forces a load — the orchestrator resolves it via a cheap override + scope-only rationalization. v6.8.8 closes it structurally: `--skip-brainstorm` requires an explicit reason argument. Tests: 515 → 524 (+9 in §67).

- **fix(pipeline-advance): `--skip-brainstorm` requires reason argument.** Pre-v6.8.8: `--skip-brainstorm` was a boolean flag without an argument — a cheap override the orchestrator uses automatically. v6.8.8: an argument MUST follow the flag. Without a reason → BLOCK with a specific message requiring:
    1. Scope alignment (user approved design informally)
    2. APD config clarity (max_defects + plan **Implements:** on EVERY section + rationale .md format)
  Plus a log entry in guard-audit.log: `INFO|orchestrator|brainstorm-skipped|task=X reason=Y` (sanitized + truncated to 200 chars).
- **fix(pipeline-advance): brainstorm-marker BLOCK message reorganized.** Pre-v6.8.8: "Two ways forward (a) Load skill (b) Override". v6.8.8: "(a) **RECOMMENDED** — Load skill / (b) Override — **ONLY IF** scope IS pre-aligned AND APD config decisions ARE explicit, requires concrete reason". Plus an explicit empirical reference: "Bambi Cycle E 3h cascade pattern" as learning material. Plus an EXAMPLE reason with concrete text.
- **fix(skills/apd-brainstorm/SKILL.md, CC + Codex): "When to skip" TWO-PART CHECK rewording.**
    1. Scope is aligned (task specified OR user approved informally)
    2. APD config decisions are explicit (4 sub-questions: budget, plan format, rationale format, BLOCK recovery)
  
  Both parts MUST be YES for legitimate skipping. **"If you cannot confirm BOTH — DO NOT skip"** with an empirical evidence reference (Bambi Cycle E). The override flag explicitly requires a reason mentioning BOTH parts.
- **fix(SKILL.md Step 5 marker write section): Override description update.** From boolean flag → reason argument. Format example + audit log mention.
- **Strategic note:** v6.8.8 is NOT forcing a skill load absolutely — the orchestrator can still legitimately skip when both conditions are met. The goal is **friction proportional to risk**: mental friction (writing an explicit reason) → the orchestrator re-examines "do I really need to skip" → if yes, it writes an audit-traceable rationale. This is analogous to the v6.7 rationale gate for adversarial dismissal — the "force structured rationale" pattern generalized to the skip override.
- **Tests:** `test-codex-adapter` §67 adds 9 assertions: SKIP_BRAINSTORM_REASON parser + missing-reason BLOCK + brainstorm-skipped audit log + RECOMMENDED on (a) + empirical reference + TWO-PART CHECK in CC + Codex skills + live BLOCK without reason + live PASS with reason. Plus §60 Live J updated for the new syntax (test fixture migration). Test count 515 → 524.
- **Migration:** projects that use `--skip-brainstorm` (without an argument) in scripts will get a BLOCK on the next task. Quick fix — add a reason argument: `--skip-brainstorm "<concrete reason>"`. The Bambi orchestrator's self-reflective lesson is a literal template for the reason content.

## v6.8.7 — 2026-05-22

Eighth same-day patch — skill content polish for 2 signals from the Soft-delete task post-mortem (live evidence 2026-05-22 15:04-15:30). Both signals are from the skill education layer (v6.8.4) — the orchestrator learned parts of the skill but not all of it. v6.8.7 fills those education gaps. Tests: 507 → 515 (+8 in §66).

- **(A) fix(apd-brainstorm): Step 4 design summary template forces explicit Risks + Rollback fields.** Pre-v6.8.7 the template had Goal / Scope / Approach / Files / Mode / Adversarial budget — but NOT Risks / Rollback. In the Soft-delete spec the orchestrator omitted Risks (3 legitimate risks: concurrent delete+read race, migration over an existing table, CSRF reuse) and Rollback (revert commit + optional DROP COLUMN). v6.8.7 template explicitly adds the fields + warning: "Risks + Rollback are NOT optional for tasks with DB migration / new public endpoint / auth changes / external API". Trivial tasks may say "minimal" or "revert commit", but without explicit documentation the adversarial reviewer cannot catch the gap.
- **(B) fix(apd-brainstorm): Downstream gates section explicit "NO RESERVED NAMES" rule + Agents/Notes in the format example.** Soft-delete plan empirical evidence: the orchestrator learned the `**Implements:** none` pattern for file-list sections (Files to modify, Files to create) but forgot it for Agents/Notes — asymmetric learning triggered a plan-spec-consistency BLOCK on 2 missing headers (issues=2). v6.8.7 format example adds Agents + Notes with an explicit comment "← NO RESERVED NAMES — Agents needs **Implements:** too". Plus explicit warning prose: "**EVERY `### Section` MUST have `**Implements:**` header — NO EXCEPTIONS.** The rule is uniform across functional sections (Backend, Frontend, Database, Tests) AND scaffolding sections."
- **(C) fix(workflow.md §3c): NO RESERVED NAMES rule explicit in the format example + Rules bullet.** Bullet updated from "set to `none` for scaffolding sections (file lists, agents, notes, documentation)" to an explicit "NO RESERVED NAMES" warning + concrete empirical evidence reference + "Treat EVERY `###` section the same way: declare R-ids OR `none`."
- **(D) fix(plugins/apd/skills/apd-brainstorm/SKILL.md): Codex mirror parity.** Step 4 Risks/Rollback warning + Downstream gates NO RESERVED NAMES rule.
- **Empirical baseline for the v6.8.7 trigger (Soft-delete task, 2026-05-22):** 20m 58s pipeline, 5:1:4 ADVERSARIAL (real adversarial work), 3 BLOCKs (all intended) — brainstorm-marker + plan-spec-consistency (issues=2 Agents/Notes) + rationale-100pct-orch-dismiss. v6.8.7 goal: reduce the 2 missing Implements in the plan-spec issues count → 0 in the next task.
- **Tests:** `test-codex-adapter` §66 adds 8 static assertions: CC skill Step 4 template forces Risks + Rollback, CC skill non-optional warning, CC skill NO RESERVED NAMES rule, CC skill Agents/Notes Implements in the format example, Codex mirror non-optional warning, Codex mirror NO RESERVED NAMES, workflow.md NO RESERVED NAMES, workflow.md scaffolding list. Test count 507 → 515.
- **Migration:** zero project-side impact. Pure skill/workflow content polish.

## v6.8.6 — 2026-05-22

Seventh same-day patch — UX polish for 2 bugs from the CSRF live test post-mortem (user observation). Both bugs are technically **intended behavior** but with confusing BLOCK messages. v6.8.6 does not change logic, only refines messages. Tests: 502 → 507 (+5 in §65).

- **fix(track-agent): clearer message for the adversarial-out-of-order BLOCK.** Pre-v6.8.6: the orchestrator dispatches adversarial-reviewer before reviewer.done → SubagentStart hook exit 2 + the start event is NOT written to .agents (intentional — a fake start must not be logged if the gate blocks). The user interpreted it as a bug ("the hook didn't record the first start event") because the BLOCK message didn't warn them explicitly. Now the message includes:
    - "NOTE: This SubagentStart was rejected — the start event is NOT recorded in .agents."
    - "After running 'apd pipeline reviewer', re-dispatch adversarial-reviewer (fresh agent dispatch, not retry)."
    The user knows exactly what to do.
- **fix(guard-pipeline-state): typo detection + correction hint.** Pre-v6.8.6: the orchestrator writes `.adversarial-rationale` (without the `.md` extension) → the guard blocks with a generic "Direct write to pipeline state file: .adversarial-rationale". The user had to ask: "maybe it needs .md?". The v6.8.6 case statement detects 3 typo cases:
    - `.adversarial-rationale` → "Did you mean '.adversarial-rationale.md'?"
    - `spec-card` → "Did you mean 'spec-card.md'?"
    - `implementation-plan` → "Did you mean 'implementation-plan.md'?"
    All three standard pipeline state markdown files with extension-typo potential get an explicit correction suggestion.
- **Live evidence (CSRF task, 2026-05-22):** the orchestrator hit both scenarios — re-dispatch adversarial after the first BLOCK + pipeline-state-direct-write BLOCK on `.adversarial-rationale`. Both had OK gate semantics but confused the orchestrator + cost minutes in recovery. v6.8.6 goal: <5s recovery per typo.
- **Tests:** `test-codex-adapter` §65 adds 5 assertions: track-agent "NOT recorded" note + re-dispatch instruction, guard-pipeline-state typo case + "Did you mean" hint, live BLOCK output with typo-bait input. Test count 502 → 507.
- **Migration:** zero impact. Pure message polish.

## v6.8.5 — 2026-05-22

Sixth same-day patch — hard gate that **forces a `/apd-brainstorm` skill load** before a non-trivial spec advance. The v6.8.4 educational layer is passive (workflow.md MANDATORY guidance is textual), so the orchestrator skipped it. Live evidence from the Test CSRF task (2026-05-22): 4 BLOCKs in 7 minutes (plan-spec-consistency + adversarial-before-reviewer × 2 + pipeline-state-direct-write) despite the v6.8.0-4 chain. The user's thesis: "without the brainstorm skill we won't make the orchestrator respect discipline" — empirically confirmed. v6.8.5 transforms the skill load from a "recommendation" into a "mandatory checkpoint" via a marker file. Tests: 489 → 502 (+13 in §64).

- **feat(pipeline-advance): brainstorm-marker hard gate.** Before `create_done "spec"` in the spec branch, a new check: if the R-criteria count in spec-card.md > 2 and `.apd/pipeline/.brainstorm-marker` does not exist (or the task name inside it does not match), BLOCK with an explicit instruction "Load /apd-brainstorm skill first". `log_block "brainstorm-marker-missing"` to guard-audit.log.
- **feat(pipeline-advance): `--skip-brainstorm` override flag.** Escape valve for experimental / pre-specified tasks. `bash .claude/bin/apd pipeline spec --skip-brainstorm "Task name"`. Flag parsed from `$@` (can be before or after the task name).
- **feat(apd-brainstorm SKILL.md): Step 5 instructs marker write.** The skill exit action now includes:
    ```bash
    printf '%s|%s\n' "Task name" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > .apd/pipeline/.brainstorm-marker
    bash .claude/bin/apd pipeline spec "Task name"
    ```
    Plus an explicit explanation of the gate and the override flag. Codex mirror identical (with the `apd:apd_advance_pipeline` MCP tool path).
- **fix(guard-pipeline-state): allowlist `.brainstorm-marker`.** Without this allowlist, the skill would hit a BLOCK when it tries to write the marker. Header comment + case statement updated.
- **fix(guard-file-edit, Codex): allowlist `.brainstorm-marker`.** AUTHORING_ALLOWLIST gets a new entry. The Codex orchestrator can write the marker via apply_patch / Edit / Write.
- **fix(guard-bash-scope): allow brainstorm-marker bash redirect.** The skill uses `printf > .apd/pipeline/.brainstorm-marker` — without this exception it would hit the "Bash redirect to protected pipeline state directory" BLOCK.
- **fix(pipeline-advance reset cleanup): wipe `.brainstorm-marker`.** Both reset paths (spec re-advance soft cleanup + explicit `pipeline-advance reset`) get `.brainstorm-marker` in the rm -f list. The next task starts fresh.
- **Trivial tasks bypass automatically.** R-count ≤ 2 (hotfix/polish) does not trigger the gate — the orchestrator is not forced to load the skill for 1-2 R-criterion tasks. Smart-friction: friction only where the cascade BLOCK pattern was observed.
- **Empirical baseline from the v6.8 dev cycle (5 tasks in Test):**
    | Task | Duration | T:A:D | BLOCKs | brainstorm load |
    |---|---|---|---|---|
    | Landing page (v6.6 baseline) | 8m 49s | 5:0:5 | 0 | n/a |
    | Add contact form | 33 min | 0:0:0 (anticipatory) | 3 cascade | NO |
    | Admin lista | 13m 25s | 10:1:9 | 2 rationale | NO |
    | Rate limit | 26m 11s | 8:8:0 (forced accept) | 3 | NO |
    | **CSRF protection (v6.8.4)** | **N/A (in progress)** | **N/A** | **4 BLOCKs in 7min** | **NO** |
  Pattern: the orchestrator skipped the skill load on all 4 tasks despite the workflow.md hint + v6.8.4 SKILL update. The v6.8.5 hard gate is realistically the only structural fix.
- **Tests:** `test-codex-adapter` §64 adds 13 assertions: BRAINSTORM_MARKER + SKIP_BRAINSTORM static parsers, reset cleanup, guard-pipeline-state + guard-file-edit + guard-bash-scope allowlists, CC + Codex SKILL.md marker instruction, live R>2 without marker → BLOCK, --skip-brainstorm override works, matching marker → spec advance passes, R≤2 trivial bypass automatic, reset wipes marker. Test count 489 → 502.
- **Migration:** projects that upgrade v6.8.4 → v6.8.5 and continue an active pipeline: if the next task has >2 R-criteria, the orchestrator gets a BLOCK with an instruction. Quick fix — load the `/apd-brainstorm` skill, walk through it (the skill writes the marker), then `apd pipeline spec`. Trivial tasks (1-2 R) do not break.

## v6.8.4 — 2026-05-22

Fifth same-day patch — structural intervention on the educational surface, not the guard layer. **Root cause spotted by user observation:** `apd-brainstorm` SKILL.md still prescribes `max_defects=0` in the Adversarial budget table despite the v6.8.1 workflow §0b update. The orchestrator reading the skill therefore still learns pre-v6.8.1 guidance, which triggered cascade BLOCKs in Add contact form (33 min, 3 cascade BLOCKs) and Rate limit (26 min, T=8:A=8:D=0 forced accept all). v6.8.4 transforms apd-brainstorm from a "vague-task clarifier" into an **"APD pipeline tutor"** — the orchestrator gets education about the gates BEFORE writing the spec. Plus workflow.md/AGENTS.md explicit MANDATORY load skill for non-trivial tasks. Tests: 480 → 489 (+9 in §63).

- **fix(skills/apd-brainstorm/SKILL.md): drop the pre-v6.8.1 max_defects=0 prescription.** Pre-v6.8.4 table:
    ```
    | 1–2 (hotfix)     | max_defects=unlimited |
    | 3–4 (real task)  | max_defects=0         |
    | 5+ (complex)     | max_defects=0 or N    |
    ```
    Post-v6.8.4:
    ```
    | 1–7 R (default — almost all tasks) | omit field (= unlimited) |
    | polish-mode (1-2 R hotfix)         | pipeline_mode: polish    |
    | Power-user explicit budget         | max_defects=N (rare)     |
    ```
    Plus explicit "DO NOT write max_defects=0 for standard tasks" with empirical evidence from the v6.8 dev cycle.
- **feat(skills/apd-brainstorm/SKILL.md): new section "Downstream gates the spec triggers".** Educates the orchestrator BEFORE writing the spec about:
    - Implementation plan format with `**Implements:** R1, R3` headers per section + scaffolding `none`
    - Plan-spec gate bidirectional check + v6.8.1 strict default
    - Adversarial rationale file format (Finding/Severity/Status/Rationale) + v7.1 + v7.6 BLOCK consequences
- **feat(skills/apd-brainstorm/SKILL.md): new section "Common BLOCKs + recovery".** Table with 7 BLOCK reasons (plan-spec-consistency, max_defects-exceeded, max_defects-raised-mid-pipeline, rationale-missing, rationale-100pct-orch-dismiss, max_builder_cycles-exceeded, adversarial-before-reviewer) + a concrete quick fix per case.
- **fix(plugins/apd/skills/apd-brainstorm/SKILL.md): Codex mirror update.** Similar structure, terser (the Codex skill is generally more concise). Drop the prescription + add the gates + BLOCKs sections.
- **fix(workflow.md step 1): MANDATORY load /apd-brainstorm BEFORE writing spec-card.md** when ANY:
    - Task is vague/broad/improve X style
    - Task has >2 R-criteria
    - Task introduces a DB migration or security surface
    - User has not pre-specified files/R-criteria/budget
  Plus an explicit description "Skill is the APD pipeline tutor (v6.8.4+)" + empirical reference.
- **fix(templates/codex/AGENTS.md): step 0 MANDATORY brainstorm load** + step 1 (Write spec card) gets a "DO NOT write `adversarial: max_defects=0`" explicit warning with rationale.
- **Empirical baseline (4 tasks in the v6.8 dev cycle):**
    | Task | Duration | T:A:D | BLOCK-ovi | `max_defects` field |
    |---|---|---|---|---|
    | Landing page (v6.6 baseline) | 8m 49s | 5:0:5 | 0 | unlimited (no field) |
    | Add contact form | **33 min** | 0:0:0 (anticipatory) | 3 cascade | **=0 explicit** |
    | Admin lista | 13m 25s | 10:1:9 | 2 rationale | unlimited (no field) |
    | Rate limit | **26m 11s** | **8:8:0** (forced accept) | 3 | **=0 explicit** |
  Pattern: max_defects=0 = 2x-4x slower vs no field. The apd-brainstorm SKILL was the cause of writing max_defects=0.
- **Tests:** `test-codex-adapter` §63 adds 9 static assertions: CC skill drops the 3-4 prescription, default omit-field, Downstream gates section, Common BLOCKs section, Codex mirror parity (drop + sections), workflow.md MANDATORY load, AGENTS.md step 0 MANDATORY, AGENTS.md spec-card warning. Test count 480 → 489.
- **Migration:** zero project-side impact. Skill content + workflow guidance polish.

## v6.8.3 — 2026-05-22

Same-day usability patch responding to v6.8.2 live evidence (Test 2nd task): `verify-plan-spec` log_block works but the workflow.md MANDATORY/Sanity preventive guidance did NOT help — the orchestrator again forgot the `**Implements:**` headers (2× plan-spec-consistency BLOCK 17s apart) and again forgot `.adversarial-rationale.md` (rationale-missing + 100pct-orch-dismiss BLOCK pair). Root cause: workflow.md is a context document read at SessionStart, not actively in the tool-call context during plan/rationale writing. Tests: 476 → 480 (+4 in §62).

- **fix(pipeline-advance): actionable BLOCK message for plan-spec consistency.** Pre-v6.8.3: `BLOCKED: plan-spec consistency check failed. Fix .apd/pipeline/implementation-plan.md per the messages above` — vague, the orchestrator has to go back to workflow.md for the syntax (~60s cost). v6.8.3: a concrete copy-paste fix template directly in the BLOCK output with a `### Backend / **Implements:** R1, R3` example + `### Files to modify / **Implements:** none` example + "Apply fix, then re-run" instruction. The orchestrator applies immediately (~5-10s).
- **fix(workflow): §3c MANDATORY marker at the top of the section.** Bridged the "rules-at-the-bottom" problem: pre-v6.8.3 the rules were below the format example (1 scroll). v6.8.3 adds an explicit **MANDATORY** marker right under the §3c heading with a "Common mistake" warning ("write plan without **Implements:** headers → BLOCK → go back and add. Saves 60s by writing headers from the start").
- **fix(AGENTS.md): step 3 MANDATORY marker (Codex mirror).** The Codex orchestrator gets the same visually-prominent instruction. Plus "Write headers FROM THE START — verify-plan-spec strict mode hard-BLOCKS otherwise" stated explicitly up front.
- **Empirical baseline (v6.8.2 Test):** 2 plan-spec-consistency BLOCKs (12 issues → 9 issues → pass) 17s apart + 2 rationale BLOCKs (rationale-missing → rationale-100pct-orch-dismiss). Net cost ~3-5 min recovery vs ~5-10s with v6.8.3 inline templates. **Real limit:** the orchestrator's RLHF training pattern and memory weight can still cause forgetting. v6.8.3 does not erase the BLOCK pattern — it reduces recovery friction.
- **Tests:** `test-codex-adapter` §62 adds 4 static assertions: pipeline-advance BLOCK contains the `**Implements:** R1, R3` literal, `**Implements:** none` scaffolding hint, workflow §3c MANDATORY marker, Codex AGENTS.md MANDATORY marker. Test count 476 → 480.
- **Strategic note:** v6.8.3 closes the "vague BLOCK message" gap. The next patch (if any) probably targets a **session-start hook reminder** or an **on-demand plan-check command** for preventive validation. Open question for the future.

## v6.8.2 — 2026-05-22

Same-day observability patch responding to v6.8.1 live verification in the `~/Projects/Test` "Admin lista kontakt poruka" task (13m 25s, 3× speedup vs v6.8.0 baseline). The run passed clean but surfaced two fine signals: (a) `verify-plan-spec` does not log BLOCKs to guard-audit.log while the other gates do (observability gap); (b) the orchestrator forgets `.adversarial-rationale.md` before the verifier advance — the gate works reactively (v7.1 BLOCK), but the workflow guidance is not visually prominent. Tests: 472 → 476 (+4 in §61).

- **fix(verify-plan-spec): log_block "plan-spec-consistency" call in the BLOCK branch.** A strict-mode BLOCK now writes an entry to guard-audit.log with the format `BLOCK|orchestrator|plan-spec-consistency|issues=N mode=strict`. Format consistent with the other gate log entries (max_defects-exceeded, rationale-missing, etc.). `apd report` and forensic analysis now have visibility into plan-spec block events.
- **fix(workflow): step 6 + step 7 stronger preventive reminder for .adversarial-rationale.md.** Step 6 — an explicit **MANDATORY** marker for writing the rationale file "BEFORE attempting verifier advance"; an explicit explanation "Common mistake: orchestrator finishes adversarial dispatch, jumps directly to verifier, hits v7.1 BLOCK". Step 7 — a new **Sanity check FIRST** bullet that explicitly requires `.adversarial-rationale.md` presence before `apd pipeline verifier`. Pre-v6.8.2 the instruction was there, but nested in a long checklist; now it is visually salient. The Codex AGENTS.md already has an equally strong instruction (lines 46 + 57) — workflow.md is now at parity.
- **Empirical baseline from the v6.8.1 live verify:** Pipeline duration 13m 25s vs 33m for the previous task of the same scope (**3.0× speedup**). ADVERSARIAL:10:1:9 — real adversarial work, not front-load anticipation. Spec `max_defects=unlimited` (workflow §0b update active). Plan has `**Implements:**` headers on all sections (strict default forces it). 2 BLOCKs in the session-log: `rationale-missing (1x)` + `rationale-100pct-orch-dismiss (1x)` — the gate worked reactively but effectively; the orchestrator learned in real time (3 behaviors recorded by the user). Zero max_defects/cycle-cap cascade BLOCKs.
- **Tests:** `test-codex-adapter` §61 adds 4 assertions: (a) verify-plan-spec source contains a log_block call with the plan-spec-consistency reason, (b) workflow.md step 6 has a MANDATORY marker for the rationale file, (c) workflow.md step 7 has a preventive Sanity check, (d) a live default-strict BLOCK actually writes an entry to guard-audit.log. Test count 472 → 476.
- **Migration:** zero impact on existing projects. Pure observability + docs polish. Users who already have a v6.8.1 install: one marketplace upgrade + reinstall, no project-side fixup needed.

## v6.8.1 — 2026-05-22

Same-day patch responding to live evidence from `~/Projects/Test` "Add contact form" run (~33 min total, 3 guard block triggers, 16 agent dispatches vs 6 baseline for similar scope). Root cause: workflow.md §0b preskripcija **"real task → max_defects=0"** caused orchestrator to:
1. Hit `max_defects-exceeded` BLOCK at 03:21:33 (`ADV_D=5 max_defects=0`).
2. Attempt mid-pipeline raise → caught by v6.3 D immutability gate at 03:22:48.
3. Cascade into multi-cycle reset + builder-cycle-cap exhaustion (03:36:47).
4. Front-load anti-pattern: orchestrator pre-emptively packed 5 anticipated fixes (F1-F5) into FIRST plan to ensure max_defects=0 passes — bigger builder context, lost adversarial fresh-eyes value.

Plus the v6.8.0 verify-plan-spec gate emitted 11 WARN linija but orchestrator ignored them (soft-warn mode = ignored signal). Tests: 468 → 472 (+4 in §60).

- **fix(workflow): §0b removes the `max_defects=0` prescription for the real-task default.** Default is now `unlimited` (= no field in spec-card.md). The field remains an optional power-user override for polish-mode tasks where you genuinely know the budget up front. Rationale: the v6.7 rationale gate (per-finding ≥40 chars + 100%-Do hard-block) structurally covers the same misuse pattern without a preflight budget cap; the v6.1 B2 budget cap is now belt-without-suspenders.
- **fix(verify-plan-spec): DEFAULT_MODE flip from `warn` to `strict`.** Single-line change. Plan sections without `**Implements:**` headers, or plans missing R-ids from spec-card.md, now BLOCK by default. Graceful migration path: set `plan_consistency_gate: warn` in spec-card.md to keep v6.8.0 soft behavior; `plan_consistency_gate: off` to skip entirely.
- **test(test-codex-adapter): §60 — strict-by-default lock-in.** Four new assertions: no-mode-field + missing-R-id → BLOCK + exit 1; no-mode-field + section-without-Implements → BLOCK + exit 1; no-mode-field + perfect plan → exit 0 silent; explicit `plan_consistency_gate: warn` override → WARN + exit 0 (migration path verification). Plus updated §59 Static E from `DEFAULT_MODE="warn"` baseline to `DEFAULT_MODE="strict"`. Plus retro-added `plan_consistency_gate: off` to 5 existing test fixtures (§42 builder cycle cap, §43 reviewer cycle cap + polish mode, §45 reviewer rollback, §51 stale dispatch filter, §52 rationale gate) so they continue testing their own gate logic without v6.8 strict mode interference.
- **Migration note.** Projects that upgrade v6.8.0 → v6.8.1 and still have plans without `**Implements:**` headers get a BLOCK on the first `apd pipeline builder`. Fix: add `**Implements:** R1, R3` (or `none`) headers on every `### Section`. Alternative: add `plan_consistency_gate: warn` to spec-card.md for soft mode during the transition. **Projects that have `max_defects=0` in their spec-card templates or reuse spec patterns get a soft hint** (no automatic BLOCK on field presence; the field continues to work as before — but workflow.md guidance no longer recommends writing it).
- **Empirical record.** The `.claude/memory/status.md` v6.8.1 phase section records details of the 2026-05-22 Test 33-min run as a baseline for future force-multiplier comparisons. A `feedback-max-defects-zero-friction` memory entry should be added separately to the project memory.

## v6.8.0 — 2026-05-22

New structural gate that closes the **plan-spec ambiguity gap**: orchestrator-authored `implementation-plan.md` is now mechanically verified against `spec-card.md` R-criteria via per-section `**Implements:**` headers. Bidirectional check — every spec `R*` must be referenced by ≥1 plan section, every plan section must declare R-ids or `none`. Ships with `plan_consistency_gate: strict|warn|off` field in spec-card.md; default `warn` in v6.8.0 (issues emit WARN, no block) to give existing projects a grace window. v6.8.1 will flip default to `strict`. Tests: 456 → 468 (+12 in §59; baseline +37 already grew from §53–§58 across v6.7.x).

- **feat(verify): new `plugins/apd/bin/core/verify-plan-spec` parser.** Parses `### Section` headings in `.apd/pipeline/implementation-plan.md`, extracts per-section `**Implements:** R1, R3` declarations, runs three checks: (1) forward — every R-id in `**Implements:**` must exist in spec-card.md, (2) reverse — every spec R-id must appear in ≥1 section's `**Implements:**`, (3) symmetric — every section must have an `**Implements:**` header (or `**Implements:** none` for scaffolding like file lists, agents, notes). Backward compat: if spec-card.md is missing R-criteria entirely, or if implementation-plan.md doesn't exist, exit 0 silent (other gates already block).
- **feat(pipeline): `pipeline-advance builder` calls verify-plan-spec.** Gate runs after the existing implementation-plan.md presence check, before BUILDER_RAN. The script itself decides the exit code by mode (read from spec-card.md). v6.8.0 default mode `warn`: issues print to stderr but `pipeline-advance` continues. `plan_consistency_gate: strict` opt-in: BLOCK with explicit error directing orchestrator to fix the plan or downgrade to `warn`.
- **feat(spec-card): three-level `plan_consistency_gate` field.** New opt-out field in spec-card.md alongside existing `adversarial: max_defects=N` / `adversarial: rationale_gate=off` patterns. Three values: `strict` (BLOCK on missing/unknown R-id or missing `**Implements:**`), `warn` (emit WARN, no block), `off` (skip entirely — for exploratory/experimental tasks where plan is deliberately rough draft). Default v6.8.0 = `warn`, v6.8.1+ = `strict`.
- **docs: workflow.md §3c rewritten.** New format example shows every `### Section` with mandatory `**Implements:**` header (Backend → R1, R3; Frontend → R2, R4; Files to modify/create/Agents/Notes → `none`). Two new bullets in Rules section: format requirement + opt-out field semantics.
- **docs: AGENTS.md (Codex) Order of operations step 3.** Mirror update — Codex orchestrator gets the same instruction with same opt-out flag reference.
- **docs: SPEC.md §9.** New `verify-plan-spec` row in verifiers table; spans gate behavior, mode parser, exit codes, builder-branch caller.
- **Strict symmetric rule, no reserved section names.** An earlier design draft considered exempting `Files to modify`, `Files to create`, `Agents`, `Notes` from the `**Implements:**` requirement. Rejected in favor of explicit `**Implements:** none` on those sections — eliminates parser special cases, gives a consistent rule to the orchestrator, and the WARN-on-missing-header signal genuinely distinguishes "orchestrator forgot" from "scaffolding section by design".
- **Gaming pattern closed by reverse check.** Mechanically putting `**Implements:** none` on all sections does not defeat the gate because the reverse check fails on uncovered R-ids — every spec R* must appear in ≥1 non-none section.
- **Tests:** `test-codex-adapter` §59 adds 12 assertions covering: binary exists/executable, forward+reverse+mode-parser+DEFAULT_MODE static greps (5), live perfect plan, live missing-R, live unknown-R-id, live section-without-Implements (default warn mode, 4), live opt-out off, live strict mode + missing-R, live strict mode + section-without-Implements (3). Live setup uses isolated synthetic project with .apd/pipeline/{spec-card.md,implementation-plan.md} fixtures. Test count 456 → 468.
- **Migration:** postojeci projekti continue to work — gate emits WARN, doesn't block. To upgrade plan-ove to the new format, add `**Implements:** R1, R3` (or `none`) to each `### Section`. v6.8.1 will flip default to `strict`; CHANGELOG v6.8.1 entry will document migration step explicitly.
- **Why this matters strategically.** The discussion record (`~/.claude/plans/hajde-da-prodiskutujemo-na-sequential-giraffe.md`, 2026-05-20) traces the root cause analysis: the real root of defects is not adversarial dismissal or builder overrun, but **a fuzzy spec → fuzzy plan → builder works in the fog → downstream gates operate on a wide ambiguity surface**. The current pipeline has two mechanical anchors (`verify-trace` for spec↔tests, presence check for plan), but the uncovered gap between them is that the plan technically exists yet does not map explicitly to the R-criteria. v6.8 closes that layer.

## v6.7.7 — 2026-05-20

Closes the 2 WARN signals reported from FiscalFusionAI v6.7.6 validation (126 PASS / 0 FAIL / 2 WARN baseline). Both review-class agent templates now self-declare the no-commit boundary, matching what `guard-git` already enforces at the bash level. Defense-in-depth: the bash guard catches actual attempts; the template text tells the agent the boundary BEFORE it tests the guard. Tests: 454 → 456 (+2 in §58).

- **fix(templates): add explicit FORBIDDEN / no-commit block to all 4 reviewer templates.** Both CC (`templates/reviewer-template.md` + `templates/adversarial-reviewer-template.md`) and Codex (`templates/codex/agents/code-reviewer.md` + `templates/codex/agents/adversarial-reviewer.md`) gain a `## FORBIDDEN` section listing: "NEVER commit changes" (with reference to `guard-git` being the runtime enforcer), "NEVER edit or create project source files" (reviewers are read-only by role), "NEVER add AI signatures" (style is human). The text patches the same gap that `templates/agent-template.md` already had — reviewers were the only template family missing it.
- **Why this matters even though `guard-git` already enforces.** The bash-level block is the safety net, not the docs. Agents that learn about the prohibition only by hitting the guard waste turns + emit confusing failure paths. Explicit template text says "here's the boundary, don't go near it" before the agent has to discover it experimentally. `verify-apd` Section 6 validator at lines 480-485 specifically checks for `NEVER.*commit | FORBIDDEN | ZABRANJENO | NIKADA.*commit` patterns in agent .md files — the WARN existed because reviewers genuinely lacked the text, not because the validator was wrong.
- **Existing projects** scaffolded pre-v6.7.7 do NOT auto-pick up the template changes — agent files in `.claude/agents/` are copied once at `/apd-setup` time and never overwritten. To pick up the new prohibition, re-run `apd-init` or manually copy the templates. The 2 WARN signals will persist on those projects until refreshed.
- **Tests:** `test-codex-adapter` §58 adds 2 assertions: all 4 reviewer templates contain `NEVER commit` or `FORBIDDEN` text; `verify-apd` Section 6 still does the validation check (keeps the lock-in alive). Test count 454 → 456.

## v6.7.6 — 2026-05-20

**Hotfix.** `verify-apd` had three stale assumptions from prior version migrations that surfaced when a user ran `/apd-setup` on a v6.7.5 install. None affected production behavior — the hooks fired correctly per the direct §7 guard tests — but the E2E verification script reported false failures, undermining trust in `apd verify` output. Tests: 450 → 454 (+4 in §57).

- **fix(verify-apd): hook detection reads `args[0]`, not `.command` (v6.6.0 exec-form catch-up).** Three checks at lines 264 / 275 / 284 (`SessionStart → session-start`, `PreToolUse(Bash) → guard-git`, `PostToolUse(Bash) → pipeline-post-commit`) used `jq '.hooks[].command'` then `grep` for the script name. Since v6.6.0 migrated `hooks/hooks.json` to args exec form, `.command` is now just `"bash"` and the script path lives in `.args[0]` — grep against `"bash"` always failed → 3 false-FAIL reports per `apd verify` run. Helper jq expression `(.command // "") + " " + ((.args // []) | join(" "))` concatenates both fields and matches across the old shell-string form (backward compat) and the new args form. Surfaced 2026-05-20 by an orchestrator running `/apd-setup` in `~/Projects/NetProjects/FiscalFusionAI` — a separate project from BambiProject, giving APD its first multi-project fresh-install validation signal.
- **fix(verify-apd): Section 8 writes `.adversarial-rationale.md` before verifier (v6.7.0 catch-up).** Section 8 line 904 wrote `ADVERSARIAL:3:2:1` to `.adversarial-summary` then expected verifier to pass; line 926 wrote `ADVERSARIAL:1:0:1` for the ordering-test BLOCK assertion. v6.7.0 added the rationale-file hard-block (v7.1) — both calls now hit `BLOCKED: Adversarial rationale file missing` instead of their intended outcome. Both spots now write a minimal valid rationale matching the T:A:D count + clean up the file at the end. The ordering-test gate fires earlier in `pipeline-advance` than the rationale gate, so the test assertion (`grep "before reviewer"`) still works, but the rationale file is now present defensively.
- **fix(verify-apd): cascade — adversarial ordering test setup failure resolves.** The original report mentioned a third bug: "adversarial ordering test setup failed (no reviewer.done after rollback)". Root cause was the previous test (Bug #2) blocking on rationale-missing and never completing the rollback handoff cleanly. Fixing Bug #2 resolves this cascade automatically.
- **No production behavior change.** Guards still fire correctly (the §7 direct-call guard tests prove this — 12/12 PASS pre-fix). The fix is to `verify-apd`'s detection logic, not to any hook script. Hooks have always worked since v6.6.0.
- **Lesson:** `verify-apd` runs in the framework's own development workflow (`bash plugins/apd/bin/core/test-codex-adapter` includes Section 8 of verify-apd indirectly), but the hook-detection grep ran against the framework's own `hooks/hooks.json` — which was migrated to args form in v6.6.0. We should have caught these false-FAILs at the v6.6.0 ship moment but didn't, because nobody ran a fresh `apd verify` cycle on a freshly-installed project. The 2026-05-20 user-report is the first such fresh-install signal in 4 days. Adds to [[feedback-test-hook-path-blindspot]] — there is a sibling pattern: scripts that VALIDATE the runtime hook surface need to be re-run after every hook-format migration, not just regression-checked via static parser tests.
- **Tests:** `test-codex-adapter` §57 adds 4 static assertions: `_CMD_CONCAT` helper present, Section 8 3:2:1 test writes rationale, ordering test writes rationale, cleanup removes rationale. Test count 450 → 454.

## v6.7.5 — 2026-05-19

Quick in-session toggle for the APD plugin's enabled state. CC-only — Codex has no `enabledPlugins` concept. Tests: 443 → 450 (+7 in §56).

- **feat(cli): `apd toggle [on|off]` flips `claude-apd@zstevovich-plugins` in CC settings.** New `plugins/apd/bin/core/toggle-apd` script wired into the apd CLI dispatcher. Default behavior: smart-detection scans `<project>/.claude/settings.local.json` → `<project>/.claude/settings.json` → `~/.claude/settings.json` and edits the first file that already contains the key. If the key is absent everywhere, defaults to `settings.local.json` (per-developer, gitignored, no team-wide impact). Why smart-detection matters: CC merges `settings.local.json` over `settings.json`, so writing to a file that does NOT hold the active value has no visible effect. Detection picks the file whose value CC will actually read.
- **fix(jq): smart-detection uses `has()` presence check, not truthiness.** Initial implementation used `jq -e '.enabledPlugins[$k]'` which returns failure for `false` (jq treats `false` as not-truthy) — this mis-classified an explicitly-disabled APD as "key missing" and edited the wrong file. Caught during local sanity test before ship; fixed by switching to `jq -e '.enabledPlugins | has($k)'`. Same gotcha resolved in the current-value reader: `jq '.enabledPlugins[$k] // "missing"'` returns RHS on both `null` AND `false`; replaced with an explicit `if has($k) then ... else "missing" end` conditional. Lock-in assertion in §56 (Static B) ensures this regression cannot ship again.
- **feat(skill): `/apd-toggle` CC slash command (`skills/apd-toggle/SKILL.md`).** Parses user intent (off/on/flip + optional `--global` / `--project` / `--local`), invokes `bash .claude/bin/apd toggle [arg]`, then calls `/reload-plugins` via the SlashCommand tool for in-session pickup — closes the bonus reload-without-restart wish. Anti-patterns section warns against manually editing settings JSON instead of using the script (smart-detection + jq atomic edit are not trivial to reproduce by hand). Total CC skill count 8 → 9.
- **flags supported:** `on`/`enable`/`true`/`1` force enable; `off`/`disable`/`false`/`0` force disable; `--global` writes to `~/.claude/settings.json`; `--project` writes to project tracked `settings.json`; `--local` writes to per-dev `settings.local.json`; no-arg flips current.
- **Atomic edit safety:** writes go through `mktemp` + `jq` + `mv`; partial-write or jq failure cannot corrupt the existing settings file. Trap cleans the temp file on early exit.
- **Reports:** prints `Old → New`, the edited file path, smart-detection note (if applied), and the reload hint. Output line `APD plugin: true → false` is the primary user-visible signal.
- **docs: SPEC.md §2** new `toggle` row in CLI surface table. **SPEC.md §7.1** CC skills table grows to 9 with `apd-toggle` row.
- **Tests:** `test-codex-adapter` §56 adds 7 assertions: script + CLI verb presence, `has()` static check, true→false flip, false→true flip (the bug-regression case), explicit `off` arg, missing-file → settings.local.json creation, smart-detection picks settings.json when key lives there. HOME-isolated test setup ensures no real `~/.claude/settings.json` is touched. Test count 443 → 450.

## v6.7.4 — 2026-05-19

**Hotfix.** v6.7.0 introduced `.adversarial-rationale.md` as a required pipeline state file that the orchestrator authors directly, but the guards on both runtimes (`guard-pipeline-state` on CC, `guard-file-edit` on Codex) were never updated to allow that path. Result: the orchestrator hit a hard BLOCK when trying to write the rationale file the verifier demanded, leaving the pipeline stuck between adversarial and verifier. Surfaced live on BambiProject MR.13a (2026-05-19, v6.7.3 install). Tests: 441 → 443 (+2 static).

- **fix(guard-pipeline-state, CC): allow `.adversarial-rationale.md`.** Added to the orchestrator-writeable allowlist (`spec-card.md`, `implementation-plan.md`, `.adversarial-summary`, `.adversarial-rationale.md`). Header comment + case statement updated.
- **fix(guard-file-edit, Codex): allow `.adversarial-rationale.md`.** Added to `AUTHORING_ALLOWLIST` in the Python guard block — Codex orchestrator can now write the rationale file via apply_patch / Edit / Write without needing a prior `apd_guard_write` call to clear the path.
- **docs: SPEC.md §4.3** `guard-pipeline-state` allowlist row updated; v6.7.4 tag added in-line.
- **Test §52 lock-in:** 2 new static assertions verify the allowlist additions on both runtimes so this regression cannot ship silently again.
- **Lesson:** the v6.7.0 test suite covered the rationale gate logic end-to-end via direct `cat > file` writes from the test harness — never going through the CC Write tool path, so the guard-pipeline-state hook was bypassed in tests. Real-world dispatch goes through the hook. Added to `feedback-validation-futility` thinking: format tests aren't enough when the runtime hook path differs from the test write path.

## v6.7.3 — 2026-05-18

v6.4 backlog F1 + F3 — template-only directives that complement the v6.7.2 F2 detection arm. F1 makes the orchestrator include an explicit finalization clause in every builder dispatch prompt; F3 forces builders to ground their self-reports in `git diff --stat` + `git status --short`, preventing hallucinated rename/file-add claims. Tests: 438 → 441 (+3 in §55).

- **docs(workflow): F1 mandatory dispatch finalization clause.** `workflow.md` step 5 now reads: "Mandatory finalization clause in EVERY builder dispatch prompt: 'When the build passes AND the tests you wrote pass, STOP IMMEDIATELY. Do NOT re-verify. Do NOT search "one more time" to confirm. Verification of completeness is the reviewer's job, not yours.'". Cross-ref to v6.7.2 F2 in the same block — F2 is the telemetry/detection arm; F1 is the upstream dispatch-prompt rule. Pure template; can't be runtime-enforced (we don't see what orchestrator writes to its subagent), but reinforces against the RLHF "thorough" default and complements the F4 `STOP IMMEDIATELY` wording in dispatch templates shipped in v6.3.0.
- **docs(templates): F3 git-state self-check directive.** Added a "Before stopping — git-state self-check" block to the Exit criteria section of `templates/agent-template.md` (CC master) + Codex `templates/codex/agents/{backend-builder,frontend-builder,testing}.md`. Each block instructs: `command -v git >/dev/null 2>&1 && git diff --stat && git status --short`, then "Report **exactly** which files you changed (or that you changed none). Do not claim work you did not do — hallucinated renames or file additions that aren't in `git status` mislead the reviewer and waste a re-dispatch.". Targets the 2026-05-11 incident where the agent claimed "renamed nonPursQrDoesNotResetTimers" but didn't actually do so — verifier confidence broke down. Reviewer templates intentionally skipped — they don't write code; the directive doesn't apply.
- **Memory: v6.4 builder-overrun backlog** marks F1 + F3 as DONE. Full F-family now closed:
  - F1 — workflow.md dispatch finalization (DONE v6.7.3)
  - F2 — track-agent duration outlier flag (DONE v6.7.2)
  - F3 — agent-template git-state self-check (DONE v6.7.3)
  - F4 — dispatch-template STOP IMMEDIATELY wording (DONE v6.3.0)
- **Existing projects:** scaffolded pre-v6.7.3 do NOT auto-pick up the template changes — re-run `apd-init` or refresh agent files manually. Codex projects do not regenerate agents from the cache automatically.
- **Tests:** `test-codex-adapter` §55 adds 3 assertions: workflow.md carries F1 clause; CC `agent-template.md` has F3 directive; all 3 Codex builder/testing templates have F3 directive + `command -v git` guard. Test count 438 → 441.

## v6.7.2 — 2026-05-18

v6.4 backlog F2 — `track-agent` SubagentStop now flags long-running agents that produced no recent file writes. Targets the 2026-05-11 intra-dispatch overrun pattern (1 builder, 23 min, 15 min of post-success "verification" loop with no code changes). Post-hoc detection only — surfaces signal, does not block. Tests: 435 → 438 (+3 in §54).

- **feat(track-agent): agent duration outlier flag (F2).** On `SubagentStop`, compute duration from the paired start event in `.agents`. When `> APD_AGENT_LONG_RUN_THRESHOLD_SEC` (default 600s) AND no uncommitted file (via `git status --porcelain` + `stat` mtime) has been modified in the trailing 5 min, emit a stderr WARN ("possible verification loop") and append `ts|agent_type|agent_id|duration_sec` to `$MEMORY_DIR/agent-overrun.log`. Disable: `APD_AGENT_LONG_RUN_THRESHOLD_SEC=0`.
- **Write-detection method:** `git status --porcelain` filters to candidate files (uncommitted changes + untracked); per-file `stat` mtime compared against `stop_epoch - 300s`. Avoids filesystem-wide `find` — no false-positive noise from build artifacts or dependency caches. False-positive scenario: legitimate long-but-quiet research tasks (e.g., extensive Read-only scan); user can lift the threshold per session.
- **Why post-hoc instead of intercepting:** track-agent is a SubagentStop hook — by the time it fires, the agent has already exited. Real-time intervention would need a SubagentInProgress hook (doesn't exist) or polling. Post-hoc WARN at stop time + `agent-overrun.log` history is enough for users to spot the pattern and re-tune their dispatch prompts.
- **docs: SPEC.md §5.4** documents the new telemetry file format, threshold env var, and 2026-05-11 incident reference.
- **Memory: v6.4 builder-overrun backlog** marks F2 as DONE. F1 (workflow.md dispatch finalization helper) + F3 (git-state mandatory self-check in agent template) remain open.
- **Tests:** `test-codex-adapter` §54 adds 3 assertions: static check for env var + WARN msg + log path; live simulation (20-min back-dated start + no file writes) → WARN + log entry; live with `APD_AGENT_LONG_RUN_THRESHOLD_SEC=0` → silent. Test count 435 → 438.

## v6.7.1 — 2026-05-18

Phase 4 patch — `pipeline-metrics.log` extended with per-status dismissal columns and rationale-warn counter. `apd pipeline metrics` cumulative report surfaces the new data without breaking legacy 12-column rows. Tests: 430 → 435 (+5 in §53).

- **feat(metrics): three new columns at positions 13–15.** `adv_do` (orchestrator dismissals), `adv_dr` (reviewer-self-dismissals), `adv_w` (count of soft-warn lines from rationale-quality scan: short rationales <40 chars or lazy-pattern matches). Read from `.adversarial-rationale.md` at reset time; the awk pass that runs in verifier is mirrored here so the warn count is consistent between live verifier output and historical metrics. Column 10 (`adv_d`) stays as `adv_do + adv_dr` for backward compat with v6.6 and earlier readers — no breaking change.
- **feat(metrics): apd pipeline metrics renders dismissal split + warns line.** Cumulative "Adversarial review" section now shows `Dismissal split: Do=N (orchestrator) Dr=N (reviewer-self)` and `Rationale warns: N (rationale text <40 chars or lazy pattern)` when non-zero. Old 12-column rows produce empty trailing fields that default to 0 — they render the same as before.
- **docs: SPEC.md §5.4** documents the v6.7.1 column extension and backward-compat behavior.
- **Tests:** `test-codex-adapter` §53 adds 5 assertions (2 static + 3 live): writer emits Do/Dr/Warns vars, apd report parses + renders them, 12-col legacy row renders without Do/Dr split, 15-col row renders with split + warns, end-to-end (rationale → verifier → reset → 15-col row with correct counts). Test count 430 → 435.

## v6.7.0 — 2026-05-18

Adversarial dismissal quality — `pipeline-advance verifier` now reads `.apd/pipeline/.adversarial-rationale.md` and hard-blocks the 100% orchestrator-dismissal bypass pattern. Three-status classification (accepted / dismissed / reviewer-self-dismissed) lets clean reviewer-self-dismiss runs sign through while catching orchestrator rationalization-without-action. Tests: 419 → 430 (+11 in §52).

- **feat(pipeline): adversarial rationale gate.** New file `.apd/pipeline/.adversarial-rationale.md` required after every adversarial pass with `T>0`. One `## Finding N — <title>` block per finding with `**Severity:** critical|important|minor`, `**Status:** accepted|dismissed|reviewer-self-dismissed`, `**Rationale:** <text>`. `pipeline-advance verifier` hard-blocks on six conditions: missing file (v7.1), finding-block count != T (v7.3), Severity/Status/Rationale field count drift per block (v7.4), accepted count != A (v7.5), dismissed sum != D (v7.5), and the 100%-orchestrator-dismiss pattern T>=3 && A==0 && Do>=1 (v7.6). Reset, full reset, and verifier/reviewer rollback all wipe the rationale file.
- **feat(pipeline): per-task opt-out.** spec-card.md `adversarial: rationale_gate=off` skips the entire rationale gate for tasks where strict structured rationales are not appropriate (exploratory phase, hotfix path). Default is on. Same bold/italic tolerance pattern as `adversarial: max_defects` (v6.1.2).
- **feat(pipeline): soft quality warnings.** When all hard gates pass, `pipeline-advance verifier` runs an awk pass over the rationale file. Rationale text under 40 chars for dismissed/reviewer-self-dismissed entries emits `! WARN Finding N: rationale only N chars`. Lazy-pattern matches (`ok`, `n/a`, `false positive`, `not applicable`, `skip`, `no`) emit `! WARN Finding N: rationale matches lazy pattern`. Non-blocking — surfaces in stderr for visibility.
- **feat(templates): adversarial-reviewer Status field.** Both CC (`adversarial-reviewer-template.md`) and Codex (`templates/codex/agents/adversarial-reviewer.md`) now require per-finding `Status: active | self-dismissed`. Self-dismissed entries must include a `Note: <reason>` for the orchestrator to copy verbatim into the rationale file as `reviewer-self-dismissed`. The distinction prevents healthy adversarial runs (reviewer raises noise and processes it itself) from false-triggering the 100%-dismiss gate.
- **docs: workflow.md step 6b expanded.** New rationale-file write instruction between adversarial dispatch and verifier step, including format spec and gate behavior notes. Step 7 documents the rationale gate alongside the existing severity gate (v6.1 B2).
- **docs: Codex AGENTS.md guardrails.** `apd_adversarial_pass` row expanded with rationale-file requirement; new guardrail bullet for orchestrators on Codex runtime.
- **docs: SPEC.md §5.3** documents the new state file row with full format spec and gate behavior.
- **Live evidence motivating the fix:** 2026-05-16 landing-page test (`~/Projects/Test`, v6.6.0) produced `ADVERSARIAL:5:0:5` with five orchestrator-only dismissals — three legitimate (out-of-scope per APD diff rule), two weak ("already an existing pattern elsewhere"). 2026-05-18 MR.9 BambiProject (cross-stack mobile + backend) had a numerically-healthy 8:4:4 but the session transcript revealed the orchestrator's entire dismissal rationale was one line: *"1 Critical + 3 Important. Dispatch fixes."*. Zero per-finding documentation; closure summary mentioned only the four accepted findings. v6.7 forces the structured rationale and hard-blocks the bypass pattern at the verifier gate.
- **Tests:** `test-codex-adapter` §52 adds 11 assertions (4 static + 7 live): hard-gate expression presence, BLOCK message identifiers, reset cleanup coverage, 5:0:5+no-file BLOCK, count-mismatch BLOCK, 100%-dismiss BLOCK, Dr=5 SIGN, 5:2:3 SIGN, short-rationale WARN, lazy-pattern WARN. Test count 419 → 430.
- **Implementation design:** `docs/plans/v6.7-adversarial-dismissal-quality.md` — full phased plan with file format spec, parser rules, BLOCK message catalog, risk register, and bump strategy. Phase 4 (pipeline-metrics columns + `apd report` integration) deferred to v6.7.1 patch.

## v6.6.0 — 2026-05-16

`hooks/hooks.json` migrated to CC 2.1.139 `args: string[]` exec form. Hard-block on CC < 2.1.139. Tests: 416/0 (no regressions). Live-verified end-to-end in `~/Projects/Test`.

- **feat(hooks): migrate to args exec form.** All 13 hook entries in `hooks/hooks.json` (1 SessionStart, 6 PreToolUse, 1 PostToolUse, 1 SubagentStart, 1 SubagentStop, 1 PreCompact, 1 PostCompact, 1 PermissionDenied) now use `"command": "bash", "args": ["${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/..."]` instead of `"command": "bash \"<path>\""`. Exec form spawns the command directly without a shell — fewer escaping pitfalls, no shell-injection surface, and matches CC's documented modern hook form.
- **Hard-block below CC 2.1.139.** On CC < 2.1.139 the `args` field is silently ignored and `bash` runs with no script path — every APD guard becomes a silent no-op. To make this user-visible instead of a silent failure, `APD_MIN_VERSION` and `APD_FUNCTIONAL_VERSION` in both `session-start` and `verify-apd` (plus the `plugins/apd/.apd-version` overrides) pin to `2.1.139`. Users on older CC see a hard-block message at SessionStart with the upgrade command, not a degraded session where guards quietly stop working.
- **SPEC.md §4.1 updated** to document the exec form migration, the version-pin rationale, and that Codex hooks (`install-codex-config`) are unaffected — `args` exec form is a CC-only feature; Codex hook schema is separate.
- **Live test (2026-05-16):** after `/plugin marketplace update zstevovich-plugins` + `/plugin uninstall claude-apd` + `/plugin install claude-apd@zstevovich-plugins` + hard restart, `~/Projects/Test` showed: plugin cache populated `claude-apd/6.6.0/`, `installed_plugins.json` updated to version 6.6.0, exec form rendered as `[bash ${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/adapter/cc/guard-bash-scope]` in CC hook trace, and `guard-bash-scope` correctly blocked `echo test > .apd/pipeline/spec-card.md` with `BLOCKED: Bash redirect to protected pipeline state directory`. End-to-end signal: hook fired, script reached its `exit 2 + BLOCKED:` message, args exec form is functional on this CC version.

## v6.5.4 — 2026-05-14

`pipeline-doctor` §9 GitHub Sync no longer warns on idle pipelines. Tests: 413 → 416.

- **fix(doctor): gate GH-sync warning on active pipeline.** `pipeline-doctor` §9 GitHub Sync emitted `gh CLI available but no issue linked (.gh-issue missing)` on every doctor run when `gh` was installed — including idle pipelines (no `spec-card.md`) where there is no task to link an issue to. The warn was pure noise: users who want GitHub Projects integration run `/apd-github` when starting a task, and users who don't want it skip it entirely; nagging on every idle doctor run adds nothing. Fix: gate the warn behind `[ -f "$PIPELINE_DIR/spec-card.md" ]`. Idle pipelines now print a softer dim hint ("link a task with /apd-github when needed") that doesn't register as a WARN line in the summary. Active pipelines (real task in flight) keep the warn — that's where linking an issue actually matters. The fix is one if-branch + one dim echo; no behavioral changes outside §9.
- **Live-verified before bump:** tmp project with `.apd/config` + empty `.apd/pipeline/` → `pipeline-doctor` prints the dim hint, no WARN. Same project with `spec-card.md` added → WARN fires as before.
- **Test:** `test-codex-adapter` §50 (3 assertions): static gate check (grep finds `spec-card.md` adjacent to the warn string), live idle test (no `spec-card.md` → no warn in output), live active test (with `spec-card.md` → warn fires). Live block guarded by `command -v gh` so CI hosts without `gh` installed don't false-pass. Test count 413 → 416.

## v6.5.3 — 2026-05-14

`verify-apd` Section 6 stub-tolerance + defensive cleanup. Diagnosed from BambiProject v6.5.2 live test on the same evening v6.5.2 shipped. Tests: 410 → 413.

- **fix(verify): F1 — Section 6 (Agents) skips reserved `apd-verify-*` namespace.** BambiProject v6.5.2 live test surfaced two new `✗` lines in verify-apd output: `Agent apd-verify-builder — model is NOT defined` and `Agent apd-verify-builder — guard-git is NOT registered (agent can commit!)`. The Section 6 quality validator (lines 384-451) iterates every `.md` file under `$APD_AGENTS_DIR` and asserts that frontmatter contains `model:`, that hook config registers `guard-git`, that secrets are gated, etc. The Section 8 synthetic builder stub introduced in v6.5.2 (3-line `---\nname: apd-verify-builder\n---`) cannot pass these checks by design — it's a dispatch-placeholder, not a real agent. Fix: a `case "$AGENT_NAME" in apd-verify-*) continue ;; esac` at the top of the for-loop short-circuits the `apd-verify-*` reserved namespace before any check fires, and `AGENT_COUNT` is incremented only after the namespace filter clears (so the registry count stays accurate). Real project agents never use this prefix (B2 reserved-namespace decision from v6.5.2). With v6.5.2 in production, every BambiProject-style consumer where the stub survives a SIGKILL-ed prior run would hit this FAIL — F1 makes the agent-quality check tolerant of the namespace.
- **fix(verify): F2 — defensive cleanup at the top of verify-apd.** Diagnosed root cause for "stub keeps coming back": the Section 8 cleanup trap fires only on EXIT/INT/TERM. SIGKILL, CC harness timeouts (Background command termination, `kill -9`, process-group reaper) all bypass the trap, so the stub written at Section 8 line 775 lives on indefinitely after an abnormal termination. v6.5.2's "bezuslovan" trap was a real fix for graceful exits but not for SIGKILL — the trap mechanism itself depends on signal-handler cooperation. Fix: a 9-line cleanup block runs immediately after `apd_header "Verification"` and before Section 1. It globs `$APD_AGENTS_DIR/apd-verify-*.md` with `for _stale_stub in ...; do [ -f "$_stale_stub" ] && rm -f "$_stale_stub"; done` (the `[ -f ]` guard handles the no-match-literal-glob case under bash without `nullglob`); also: if `spec-card.md` heading matches `^##? *\[?APD-VERIFY-`, it invokes `pipeline-advance reset` to wipe any leftover synthetic pipeline state from a prior run. Both guards are scoped to the reserved namespace so they never touch real project agents or non-synthetic spec cards. Belt-and-suspenders with the v6.5.2 trap-side cleanup — F2 catches what the trap missed.
- **Live-verified before bump:** scripted reproduction with two `apd-verify-*` stubs (`apd-verify-builder.md`, `apd-verify-stuff.md`) + real `backend-builder.md` (`---\nname: backend-builder\nmodel: opus\n---\nREAL`) → simulated F2 glob → both stubs gone, real `backend-builder.md` intact with the `REAL` sentinel preserved.
- **Test:** `bin/core/test-codex-adapter` §49 grows from 7 to 10 assertions: (F1) grep finds the `apd-verify-*) continue` case clause in verify-apd source; (F2 static) grep finds the `apd-verify-*.md` glob paired with `rm -f "$_stale_stub"`; (F2 live) the mktemp + 2-stub + 1-real-agent scenario asserts the glob purges all `apd-verify-*` files while leaving the real agent untouched. Test count 410 → 413.
- **Note for existing BambiProject contamination:** v6.5.3 defensive cleanup will purge the `apd-verify-builder.md` stub on the next `verify-apd` invocation. The 30-byte `backend-builder.md` (+ `.bak.preaudit`) leftover from old pre-v6.5.2 verify-apd runs is NOT touched by F2 because the filter is `apd-verify-*`, not `backend-builder`. User-driven recovery: inspect file size — real APD agent files are 2-4 KB; the 30-byte file is the historical stub. `rm` at user discretion.

## v6.5.2 — 2026-05-14

`verify-apd` Section 8 cleanup hardening — two failure modes diagnosed from BambiProject `apd doctor` output on the same day v6.5.1 shipped. Tests: 403 → 410.

- **fix(verify): bezuslovan Section 8 cleanup on every exit path.** `restore_pipeline_state` (the EXIT/INT/TERM trap) previously branched on `HAD_EXISTING_PIPELINE`: if the pipeline was empty when verify-apd started (the common case on a freshly reset project), the trap restored nothing and left every synthetic artifact behind — `spec-card.md` with the `## APD-VERIFY-TEST` heading, `spec.done` / `builder.done` / `reviewer.done`, four `a000000…`-ID start/stop pairs in `.agents`, plus `.adversarial-pending` and `.adversarial-summary`. The next `apd doctor` run on that project showed `Active task: APD-VERIFY-TEST` with `✗ verifier: NOT done` despite the user never having run a real pipeline. Fix: new `SECTION_8_ENTERED` flag set `true` at the very top of Section 8 (right after the `_apd_verify_pipeline_busy` skip-gate clears). Trap branches on the flag and calls `bash $SCRIPT_DIR/pipeline-advance reset` bezuslovno before the existing backup-restore layer fires. The existing `HAD_EXISTING_PIPELINE`-gated `cp $BACKUP_DIR/*.done $PIPELINE_DIR/` then layers backup state on top of the reset, preserving the original behavior for projects that did have prior `.done` files. Net effect: idle-project verify-apd runs now end in a fully clean pipeline directory instead of half-state.
- **fix(verify): synthetic builder uses reserved name `apd-verify-builder`.** Section 8 line 754 (pre-fix) wrote a 30-byte stub at `$APD_AGENTS_DIR/backend-builder.md` when the file was absent. `CREATED_BUILDER=true` then gated the trap-side `rm -f`. The bug: every subsequent verify-apd run found the stub present → set `CREATED_BUILDER=false` → trap left the file untouched → the stub became permanent. BambiProject's real agent roster is backend-api / backoffice / database / mobile / testing (no `backend-builder`), so the Apr 29 verify-apd run created the stub, `apd-audit` backed it up as `backend-builder.md.bak.preaudit` (same 30 bytes), and from that point on every `apd doctor` run on BambiProject showed `✓ backend-builder (?/?)` because the agent-registry parser found YAML with only a `name:` field, no `model:` or `effort:`. Fix: synthetic builder name changed to `apd-verify-builder` (reserved namespace for verify-apd's internal use). Trap removes it bezuslovno (no `CREATED_*` flag) because the name is guaranteed never to belong to a real project agent. `code-reviewer` and `adversarial-reviewer` keep their original names because `pipeline-advance` hardcodes `adversarial-reviewer` for the ordering check at lines 631 (`grep "|stop|adversarial-reviewer|"`) and 672 (`grep "|start|adversarial-reviewer|"`); their stub creation continues to gate on `CREATED_REVIEWER` + `CREATED_ADVERSARIAL`. The opt-out section (APD-VERIFY-OPT-OUT, line 905-906) also re-creates the `apd-verify-builder.md` stub idempotently in case `pipeline-advance reset` between the two sub-tests wiped agent files.
- **Live-verified before bump:** scripted reproduction of the BambiProject scenario — tmp project with `APD-VERIFY-TEST` synthetic state (spec-card.md, *.done, .agents, .adversarial-*) + `apd-verify-builder.md` (30-byte stub) + real `backend-builder.md` (55 bytes, mock content) → `pipeline-advance reset` + `rm -f apd-verify-builder.md` (the trap's bezuslovan cleanup pair) → pipeline directory empty, `apd-verify-builder.md` removed, real `backend-builder.md` untouched with all 55 bytes intact.
- **Test:** `bin/core/test-codex-adapter` §49 (7 assertions): (A) `verify-apd` source has zero `backend-builder` references confirming B2 rename completeness; (B) `SECTION_8_ENTERED=true` flag literal present; (C) `awk` extract of the trap function body grep-matches both `SECTION_8_ENTERED.*true` and `pipeline-advance.*reset`; (D) same extract finds the `rm -f "$APD_AGENTS_DIR/apd-verify-builder.md"` literal; (E-G) live cleanup test reproduces BambiProject scenario via `mktemp -d` + manual synthetic state seeding + `pipeline-advance reset` invocation, asserts pipeline directory empty + stub removed + real `backend-builder.md` (with `REAL CONTENT` sentinel) preserved. Test count 403 → 410.
- **Note:** existing BambiProject contamination (the artifacts that surfaced this bug) is NOT auto-recovered by v6.5.2 — fix is forward-only. To clean BambiProject: `bash .claude/bin/apd pipeline reset` + `rm .claude/agents/backend-builder.md .claude/agents/backend-builder.md.bak.preaudit` if those are stale stubs (verify size — real agent files are 2-4 KB; the 30-byte stub is the BambiProject regression artifact).

## v6.5.1 — 2026-05-14

Verification-script path fix. No behavior change in any pipeline, guard, or MCP code path. Tests: 403/0 (unchanged baseline).

- **fix(verify): `hooks/hooks.json` lives at repo root, not `plugins/apd/`.** `plugins/apd/bin/core/verify-apd:230` and `plugins/apd/bin/core/test-hooks:94` both read `$APD_PLUGIN_ROOT/hooks/hooks.json` (= `plugins/apd/hooks/hooks.json`), but per the CLAUDE.md architecture map `hooks/hooks.json` is at the repo root (CC auto-discovery anchor — the v6.0 self-containment plan considered moving it under `plugins/apd/hooks/` but the move never happened because CC requires the anchor at the top-level plugin root, not nested). The two references were stale remnants of that proposed move. Post-fresh-install `verify-apd` therefore printed `✗ Plugin hooks/hooks.json DOES NOT EXIST` as the very first hooks-section result, which masked the rest of the verification report and made the install look broken when in fact every hook was wired correctly. Both scripts now compute `REPO_ROOT="$APD_PLUGIN_ROOT/../.."` (per CLAUDE.md convention for scripts that need repo-root paths — the same pattern the Codex marketplace manifest and top-level CC skills already use) and read `$REPO_ROOT/hooks/hooks.json`. After fix `verify-apd` emits `✓ Plugin hooks/hooks.json valid JSON` and continues into the rest of section 3a (SessionStart, PreToolUse Bash → adapter/cc/guard-git, PostToolUse Bash → pipeline-post-commit, PostCompact, PermissionDenied — all of which were previously skipped because the parent `if` branch short-circuited on the missing file). `test-codex-adapter`: 403/0 — no regressions in the primary E2E suite (the test does not exercise this code path because verify-apd is invoked separately).

## v6.5.0 — 2026-05-13

Framework self-detection — plugin can be enabled in its own source repo without auto-scaffolding or pipeline enforcement turning the framework into a managed consumer project. Tests: 397 → 403.

- **feat(resolve): framework self-detection.** Until v6.5 the only way to keep APD out of its own source was a total plugin disable in `.claude/settings.local.json` (`"claude-apd@zstevovich-plugins": false`). That worked but cost the framework developer access to slash skills + MCP tools while working in the dev repo itself. `resolve-project.sh` now flags `APD_FRAMEWORK_SELF=true` when the resolved `PROJECT_DIR` contains BOTH `plugins/apd/VERSION` AND `.claude-plugin/plugin.json` with `"name": "claude-apd"`. When the flag is set, `APD_ACTIVE=false` is forced regardless of whether a config file exists. `apd-init` prints a one-line "framework dev mode" message and exits 0 (`--quick` stays silent for hook callers). `session-start` emits a once-per-session banner and exits 0 before any scaffolding can run. Guards (which already no-op on `APD_ACTIVE=false`) stay silent. Skills + MCP tools register normally because CC handles those at the plugin level, not via APD's activation marker — so enabling `claude-apd@zstevovich-plugins` in `settings.local.json` now gives the framework developer slash skills + MCP without auto-scaffolding the framework into a managed consumer project. Override for dogfooding the framework on itself: `APD_FRAMEWORK_DEV_MODE=force-enable`. New `test-codex-adapter` §48 (6 assertions: detection on real markers, force-enable override restores activation, foreign plugin.json doesn't false-positive, apd-init message + no scaffold writes, --quick silent exit). Test count 397 → 403. CLAUDE.md Critical Rules section documents the new flag + override.

## v6.4.0 — 2026-05-12

v6.3 audit cleanup + Codex config drift mitigation. Tests: 369 → 397.

- **fix: nine logic-quality findings from v6.3.0 audit.** Max-effort code review across the non-Codex-adapter framework caught 1 CRITICAL + 4 HIGH + 3 MEDIUM + 1 LOW issue. CRITICAL: `guard-bash-scope` checked "any path in scope" rather than "the write target in scope" — `cp src/innocent /etc/passwd` passed when scope=src/. Now identifies the actual destination per write-op family (redirects, tee, cp/mv/install positional tail, dd of=, mkdir/touch/rm/rmdir args, sed -i files after pattern; BSD/GNU sed handled, octal escape for embedded quotes in awk source). HIGH: spec re-advance now wipes `.builder-count`/`.reviewer-count` (was carrying counters across tasks, blocking fresh tasks with misleading prior-task messages); `gh-sync` uses `jq --arg t "$ARG2"` + `contains($t)` to prevent injection; `verify-apd` parses the actual spec-card heading format (was matching `^# Task:` which the template never emits, so Section 8 always skipped); `workflow.md §0b` reworded "every dispatch costs a cycle" → "every `pipeline-advance <phase>` call costs a cycle" to match code semantic. MEDIUM: zombie sweep filters by ancestor PID chain (no more cross-terminal false positives); reviewer rollback clears stale `.adversarial-summary`; `apd-init` eager `.apd-version` sync drops `[ -n "$PROJ_V" ]` guard so missing files get the version too. LOW: `rotate-session-log` uses `wc -l | tr -d ' '` instead of `grep -cv … || echo 0` (was producing multi-line "0\n0" in archive metadata). New `test-codex-adapter` §44 (16 assertions: 8 pre-audit bug repros + 8 happy paths covering cp/mv/sed -i BSD+GNU/rm/mkdir/tee/dd/multi-file) + §45 (1 assertion: rollback to reviewer clears stale summary). Test count 369 → 386.
- **feat(cdx): v6.4 G1 — codex-doctor version-mismatch detection + --fix.** Closes the live failure from the 2026-05-12 Test session on Codex 0.130.0: marketplace upgrade cleaned v6.2.0 but project `.codex/config.toml` cwd still pointed there, Codex MCP startup failed with "No such file or directory (os error 2)". Doctor's Project `.codex/` section now reads cwd from `[mcp_servers.apd]` (awk-based), extracts the version (sed regex `cache/codex-apd/apd/<X.Y.Z>`), and compares with installed plugin cache versions (`sort -V` picks highest). Three branches: stale (cwd dir no longer exists in cache) → BAD with explicit recovery command; older-but-still-installed → WARN with migration hint; matching → silent. The new `--fix` flag at the script entry parses out of `$@` before the optional project-path positional; when version-mismatch detected, invokes the latest-installed plugin's `apd cdx init <project>` to rewrite the config.toml. Closes the v6.4 G1 backlog item from `project-v6.4-codex-config-drift-backlog.md`. New `test-codex-adapter` §46 (5 assertions: stale-detection, recovery-hint path, older-version warn, matching-silent, --fix-invokes-recovery). Test count 386 → 391.
- **feat(cdx): v6.4 G2 — `[features].codex_hooks` → `[features].hooks` rename.** Codex 0.130 renamed the hooks feature flag and emits a per-session deprecation warning when only the old key is present. Plugin never wrote the flag directly (only printed CLI hints + checked for it in global config), so scope was detection + auto-recovery. `codex-doctor` Global Codex config section branches on four states: new-name-only (OK, Codex 0.130+ canonical), old-name-only (WARN with rename instructions; `--fix` does macOS-safe `sed -i.bak` rename in place), both (OK + soft warn about redundant deprecated key), neither (BAD with both-form enable hint). `install-codex-config` post-install hint now says `codex features enable hooks` (new form) with a one-line fallback for older Codex 0.121–0.125. `apd help` text updated to match. The legacy form is preserved in hints for now — once we have telemetry that no users are on pre-0.124, the fallback line can drop. New `test-codex-adapter` §47 (6 assertions: all four detection states + --fix rename + install hint mentions both forms). Test count 391 → 397.

## v6.3.0 — 2026-05-11

BambiProject Cycle 1 post-mortem — five framework backlog closures targeting both inter-dispatch overrun (3+ builder cycles for polish work) and the orchestrator-discipline failure modes surfaced by the 2026-05-11 incident. Test count: 328 → 361.

- **feat(pipeline): v6.3 D — spec-card max_defects immutability across re-advance.** `pipeline-advance spec` writes a `.spec-max-defects-history` snapshot (`<task>|<value>`) alongside `.spec-hash`. On subsequent spec advance for the same task name, raising `max_defects` (numeric > prev, or → `unlimited`) is BLOCKED. Lowering is allowed. Reset wipes the snapshot — the explicit escape valve for a real pivot. Closes the rollback+re-advance loophole that defeated the v6.1.2 B2 severity gate (BambiProject Cycle 1 spec-card amended `max_defects=0 → 6` mid-pipeline). Same bold/italic tolerance as the verifier-side parser. New `test-codex-adapter` §38 (7 assertions: first-write, raise-block, lower-allow, different-task-allow, reset-wipes, post-reset-fresh). Test count 328 → 335.
- **feat(rules): v6.3 E — orchestrator communication discipline.** Anti-epilogue rules in orchestrator-facing templates target the RLHF-default end-of-turn lessons-learned recap + "what I did + next steps" multi-bullet wrap-ups. (a) `plugins/apd/rules/workflow.md` — new `## 0a. Communication discipline` section before "Lean vs Full"; Do-NOT list (lessons-learned bullets, recaps, self-narration, restating user command, multi-paragraph wrap-ups) vs Do list (one-line state updates during work, one-sentence end-of-turn, real questions). (b) `plugins/apd/templates/CLAUDE.md.reference` — new `**Communication:**` critical-rule bullet alongside Author/Style. (c) `plugins/apd/templates/codex/AGENTS.md` — new `### Communication discipline` subsection under APD before Pipeline. Dispatch templates (builder/reviewer/adversarial) audited and left untouched — their structured output formats do not license epilogues. New `test-codex-adapter` §39 (6 assertions verifying anti-epilogue phrasing present in all three files). Test count 335 → 341. Existing projects scaffolded pre-v6.3 do not auto-pick up the rule; re-run `apd-init` or manual `workflow.md` refresh required.
- **feat(track-agent): v6.3 A — post-agent zombie sweep on SubagentStop.** `track-agent` SubagentStop branch now runs a process-table audit after every subagent stop. Catches polling-loop zombies (`while pgrep | while true | while sleep | tail -f | watch -n`) and gradle daemons left behind by the subagent's bash invocations. Closes the BambiProject Cycle 1 multi-hour gradle zombie: builder dispatched `while pgrep -f testDebugUnitTest; do sleep 5; done` which infinite-looped because the gradle daemon AND the polling shell both carried the matched pattern in argv. User manually `pkill`-ed 45 min later. Uses `ps -axo "pid= command="` (cross-platform; BSD pgrep lacks `-a`); filters out `track-agent`, `/claude`, sweep itself, `ps -axo`. Surfaces up to 5 hits as WARN to stderr + appends `<ts>|<agent>|<pid>|<cmd>` rows to `zombie-audit.log` under `MEMORY_DIR`. Informational — never blocks the agent stop event. Opt-out: `APD_ZOMBIE_SWEEP=0`. Pattern set deliberately excludes `node`/`python`/`dotnet` — too broad in dev-server-heavy projects, false positives erode trust. Still CC-only — Codex 0.128 has no SubagentStop hook equivalent. New `test-codex-adapter` §40 (5 assertions covering spawn-and-detect, audit-log capture, opt-out, no-stale-match after kill). Test count 341 → 346.
- **feat(pipeline): v6.3 C — builder cycle cap (max_cycles).** `pipeline-advance builder` now counts dispatches per task in `.builder-count` and blocks runaway re-dispatch loops. Default cap = 2 (one initial + one re-dispatch after reviewer rejection). Counter persists across rollback + re-advance — every dispatch costs a cycle. Reset wipes. Closes the BambiProject Cycle 1 runaway pattern (3 builder cycles for a polish task, ~28 min agent time). Override per spec via line in spec-card.md: `builder: max_cycles=4` (explicit higher cap with rationale), `builder: max_cycles=unlimited` (no cap). Parser uses the same bold/italic tolerance as `adversarial: max_defects`. Block message names three forward paths: (a) STOP and review whether implementation-plan.md is complete or adversarial is flagging the same issue repeatedly; (b) decompose into smaller tasks and reset; (c) raise the cap with rationale via rollback + re-advance. Counter is NOT incremented when blocked — re-running after rollback + cap raise starts from the same number, not one above. `workflow.md §0b` documents the field. New `test-codex-adapter` §41 (7 assertions: first/second advance under default cap, third blocked, no counter bump on block, raised cap, unlimited allows arbitrary dispatches, reset wipes). Test count 346 → 353.
- **feat(pipeline): v6.3 B — reviewer cycle cap + `pipeline_mode: polish`.** Scoped down from the original B memo. (a) Reviewer cycle cap (mirror of v6.3 C builder cap). `.reviewer-count` counter at `pipeline-advance reviewer`; default 2; override via `reviewer: max_cycles=N|unlimited`. Reset wipes. (b) `pipeline_mode: polish` preset. Lowers BOTH builder and reviewer default caps to 1 — no re-dispatch. Explicit per-phase `max_cycles` still takes precedence over the preset. Named `polish` (not `lean`) to avoid conflict with the existing "Lean" semantic (= `adversarial: skip` opt-out for tiny tasks). Deliberately deferred to v6.4: adversarial cycle cap (rare in practice; no `pipeline-advance adversarial` step; needs a different counter mechanism) + auto-spec follow-up for dismissed adversarial findings (separate feature, not a fix). `workflow.md §0b` renamed (singular → plural "phase cycle caps"), polish-mode subsection added. New `test-codex-adapter` §42 (8 assertions: default cap=2 first+second allow, third block, no bump on block, reset wipes, polish caps both at 1, explicit override beats preset). Side fix: §40 (v6.3 A zombie sweep) flakiness eliminated. Original wait loop checked pgrep visibility before invoking track-agent, but the sweep uses `ps -axo`, which has different process-table flush timing on some runs. Replaced with explicit ps-only wait (up to 2 s). 8-run stress test confirms stability. Test count 353 → 361. With `pipeline_mode: polish` + defaults, the BambiProject Cycle 1 second builder dispatch would have BLOCKED at #2, forcing human review at the right moment instead of 3 cycles of agent thrash.

## v6.2.0 — 2026-05-06

Diagnostics symmetry across both runtimes for stale plugin cache cleanup, plus SPEC threat-model rationale motivated by the CC 2.1.121–128 scan. Test count: 278 → 280.

- **docs(spec): rationale for guard-based enforcement.** Added a paragraph to §4.3 explaining why APD relies on guard `exit 2` + the compiled `validate-agent` Go binary instead of CC permission prompts. Motivated by CC 2.1.121 + 2.1.126: `--dangerously-skip-permissions` now skips writes to `.claude/skills/`, `.claude/agents/`, `.claude/commands/`, and the entire `.claude/`, `.git/`, `.vscode/`, and shell config files. Anyone running CC in that mode bypasses every permission rule, so APD's enforcement boundary cannot live there.
- **feat(cc): stale plugin cache detection in `pipeline-doctor`.** New block in §10 reads `~/.claude/plugins/installed_plugins.json`, finds the active `claude-apd@<marketplace>` install path, and lists sibling per-version cache directories not referenced by the JSON. Each is shown with `du -sh` size and a manual `rm -rf` hint. Read-only — no destructive action from the doctor. Detected 48 MB of stale cache on the development machine (3 dirs: 6.1.0, 6.1.1, 6.1.2). Verified `claude plugin prune` does not handle this scenario — it only cleans auto-installed dependencies.
- **fix(cc): remove broken `CACHE_NAME` warn from `pipeline-doctor` §10.** The pre-existing `basename(dirname($APD_PLUGIN_ROOT))` check had been a false-positive every run since v6.0 self-containment moved the plugin payload into `plugins/apd/` (`CACHE_NAME` always resolved to `plugins`, never to a version string). New stale-cache detection above covers the meaningful diagnostic; the broken block deleted.
- **feat(codex): symmetric stale plugin cache detection in `codex-doctor`.** New "Plugin cache" section between MCP server and Summary checks `$CODEX_HOME/plugins/cache/*` for sibling version dirs. Codex's v6.0+ self-contained cache layout makes the walk simpler: `$APD_PLUGIN_ROOT` is itself the version dir, so `dirname` lands on the version-parent directly. Dev-mode runs (`$APD_PLUGIN_ROOT` outside the cache prefix) print `_ok` "running from non-cache path" instead of false-positiving.
- **test: 2 new assertions in `test-codex-adapter` §15.** Asserts that `apd cdx doctor` output contains a `Plugin cache` section and that the dev-mode `running from non-cache path` skip fires (tests scaffold via `mktemp`, so APD_PLUGIN_ROOT is the dev repo path). Count 278 → 280.
- **docs(spec): §14 audit cleanup.** Removed 5 stale entries (Codex 0.121.0 marketplace blocker, slash-menu skill listing, .mcp.json gap, manifest version lag from §13 + §14) — all resolved in 0.124+ or v6.0. Reworded 3 entries (`SessionStart`, `codex exec`, pipeline reset) to drop stale version references ("v5.1 candidate", "v4.7.21+F2 docs"). 13 → 9 limitations.
- **test: regression coverage for `guard-bash-scope` read/write distinction.** New `test-codex-adapter` §27 (10 assertions) verifies that read commands (`cat`, `grep`, `head`, `tail`, `wc`, `less`) on `.apd/pipeline/spec-card.md` ALLOW (exit 0) and write commands (`>`, `>>`, `cp`, `rm`, `sed -i`) BLOCK (exit 2). Closes the 2026-04-10 Bambi Run #9 false-positive memo as RESOLVED on current master (the original bug does not reproduce; coverage prevents future regression).
- **feat(pipeline-gate): stage completeness soft warn.** After `.done` signature verification succeeds, `pipeline-gate` now lists modified files in any dispatched builder's scope that are not staged for commit. Reads `.apd/pipeline/.agents` for dispatched builders, finds each agent file (`.apd/agents/<name>.md` or `.claude/agents/<name>.md`), extracts scope from either Codex YAML `scope:` list or CC inline `guard-scope <paths>` hook command, and cross-references against `git diff --name-only` + `git ls-files --others --exclude-standard`. Soft warn — exit 0 always (per memo: sometimes files are intentionally left out). Closes the 2026-04-16 BambiProject "Verifikacija emaila #31" miss (RegisterScreen.kt left out of a 22-file commit). New `test-codex-adapter` §28 (4 assertions: positive warn + file naming + no-false-positive when staged + no-false-positive out-of-scope). Test count 280 → 294.
- **feat(track-agent): CC parallel same-type dispatch gate.** `track-agent` SubagentStart now blocks (exit 2) when an agent of the same `agent_type` started within `APD_PARALLEL_WINDOW` seconds (default 30) and has not emitted a matching `SubagentStop` for its `agent_id`. Closes 2026-04-16 BambiProject #48 (3× backend-api dispatched in 34s, drove orchestrator into destructive-git recovery). Cross-platform epoch math (`date -j` BSD / `date -d` GNU). Different agent types are unaffected. `APD_PARALLEL_WINDOW=0` disables the gate. CC-only — Codex has no equivalent hook surface (per `reference-codex-0.128-doc-verified.md`); Codex side requires orchestrator discipline. New `test-codex-adapter` §29 (5 assertions: first dispatch ALLOW + parallel BLOCK + different-type ALLOW + after-stop ALLOW + window=0 ALLOW). Test count 294 → 299.
- **fix(apd-init): mkdir deny coverage.** `apd-init` settings.json `permissions.deny` block extended from 4 to 8 patterns. The original 4 all required a `*/` prefix (e.g. `Bash(mkdir */.apd/pipeline)`), which CC's glob does not match against the bare form `mkdir .apd/pipeline` — the most common orchestrator pre-pipeline command. New 4 patterns cover the bare form (`Bash(mkdir .apd/pipeline)`, `Bash(mkdir -p .apd/pipeline)`, `Bash(mkdir .apd/pipeline/*)`, `Bash(mkdir -p .apd/pipeline/*)`). `permissions.deny` overrides hook-ask since CC 2.1.101, so the prompt never appears — naive users no longer get the chance to approve a destructive directory create. Defense in depth still includes `guard-bash-scope` and `guard-pipeline-state`. New `test-codex-adapter` §30 (9 assertions: settings.json exists + each of the 8 deny patterns present verbatim). Test count 299 → 308.
- **test: lock-in `pipeline-advance spec` hard block.** Existing behavior since v3.6.0 (lines 184-198) — exits 1 when `spec-card.md` is missing or has no `R*` acceptance criteria — was never covered by an automated test. New `test-codex-adapter` §31 (2 assertions). Closes the spec-card side of `project-enforcement-gaps`; the adversarial-summary side is superseded by the v6.1 `.adversarial-pending` hard gate (already covered by §23/§25). Test count 308 → 310.
- **test: lock-in `pipeline-advance builder` hard block on missing plan.** Existing behavior (lines 240-244) — builder exits 1 when `.apd/pipeline/implementation-plan.md` is absent — was never covered by an automated test. New `test-codex-adapter` §32 (1 assertion). Closes `project-implementation-plan-step` (the plan-as-precondition design ships as builder-step gate rather than a separate `pipeline-advance plan` subcommand). Test count 310 → 311.
- **test: lock-in `superpowers:` agent prefix rejection.** Existing behavior (`pipeline-advance` lines 257-265 reviewer + 363-371 builder) — reviewer/builder steps reject any `.agents` `stop` event whose `agent_type` matches `^superpowers:` and emit `BLOCKED: No project Reviewer/Builder agent was dispatched!` with guidance toward `Agent({ subagent_type: "code-reviewer", ... })` — was never covered by an automated test. New `test-codex-adapter` §33 (2 assertions: rejection exit + guidance message). Closes `feedback-superpowers-conflict`; superpowers is also disabled at the `enabledPlugins` level by `apd-init`. Test count 311 → 313.
- **feat(mcp): `apd_pipeline_metrics()` 9th MCP tool.** Reads `.apd/memory/pipeline-metrics.log` and returns structured runs (timestamp, task, phase ts, status, adversarial summary T/A/D, agent counts). `limit` arg caps recent runs (0 = all, max 200). Closes the v6.1 deferred item; replaces the `apd-miro` workaround that read the log directly. Also wired into `install-codex-config` `_APD_TOOLS` tuple, `codex-doctor` `EXPECTED_TOOLS` list, and `plugins/apd/.mcp.json` per-tool approval block. New `test-codex-adapter` §34 (3 assertions: total/list, limit subset, numeric field parse) + §2 loop count adjusted from 8 → 9. Test count 313 → 317.
- **docs(skill): switch Codex `apd-miro` to `apd:apd_pipeline_metrics()`.** Procedure step 1 now calls the MCP tool instead of `cat .apd/memory/metrics.csv`; Exit criteria reference updated; `agents/openai.yaml` `default_prompt` rewrites the workaround language. Closes the v6.1.0 known gap noted in the original `apd_pipeline_metrics()` audit (CHANGELOG v6.1.0 A6 bullet). CC `skills/apd-miro/SKILL.md` is unchanged — CC uses the `bash .claude/bin/apd pipeline metrics` CLI shortcut, not MCP. No test impact.
- **feat(mcp): C2 Phase 2a — TOML agent parser support.** `apd_mcp_server` now reads Codex-canonical `.codex/agents/<name>.toml` files alongside the legacy `.apd/agents/<name>.md` format. New `_parse_agent_toml()` (via `tomllib` on 3.11+, `tomli` fallback) and `_parse_agent()` dispatcher; `_agents_dir()` priority is `.claude/agents/` → `.codex/agents/` → `.apd/agents/`. `apd_list_agents` globs both extensions; `apd_guard_write` tries `.toml` before `.md`. `--with tomli` added to `args` in `plugin .mcp.json`, `install-codex-config`, and `codex-doctor` so Python <3.11 has the parser. **No behavior change for existing users** — projects with only `.apd/agents/*.md` keep working. Test §35 (4 assertions: TOML list discovery + in-scope allow + out-scope block + legacy `.md` backward-compat). Test count 317 → 321. Phases 2b–2d (migration utility, flip default, sunset) deferred to subsequent v6.2 sessions.
- **feat(cdx): C2 Phase 2b — `apd cdx agents migrate` utility.** New subcommand in `agents-scaffold` converts `.apd/agents/*.md` → `.codex/agents/*.toml` in-place. Supports `--dry-run` (preview without writing) and `--force` (overwrite existing targets). Idempotent: re-run skips files that already exist. Source `.md` files are preserved so the legacy fallback in `_agents_dir()` continues to work. Output TOML has Codex-documented fields (`name`, `description`, `model`, `model_reasoning_effort`, `developer_instructions`) plus a clearly labelled "APD extensions" section (`max_turns`, `scope`, `readonly`). Body content uses `"""..."""` by default, falls back to `'''...'''` literal string if body itself contains `"""`. `bin/apd` help text + `agents-scaffold` help text updated. Test §36 (5 assertions: dry-run no-write, real migrate creates target, TOML field shape, idempotent skip, source preserved). Test count 321 → 326. Phases 2c (flip `add` default to `.toml`/`.codex/agents/`) and 2d (sunset `.md` fallback target v6.4) remain.
- **fix(cdx): codex-doctor surfaces migrate hint.** When `.apd/agents/` contains `.md` agent files but `.codex/agents/` has no `.toml` files, `codex-doctor` now warns and suggests `apd cdx agents migrate` so users discover the C2 migration path through their existing health check. Hint clears automatically once migration completes (counts go to 0/N+ on next run). Test §37 (2 assertions: hint appears + hint clears). Test count 326 → 328.

## v6.1.3 — 2026-05-04

CC + Codex plugin audit cleanup. Test count: 257 → 278. Verified against `developers.openai.com/codex/{hooks,subagents,mcp,plugins/build}`.

- **fix(cc): drop redundant monitor declaration.** `monitors/monitors.json` ran the same `session-start` script that already fires as `SessionStart` + `PostCompact` hooks. The monitor produced a "Monitor stream ended" notification every session with zero added behavior. Removed the file and the `monitors:` field in `plugin.json`; SPEC §11.1 + §19 + README + CLAUDE.md aligned with the monitor-less layout.
- **fix(cc): bump `APD_MIN_VERSION` to 2.1.101.** First CC release where the `SessionStart` hook fires reliably for plugins. `session-start` + `verify-apd` now read `MIN_CC_VERSION` from `plugins/apd/.apd-version` (relocated from repo root, where it had been orphaned since v6.0 plugin self-containment).
- **feat(codex): apply_patch / Edit / Write enforcement.** New `bin/core/guard-file-edit` (core) + `bin/adapter/cdx/guard-file-edit` (cdx shim) block file-edit targets that have not been pre-cleared by `apd_guard_write`. The MCP tool records cleared targets into `.apd/pipeline/.guarded-writes` (10 min TTL); the file-edit hook reads that cache. `install-codex-config` block 5a wires the `PreToolUse apply_patch|Edit|Write` hook into project `.codex/hooks.json`. `spec-card.md` + `implementation-plan.md` allowlisted; `.apd/pipeline/` state and outside-project paths block hard. Canonical payload `tool_name: "apply_patch"` per Codex docs.
- **fix(guard): runtime-write detection in protected dirs.** `guard-bash-scope` now also runs the runtime-write detector (node / python / ruby / php / perl `-e` writes) when the command targets the plugin cache or `.apd/pipeline/`, closing a shell-bypass for those paths. DRY refactor extracted `_runtime_write_detected` helper.
- **fix(codex): canonical agent frontmatter.** All 5 `templates/codex/agents/*.md` use `model: gpt-5.4` (was `sonnet`/`opus`) and `model_reasoning_effort: high` (was `effort: xhigh`). Documented Codex 0.128 model values are `gpt-5.3-codex-spark` / `gpt-5.4` / `gpt-5.4-mini`; canonical effort field is `model_reasoning_effort`. Closes the v6.1.1 deferred M4 item.
- **fix(codex): `AGENTS.md` template structure.** Replaced `<fill in>` placeholders with required `## Stack` / `## APD` / `### Pipeline` / `### Guardrails` / `### Mandatory skills` / `### Human gate` sections so freshly scaffolded projects pass `apd-audit` + `codex-doctor` checks. Skill refs use bare names (`apd-brainstorm`) instead of MCP-tool-style `apd:apd-brainstorm`.
- **fix(codex): `codex-doctor` extended checks.** Added `AGENTS.md` required-sections + `<fill in>` + file-edit hook wiring checks. Hybrid checkout `.claude/` warning softened.
- **fix(pipeline): reset clears `.guarded-writes`.** `pipeline-advance reset` rm-line includes the new clearance cache file.

## v6.1.2 — 2026-04-29

Hotfix from BambiProject live pipeline evidence: spec-card.md authored with markdown-bold around the `adversarial:` directive (`**adversarial:** skip — <reason>`) was not recognized by `pipeline-advance`'s opt-out parser. The verifier therefore demanded the adversarial pass even though the spec opted out — the user's workaround was to dispatch a trivial adversarial-reviewer to satisfy the gate.

- **fix(pipeline): markdown-bold tolerance on adversarial directive parsing.** Both `pipeline-advance` parser sites — the reviewer-step `adversarial: skip` opt-out (introduced in v3.x) and the verifier-step `adversarial: max_defects=N` severity gate (introduced in v6.1 B2) — relaxed their regex from `^adversarial:` to `^[-*_ \t]*adversarial[-*_ \t]*:`. Six skip-variant inputs and three max_defects bold-variant inputs now match: `**adversarial:**`, `**adversarial**:`, `*adversarial:*`, `- adversarial:`, `**Adversarial:**`, plus the original plain form. Test section 26 covers all variants. Tests: 248 → 257.

## v6.1.1 — 2026-04-29

Codex skill-payload quality fixes from the v6.1.0 audit. Test count: 246 → 248.

- **H1 — apd-brainstorm advance-vs-exit clarified.** Codex and CC brainstorm skill text now distinguishes "do not advance while asking questions / presenting options / revising design" from the required exit: after explicit user approval, write the spec-card.md and call the spec pipeline advance as the only valid exit. Codex `agents/openai.yaml` prompt now carries the same wording.
- **H2 — Codex-native audit evals.** Added three `runtime: codex` apd-audit scenarios covering missing builder scope, stale `.claude/` references in `AGENTS.md`, and missing APD MCP per-tool approval blocks. Canonical evals now total 27; `eval-mirror` keeps CC mirror at 24 by excluding Codex-only scenarios and keeps Codex mirror at 24.
- **H3 — Both-runtime eval fixtures seed AGENTS.md.** The brainstorm, GitHub Projects, and Miro "both" scenarios now materialize `AGENTS.md` alongside `CLAUDE.md`, so Codex skill behavior is not tested against Claude-only context.
- **M5 — skill-eval runtime filtering.** `skill-eval --list` now shows the `runtime` field. `--rubric` and `--judge` execute only scenarios whose `runtime` is `both` or matches `--runtime`; explicit `--dry-run --runtime <cc|codex>` validates the same no-spawn execution subset. Section 24 adds coverage for the Codex subset (21/27), raising `test-codex-adapter` to 248 checks.
- **Deferred M4 — Codex agent `model:` values.** Left `sonnet` / `opus` in Codex agent templates untouched. Needs an author decision on whether those fields are descriptive labels or runtime selectors before changing to `gpt-5.x`.

## v6.1.0 — 2026-04-28

Skill quality + pipeline gate refinements per `docs/plans/v6.1-skills-and-pipeline-improvements.md`. Test count: 226 → 246.

**Track A — Skills authoring quality**

- **A1 — Pushy descriptions across 15 skills.** Description field now leads with a third-person trigger statement, lists explicit trigger phrases, and uses MANDATORY for hard-required skills (apd-tdd, apd-debug, apd-finish). Targets undertriggering surfaced by skill-creator audit. CC + Codex mirrors. Char counts 373–556, all under the 1024 description limit.
- **A2 — Concrete examples in 5 skills.** Anthropic-format Input/Output Example blocks (2-3 per skill) added to apd-debug, apd-audit, apd-finish, apd-github, apd-miro for both CC and Codex mirrors. Each example grounds the skill methodology in a realistic scenario: failing-test → root-cause walks for apd-debug, audit recommendation blocks for apd-audit, decision trees for apd-finish, lifecycle states for apd-github, and frame-update before/after for apd-miro.
- **A3 — Terminology consistency sweep.** Glossary normalized across all 15 skill files: `pipeline step → pipeline phase`, `acceptance criteria → R-criteria`, `Result: X issues → X findings`, `structural issue → structural finding`, `spec card → spec-card.md` for file references. The literal `## Spec card` heading inside sample issue bodies is left as-is.
- **A4 — Eval framework.** Scenario-driven evaluation harness for every shipped skill. Canonical source `plugins/apd/evals/<skill>/*.json` (24 scenarios — 8 skills × 3 each); `bin/core/skill-eval` runner with `--list`, `--dry-run`, `--rubric`, `--judge` modes; `bin/core/eval-mirror` syncs canonical scenarios into `skills/<skill>/evals/` (CC) and `plugins/apd/skills/<skill>/evals/` (Codex). Evals are advisory, not a pipeline gate. Spec under `plugins/apd/evals/README.md`.
- **A5 — Progressive disclosure for `apd-setup`.** Split the 389-line monolith SKILL.md (over Anthropic's 500-line soft ceiling for active-context skills, and frequently triggered) into a 140-line top-level guide plus three on-demand `reference/` files: `agent-templates.md` (auto-detect rules + builder/reviewer specs), `rules-templates.md` (CLAUDE.md sections, verify-all, rules, memory, settings, gitignore, MCP recommendations), and `init-checklist.md` (gap analysis table + example walkthrough + verification). SKILL.md links to each reference using Anthropic Pattern 1 (`See [reference/Y](reference/Y)`). CC-only — Codex `apd cdx init` CLI is unaffected.
- **A6 — Fully-qualified MCP tool names in Codex skills.** 83 bare references to APD MCP tools (`apd_advance_pipeline`, `apd_pipeline_state`, `apd_guard_write`, etc.) across 7 Codex `SKILL.md` + 7 `agents/openai.yaml` files now use Anthropic's `ServerName:tool_name` form (`apd:apd_advance_pipeline`, …). Audit also surfaced three references to a non-existent `apd_pipeline_metrics()` tool in `apd-miro`; replaced with a documented combination of `apd:apd_pipeline_state()` plus a direct `.apd/memory/metrics.csv` read until a metrics MCP tool ships.
- **A7 — Time-sensitive language audit.** Single hit: `apd-tdd` Codex SKILL.md pinned the `apd_role` parameter workaround to Codex 0.121.0. Rephrased as version-free ("Codex's multi_agent role-mismatch approval prompt") so the note ages cleanly across Codex releases.

**Track B — Pipeline gate refinements**

- **B1 — Adversarial pre-flight gate.** Closes the bambi run #34 ~2m wasted dispatch surfaced when adversarial-reviewer was triggered before reviewer.done. Two-prong gate:
    - **Hard (mechanical):** CC `track-agent` SubagentStart exits 2 when `adversarial-reviewer` is dispatched without `reviewer.done` OR without the `.adversarial-pending` marker (= adversarial opted out or already recorded). Codex `apd:apd_adversarial_pass` refuses early at the recording step with a parallel error.
    - **Soft (instruction):** `plugins/apd/rules/workflow.md` step 6b spells out the order gate; both `apd-tdd` SKILL.md Hand-off blocks (CC + Codex) point at the marker as the green light; `apd:apd_advance_pipeline` and `apd:apd_adversarial_pass` MCP docstrings name the gate.
    - test-codex-adapter section 23 covers all three branches per runtime (no marker → block, only reviewer.done → block, both markers → accept) plus a fourth check that regular `code-reviewer` dispatch is never caught by the adversarial gate. 232 → 239 checks.
- **B2 — Severity gate (`max_defects` spec-card field).** New optional `adversarial: max_defects=N|unlimited` line in `spec-card.md` lets the user opt into a strict severity threshold. `pipeline-advance verifier` parses the field and refuses to advance when the adversarial dismissed-defect count (`D` in `ADVERSARIAL:T:A:D`) exceeds the budget. Default (field absent) = `unlimited` — same behavior as pre-v6.1, no migration cost. Both `apd-brainstorm` skill files (CC + Codex) recommend per task size: hotfix → `unlimited`, real task → `0`, complex → `0` or `N` with rationale. test-codex-adapter section 25 covers parse + decision branches: `max_defects=2` (parsed, D=8 > 2 → block, D=2 → allow), missing field (default unlimited), `max_defects=unlimited` (explicit), colon variant `max_defects: 3`, plus a smoke test on the BLOCKED message wording. 239 → 246 checks.
- **B3 — maxTurns bump across the board.** Bambi run #34 produced 2 maxTurn exhausts on 7-R features (code-reviewer hit at 4m 8s, adversarial-reviewer at 5m+) and live builder runs showed re-dispatch mid-feature too. Memory feedback `feedback-maxturn-counterintuitive-speedup.md` already validated higher maxTurns wins because re-dispatch costs more turns than running through. Final landscape:
    - **Builders** (backend, frontend, testing, master `agent-template.md`): `40 → 60`
    - **Reviewers** (`reviewer-template.md`, `adversarial-reviewer-template.md` + matching Codex variants): `30 → 80`
    - Reviewers get the larger budget because they walk every file in the diff; builders write code in chunks. testing was at 30 pre-bump (drift); now aligned with the builder default at 60.
    - workflow.md, apd-setup SKILL + reference docs updated. Test count unchanged (246) — the change is purely data-value.

**Other**

- `docs/SPEC.md` 7.2 updated to 7 Codex skills (was stale at 4); new 7.3 section documents the eval framework; test-codex-adapter check count updated.

## v6.0.3 — 2026-04-27

Critical regression fix for CC users on v6.0.x. Session-start hook reported
`guard-git`, `pipeline-advance`, and `pipeline-gate` as MISSING, breaking
the pipeline.

**Root cause.** v6.0 moved every framework binary into `<repo>/plugins/apd/`,
but `bin/lib/resolve-project.sh` still set `APD_PLUGIN_ROOT = $CLAUDE_PLUGIN_ROOT`
verbatim when CC was running the hook. CC sets `CLAUDE_PLUGIN_ROOT` to the
plugin cache **repo root** (e.g. `~/.claude/plugins/cache/.../6.0.1/`),
not the plugin folder. So `SCRIPT_DIR = $APD_PLUGIN_ROOT/bin/core` resolved
to a path that no longer exists in v6.0+ (`bin/` lives under
`plugins/apd/`, not at root). Direct script invocation kept working
because the fallback branch walked up from `${BASH_SOURCE[0]}` to land
inside `plugins/apd/`. The mismatch only surfaced under CC hook execution.

**Fix.** `resolve-project.sh` now detects v6.0+ layout and adjusts:
when `$CLAUDE_PLUGIN_ROOT/plugins/apd/bin` exists, set
`APD_PLUGIN_ROOT = $CLAUDE_PLUGIN_ROOT/plugins/apd`. Falls back to the
old behaviour for pre-v6.0 caches that still have `bin/` at the plugin
root, so users on a stale cache during transition keep working until
they `/plugin update`.

## v6.0.2 — 2026-04-27

Fixes Codex TUI prompting for APD MCP tool approval even though `plugins/apd/.mcp.json` declared every APD tool with `approval_mode = "approve"`.

Live Codex 0.125 testing showed that plugin-shipped MCP approval metadata is not applied by the TUI approval gate. `install-codex-config` now writes a project-local, complete `[mcp_servers.apd]` override into `<project>/.codex/config.toml`: `command = "uv"`, relative `mcp/apd_mcp_server.py`, `cwd = "<plugin-root>"`, plus all eight `[mcp_servers.apd.tools.<tool>] approval_mode = "approve"` blocks. This keeps plugin `.mcp.json` as the self-registration fallback while making the effective no-prompt path use Codex's working config surface.

Important detail: APD writes the full parent transport block, not just per-tool approval sections. Per-tool sections alone create an implicit TOML parent with no transport and Codex fails with `invalid transport in mcp_servers.apd`.

`codex-doctor`, `test-codex-adapter`, `docs/SPEC.md`, and `plugins/apd/mcp/README.md` were updated to match the hybrid model.

## v6.0.1 — 2026-04-27

`verify-apd` Section 8 (synthetic pipeline end-to-end test) now refuses to run when an active real-task pipeline is in flight. Previously, if the test got triggered (via `apd verify` re-run, or other code paths that invoke verify-apd) while a project was mid-pipeline, it would overwrite `spec-card.md` and `implementation-plan.md` with `APD-VERIFY-OPT-OUT`/`APD-VERIFY-TEST` content, append fake agent events to `.agents`, set the pipeline lock, and (when gh-sync is wired) open a GitHub issue — forcing a manual ~3-minute recovery to restore real state.

Hard guard added at the top of Section 8: skips the entire end-to-end test when any of these are true:
- `spec-card.md` exists with a task name not starting with `APD-VERIFY-` (or with no `# Task:` header at all)
- `.lock` directory present (another pipeline operation in flight)
- `spec.done` exists for a task other than an `APD-VERIFY-*` synthetic

When skipped, `verify-apd` prints a clear warning telling the user to `apd pipeline reset` first if they want to exercise the test, and surfaces the skip in the summary as `Pipeline: skipped (active pipeline)`. The remaining 8 sections still run as usual.

Reported live by a CC user during a real GDPR-delete task pipeline, with the same incident also having corrupted a previous welcome-bonus pipeline (commits `58dde25` etc.). No more silent overwrites.

## v6.0.0 — 2026-04-27 — Plugin self-containment

**Major refactor.** Every framework binary, template, rule, and the MCP server itself now live inside `plugins/apd/`. The Codex plugin cache, which only mirrors the plugin folder, finally contains everything the MCP server needs — closing the v5.0.9–10 plugin-shipped `.mcp.json` gap that was reverted in v5.0.11. `install-codex-config` becomes cleanup-only for the MCP server section; per-project `<project>/.codex/config.toml` no longer carries `[mcp_servers.apd*]` blocks.

### Layout changes (repo root → `plugins/apd/`)

```
bin/        →  plugins/apd/bin/
mcp/        →  plugins/apd/mcp/
rules/      →  plugins/apd/rules/
templates/  →  plugins/apd/templates/
VERSION     →  plugins/apd/VERSION
```

Stays on the repo root (CC plugin auto-discovery + repo tooling):

- `.claude-plugin/{plugin.json,marketplace.json}` — CC manifests
- `hooks/hooks.json` — auto-discovered by Claude Code from `${CLAUDE_PLUGIN_ROOT}/hooks/`
- `skills/` — auto-discovered by Claude Code (top-level CC skills, including the CC-only `apd-setup`)
- `monitors/monitors.json` — referenced by `.claude-plugin/plugin.json` relative to repo root
- `.agents/plugins/marketplace.json` — Codex marketplace manifest
- `bump-version`, `.gitignore`, `README.md`, `CHANGELOG.md`, `LICENSE`, `docs/`, `examples/`

### MCP server self-registration

`plugins/apd/.mcp.json` now ships with the plugin and registers the APD MCP server with `cwd: "."`. Codex auto-loads this from the plugin cache at `~/.codex/plugins/cache/codex-apd/apd/<v>/`, which now contains `mcp/apd_mcp_server.py`. Per-tool approval modes for all 8 tools live in the same manifest under `mcpServers.apd.tools.<name>.approval_mode`.

### Migration for existing users

`apd cdx init` (i.e. `install-codex-config`) detects any legacy `[mcp_servers.apd]` and `[mcp_servers.apd.tools.<tool>]` blocks in `<project>/.codex/config.toml` and removes them. Backup of the original is written next to the file (`config.toml.bak.<epoch>`). After upgrading the plugin via `codex plugin marketplace upgrade codex-apd`, run `apd cdx init` once per project to clean up the legacy blocks.

### Path reference updates

- `${CLAUDE_PLUGIN_ROOT}/bin/...` → `${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/...` in all CC hooks, monitors, top-level CC skills, agent templates, and example agent files
- `APD_PLUGIN_ROOT` (computed by every script) now resolves to `plugins/apd/` instead of repo root. Scripts that need repo-root-only paths (the Codex marketplace manifest, top-level skills) reference an explicit `REPO_ROOT="$APD_PLUGIN_ROOT/../.."` instead
- `bump-version` updates `plugins/apd/VERSION`, `plugins/apd/.codex-plugin/plugin.json`, and `.agents/plugins/marketplace.json` in addition to the CC manifests

### Tests

`bin/core/test-codex-adapter` reorganised: 213 passing checks (was 209 before v6.0). New checks cover plugin `.mcp.json` validity, `cwd: "."`, all 8 per-tool approval entries, and migration of legacy `[mcp_servers.apd*]` blocks. `codex-doctor` now flags legacy MCP blocks and verifies plugin `.mcp.json` presence.

### Breaking

- Anyone with hardcoded `apd-template/bin/...` or `apd-template/mcp/...` paths in external scripts must update to `apd-template/plugins/apd/bin/...` etc.
- Pre-v6.0 `.codex/config.toml` files keep working until `apd cdx init` is rerun, but the plugin-shipped registration takes precedence — running both can cause Codex to spawn the MCP server twice.

## v5.0.11 — 2026-04-27

Fourth patch in the v5.1 chain. Reverts the v5.0.9-10 plugin .mcp.json self-registration experiment after a second live-test crash.

### What broke (again)

After v5.0.10 shipped, `codex plugin marketplace upgrade codex-apd` pulled the new `plugins/apd/.mcp.json`. Codex started without the v5.0.9 `invalid transport` crash (good), but `apd_ping` failed with:

```
⚠ MCP client for `apd` failed to start: MCP startup failed: handshaking with MCP server failed: connection closed: initialize response
```

`~/.codex/log/codex-tui.log` shows the actual cause:

```
MCP server stderr (uv): can't open file '/Users/zoranstevovic/.codex/plugins/cache/codex-apd/mcp/apd_mcp_server.py': [Errno 2] No such file or directory
```

### Root cause

The Codex plugin cache layout is narrower than we assumed. After `codex plugin marketplace upgrade`, the plugin lives at `~/.codex/plugins/cache/codex-apd/apd/<version>/` and contains only the contents of `plugins/apd/` from the repo — `.codex-plugin/`, `.mcp.json`, `skills/`. It does **not** include `mcp/apd_mcp_server.py`, `bin/core/*`, `bin/adapter/cdx/*`, or `VERSION`, all of which live at the repo root *outside* the plugin directory. With `cwd: "../.."` in our manifest, Codex resolved cwd to `~/.codex/plugins/cache/codex-apd/` and spawned `uv run python mcp/apd_mcp_server.py` from there — file not found.

Plugin-shipped self-registration is fundamentally incompatible with our current layout. The fix is to move `mcp/`, `bin/`, and `VERSION` into `plugins/apd/` (plugin self-containment), which is a structural refactor — v6.0 territory, not a patch. Until then, the absolute-path writer in `install-codex-config` stays.

### Revert

- **Removed: `plugins/apd/.mcp.json`** — broken self-registration entry.
- **`bin/adapter/cdx/install-codex-config`** — restored to v5.0.8 behaviour. Writes `[mcp_servers.apd]` (command + args, absolute path to the active checkout's `mcp/apd_mcp_server.py`) plus 8 per-tool `[mcp_servers.apd.tools.<name>]` approval blocks. The legacy block is no longer "removed on next run"; it is now the canonical block we want there.
- **`bin/adapter/cdx/codex-doctor`** — MCP checks reverted to config.toml-based (looks for `[mcp_servers.apd]` + 8 per-tool blocks; warns when path doesn't match `APD_PLUGIN_ROOT`).
- **`docs/SPEC.md` §3, §12, §18.1** — reverted to v5.0.8 wording, with a new explanatory paragraph at the end of §3 documenting the failed v5.0.9-10 attempt as a cautionary note pointing at the v6.0 plugin-self-containment refactor.
- **`bin/core/test-codex-adapter`** — back to the v5.0.8 form. Total 211 → 209 PASS / 0 FAIL (the 2 plugin-mcp-specific checks added in v5.0.10 are gone with their feature).

### Lessons

- The "test through marketplace" rule held: v5.0.9 and v5.0.10 both passed all 211 unit tests because the framework tests run against the dev repo where `mcp/apd_mcp_server.py` exists at `${APD_PLUGIN_ROOT}/mcp/`. The marketplace cache is a different path layout entirely. Only the live `codex plugin marketplace upgrade` + TUI session catches this.
- Feedback memory updated: don't assume the plugin cache mirrors the repo; check what files Codex actually copies into `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/` before designing plugin-relative paths.

### Live unblock for users on v5.0.10

If your project's `.codex/config.toml` was emptied during the v5.0.10 attempt, run `apd cdx init` once v5.0.11 ships — it will rewrite `[mcp_servers.apd]` and per-tool approvals back into the file.

## v5.0.10 — 2026-04-26

Third patch in the v5.1 chain. Emergency fix for v5.0.9 — live test caught a Codex startup crash that local-cache testing would have missed.

### What was broken in v5.0.9

v5.0.9 shipped `plugins/apd/.mcp.json` and stopped writing top-level `[mcp_servers.apd]` into user config.toml — but kept writing the eight `[mcp_servers.apd.tools.<name>]` per-tool approval blocks. After running `apd cdx init` on a v5.0.9 project, `<project>/.codex/config.toml` contained only the per-tool blocks. TOML semantics implicitly defines `mcp_servers.apd` as a parent table whenever any `[mcp_servers.apd.tools.<name>]` block exists; that parent had no `command` / `url`, so Codex refused to start: `Error loading config.toml: invalid transport in mcp_servers.apd`. Per-tool blocks cannot legally exist without a parent transport block in user config.

### Fix

- **`plugins/apd/.mcp.json` gains a `tools` field.** Codex `RawMcpServerConfig` accepts `tools: HashMap<String, McpServerToolConfig>` per `codex-rs/config/src/mcp_types.rs:241`; `McpServerToolConfig` carries the `approval_mode` field (line 56). All eight APD tools (`apd_ping`, `apd_doctor`, `apd_advance_pipeline`, `apd_guard_write`, `apd_verify_step`, `apd_adversarial_pass`, `apd_list_agents`, `apd_pipeline_state`) now declare `approval_mode = "approve"` inside the plugin manifest itself. Codex picks them up alongside the server registration.
- **`bin/adapter/cdx/install-codex-config` is cleanup-only.** It writes nothing under `[mcp_servers.apd*]`; on re-run it strips both pre-v5.0.9 top-level `[mcp_servers.apd]` and v5.0.9 per-tool `[mcp_servers.apd.tools.*]` blocks. If config.toml has nothing to clean, the script is a no-op (the file is not even created).
- **`bin/adapter/cdx/codex-doctor` updated.** New OK check: plugin `.mcp.json` includes per-tool approvals for all 8 APD tools. New BAD check: legacy `[mcp_servers.apd.tools.*]` block(s) still in user config.toml — explains the `invalid transport` crash and points at `apd cdx init` for cleanup.

### Doc updates

- `docs/SPEC.md` §3 — clarifies that all MCP config (server + per-tool approvals) ships in plugin `.mcp.json` since v5.0.10.
- `docs/SPEC.md` §12 (configuration surfaces) — `<project>/.codex/config.toml` row reworded as cleanup-only.
- `docs/SPEC.md` §18.1 — Step 1 of `install-codex-config` is now "MCP cleanup-only" with a pointer back to v5.0.10 motivation.

### Tests

- `bin/core/test-codex-adapter` — replaced `wrote per-tool approval blocks` assertion with `first install skips MCP cleanup on empty config (nothing to remove)`. Replaced eight `config.toml auto-approves <tool>` checks with eight `plugin .mcp.json auto-approves <tool>` checks. Added a hard fail-on-presence check for `[mcp_servers.apd*]` in user config. Repair test now expects "[removed] legacy APD MCP block" instead of "[updated] APD per-tool approvals". TOML parse check now skips when config.toml doesn't exist (no-op installs leave it absent). Total 210 → 211 PASS / 0 FAIL.

### Live unblock

If you ran `apd cdx init` on v5.0.9 and Codex now refuses to start with `invalid transport in mcp_servers.apd`, empty the project config (or run v5.0.10's `apd cdx init` once it ships):

```bash
> <project>/.codex/config.toml          # one-shot unblock
# OR after v5.0.10 marketplace-upgrade:
bash <project>/.codex/bin/apd cdx init   # cleanup happens automatically
```

## v5.0.9 — 2026-04-26

Second patch in the v5.1 chain. Plugin self-registers its MCP server via `plugins/apd/.mcp.json`; closes the v5.0.6 exec-mode bootstrap gap.

### What was broken

`install-codex-config` wrote `[mcp_servers.apd]` into every user's `<project>/.codex/config.toml` with the absolute path to the dev checkout's `mcp/apd_mcp_server.py`. That worked locally but was the root cause of every "MCP path is stale" repair, every WARN about plugin MCP overwriting earlier definitions, and the entire reason `codex exec` had no automatic APD bootstrap (the user-config block had to be written manually first via `apd cdx init`, which doesn't fire in exec mode).

### Fix

- **New file: `plugins/apd/.mcp.json`** registers the APD MCP server with `command: "uv"`, `args: ["run", "--with", "mcp", "python", "mcp/apd_mcp_server.py"]`, `cwd: "../.."`. Codex 0.124+ auto-loads plugin-shipped `.mcp.json` (`core-plugins/loader.rs::normalize_plugin_mcp_server_value`), normalises `cwd` against the plugin root (`plugins/apd/`), and the resulting `cwd = repo-root` is then applied to the stdio launcher's `Command::current_dir` (`rmcp-client/stdio_server_launcher.rs:231`). The Python server already self-locates via `Path(__file__).resolve().parent.parent`, so it finds the rest of the repo from there.
- **`bin/adapter/cdx/install-codex-config` no longer writes `[mcp_servers.apd]`.** That block is now provided by the plugin. The installer keeps the per-tool `[mcp_servers.apd.tools.<name>]` approval blocks (plugin `.mcp.json` doesn't carry per-tool approvals). Crucially, the existing replace logic still treats `[mcp_servers.apd]` as APD-owned, so any legacy block from APD < v5.0.9 is **removed on next run** — without that cleanup, Codex would print "plugin MCP overwrote earlier server definition" on every session.
- **`bin/adapter/cdx/codex-doctor` updated.** Old check ("config.toml has `[mcp_servers.apd]`") now reports a WARN if it finds the legacy block, and a new check confirms `plugins/apd/.mcp.json` registers the apd server. A second new check verifies all 8 per-tool approval blocks are present.

### Why `cwd: "../.."`?

The plugin's MCP server (`mcp/apd_mcp_server.py`) lives at the repo root — outside the plugin directory itself — because it depends on `bin/core/*`, `bin/adapter/cdx/*`, and `VERSION` which all live at the repo root. The `cwd: "../.."` value places the spawned process at `plugins/apd/../..` = repo root, which is what the Python server expects via its `__file__`-based path resolution. A future major release will move all of this into a self-contained `plugins/apd/` and drop the `../..`.

### Doc updates

- `docs/SPEC.md` §3 (MCP server) — explains the plugin .mcp.json registration path, the `cwd: "../.."` rationale, and the residual install-codex-config role.
- `docs/SPEC.md` §12 (configuration surfaces) — `<project>/.codex/config.toml` row reworded: "8 per-tool approval blocks; `[mcp_servers.apd]` ships in plugins/apd/.mcp.json".
- `docs/SPEC.md` §18.1 (install-codex-config steps) — Step 1 reworded as "per-tool approvals + legacy cleanup".

### Tests

- `bin/core/test-codex-adapter` — replaced "config.toml has `[mcp_servers.apd]`" check with a paired "no legacy block" + "plugin .mcp.json registers apd". Repair test now asserts the legacy block is removed instead of rewritten. Doctor label scan updated. Total: 209 → 210 PASS / 0 FAIL.

### Live verification still needed

This patch ships untested-in-TUI per the marketplace-only rule. Next step is `codex plugin marketplace upgrade codex-apd` on `~/Projects/Test`, then a fresh TUI session to confirm `apd_ping` works **without** `install-codex-config` having pre-written the server block.

## v5.0.8 — 2026-04-26

First patch in the v5.1 chain. Surfaces a real install bug discovered during the v5.0.7 live marketplace test on `~/Projects/Test`.

### What was broken

`apd cdx skills install` defaulted to `direct-drop` mode (symlinks into `~/.codex/skills/apd-*`). That default was correct for Codex 0.121.0 because the marketplace install path was upstream-blocked (openai/codex#18258). On Codex 0.124+ the marketplace path works, the plugin cache populates correctly, and skills surface in the `/` slash menu — but the legacy `~/.codex/skills/apd-*` symlinks coexist with the plugin cache and produce **duplicates in the slash menu** (4 historical Codex skills shown twice; the 3 newly-ported v5.0.7 skills shown once because they had no legacy symlinks).

### Fix

- **`bin/adapter/cdx/skills-install` default flipped to marketplace.** `apd cdx skills install` (no flag) now registers the local marketplace and enables `[plugins."apd@codex-apd"]` instead of writing user-level symlinks. Reflected in subcommand dispatch: `MODE` now defaults to `marketplace`.
- **`--legacy-symlink` flag retained** (alias `--direct`, `--symlink-mode`). Existing automation that explicitly opts into direct-drop continues to work, but the script now prints a deprecation banner on every run explaining why the mode is bad on 0.124+ and pointing the user at the new default. The flag will be removed in a future major.
- **`--marketplace` install no longer prints the `EXPERIMENTAL` warning.** That warning was specific to 0.121's broken path-resolution; on 0.124+ the install is the supported flow. Replaced with a one-liner pointing the user at `codex plugin marketplace upgrade codex-apd` for the cache-refresh step.
- **`status` output reordered.** Marketplace block now leads (labeled "default since v5.0.8"); direct-drop block follows under a "deprecated" header.

### Doc updates

- `docs/SPEC.md` §1 (install matrix) and §19 (skill install spec) — reworded to match the new defaults.
- `bin/adapter/cdx/skills-install` header comment rewritten to lead with marketplace and label direct-drop as deprecated.
- `bin/adapter/cdx/skills-install` help text updated to surface `--legacy-symlink` instead of bare `--copy` / `--force` flags.

### Tests

- `bin/core/test-codex-adapter` — three updates and two new checks. Old "default install creates 4 symlinks" reframed as "`--legacy-symlink` install creates 4 symlinks". New checks: `--legacy-symlink prints deprecation warning`, `status shows legacy Direct-drop section labelled deprecated`. Total 207 → 209 PASS / 0 FAIL.

### Live cleanup for existing installs

If you ran `apd cdx skills install` before v5.0.8 and now see duplicate APD skills in the slash menu, remove the legacy symlinks once:

```bash
rm ~/.codex/skills/apd-brainstorm ~/.codex/skills/apd-debug ~/.codex/skills/apd-finish ~/.codex/skills/apd-tdd
```

Then restart the TUI. The marketplace cache will continue to provide the skills.

## v5.0.7 — 2026-04-26

Skill quality release — every APD skill on both runtimes now conforms to a single canonical template, with explicit triggers, exit criteria, and anti-patterns. Closes the long-standing structural drift across the eight CC skills and brings the Codex side from 4 → 7 skills.

### Skill template canon

- **New file** — `templates/skill-template.md` codifies frontmatter (CC: `name`, `description`, `effort`, `allowed-tools`, optional `disable-model-invocation`; Codex: just `name` and `description`), a four-section mandatory body (When to use / When to skip · Steps · Exit criteria · Anti-patterns) plus two optional sections (Iron Law where the skill has a real invariant, Hand-off where transitions exist), and an effort taxonomy. Anti-patterns explicitly accepts two formats: "Don't → Do" pairs (procedural skills) and "Common rationalizations" tables (anti-self-deception, used by tdd / debug / brainstorm / finish).
- **Cross-runtime parity table** — eight CC skills, seven on Codex; `apd-setup` is intentionally CC-only because `apd cdx init` CLI replaces it.

### CC skills brought to compliance (8 of 8)

- **Frontmatter** — added missing `allowed-tools` to `apd-setup`, `apd-brainstorm`, `apd-finish`, `apd-github`, `apd-miro`. The remaining three already had it.
- **Body** — added explicit `When to use / When to skip`, `Exit criteria`, and `Hand-off` sections to all eight (most had implicit equivalents in `Integration` / checklist tail).
- **Specific fixes:**
  - `apd-setup` — Step 1's "MANDATORY: run init scripts" was a top-level paragraph; refactored into a numbered first step under `## Steps`. Renumbered the rest (1→2 detect, 2→3 gather, 3→4 auto-detect agents, 4→5 generate files with subsections renumbered 5.1–5.8, 5→6 verify). Added Anti-patterns and Hand-off (→ `apd-audit`) — previously had neither.
  - `apd-audit` — removed forced "Iron Law" line ("NO TASK WITHOUT A HEALTHY PIPELINE FIRST" wasn't really an invariant, just a recommendation).
  - `apd-github` and `apd-miro` — added Anti-patterns sections (had none before).
  - All four "Common Rationalizations" tables (audit, brainstorm, debug, tdd) renamed to lower-case "Common rationalizations" to match template wording.

### Codex skills brought to compliance + parity (4 → 7)

- **New ports** — `plugins/apd/skills/apd-audit/`, `plugins/apd/skills/apd-github/`, `plugins/apd/skills/apd-miro/`. Each ships a `SKILL.md` adapted for Codex (references `AGENTS.md` instead of `CLAUDE.md`, `.apd/agents/` instead of `.claude/agents/`, `apd_pipeline_state()` / `apd_doctor()` / `apd_verify_step()` MCP tools instead of bash commands, `${APD_PLUGIN_ROOT}` instead of `${CLAUDE_PLUGIN_ROOT}`) plus an `agents/openai.yaml` with `display_name`, `short_description`, and `default_prompt` (Codex per-skill UX metadata, distinct schema from the plugin manifest's `interface.defaultPrompt`).
- **Existing 4 Codex skills** (`apd-brainstorm`, `apd-debug`, `apd-finish`, `apd-tdd`) — added explicit `When to use / When to skip`, `Exit criteria`, and `Hand-off` sections to match the template. Bodies otherwise unchanged.

### Validation

- `bin/core/test-codex-adapter` — 207 PASS / 0 FAIL.
- All 7 Codex `agents/openai.yaml` files parse as valid YAML.
- All 15 `SKILL.md` files (8 CC + 7 Codex) have valid YAML frontmatter.

### Known carry-over (not in this release)

- **`codex exec` has no APD bootstrap path** — flagged in v5.0.6, still open. Candidate for v5.1, likely via `.mcp.json` self-registration.

## v5.0.6 — 2026-04-26

Live re-validation against Codex 0.125.0 + manifest fix for hard limit introduced in 0.124+.

- **Codex 0.125.0 sanity test passed.** TUI session opened from `~/Projects/Test`, first user prompt fired `SessionStart` hook on schedule (`gap-analysis: ran` after stale-cache detection). `codex_hooks` is now listed in the stable feature set on 0.125. Tracks original v5.0.4 evidence (0.124) plus this re-confirmation; openai/codex#15269 quirk (fires on first prompt, not banner) still applies.
- **`plugins/apd/.codex-plugin/plugin.json` — `defaultPrompt` schema fix.** Codex 0.124+ enforces a hard cap of 3 entries × 128 chars each on `interface.defaultPrompt`; longer entries are silently dropped (`codex-tui.log` shows `WARN ... ignoring interface.defaultPrompt[0]: prompt must be at most 128 characters`). The previous single 240+ char entry was being ignored entirely. Replaced with three short user-facing starter prompts: "Bootstrap APD: run apd_doctor and gap analysis." / "Brainstorm a new APD spec card." / "Audit APD setup with apd_doctor."
- **Doc consequence — exec-mode bootstrap is no longer claimed via `defaultPrompt`.** SPEC §4.2, §11.2, §14, §19.3 reworded. The earlier hypothesis that the orchestrator picked up a long `defaultPrompt` as a system-style instruction is no longer valid in 0.124+; `defaultPrompt` is now strictly user-facing UX. `codex exec` lacks an automatic APD bootstrap path until a real upstream entry point ships — flagged as a known limitation, candidate for v5.1 (likely via `.mcp.json` self-registration).

## v5.0.5 — 2026-04-26

Docs-only patch closing two issues surfaced by `framework-audit`:

- **`docs/SPEC.md` §4.1 heading** — corrected "13 entries across **7** event types" → "**8** event types". The table below already listed all eight (adding `PostCompact` between `PreCompact` and `PermissionDenied`); only the heading counter was stale. Restores alignment with the durable rule "update SPEC in same commit as any framework change".
- **`README.md` Skills table** — added the missing `/apd-miro` row. `skills/apd-miro/` ships, but the Skills table listed only 7 of 8 skills.

## v5.0.4 — 2026-04-26

Documentation-only patch capturing live Codex 0.124.0 validation findings from a full TUI session test against `~/Projects/Test`.

### What we learned live

- **Plugin install via GitHub marketplace works on 0.124.** `codex plugin marketplace add zstevovich/claude-apd` clones the repo into `~/.codex/.tmp/marketplaces/codex-apd`, then enabling the plugin (`[plugins."apd@codex-apd"] enabled = true`) makes skills appear in the slash menu immediately.
- **MCP auto-registration works end-to-end.** After plugin enable, a fresh TUI session on a clean project leads to `.codex/config.toml` being populated with `[mcp_servers.apd]` + 8 per-tool approval blocks, and `.codex/hooks.json` with both `PreToolUse Bash → guard-bash-scope` and `SessionStart → cdx session-start`. Working hypothesis (not yet proven): the orchestrator invokes `apd cdx init` on its own because `defaultPrompt` tells it to call `apd_doctor`, which flags the gap. Unknown whether Codex itself also has a post-install hook path.
- **`apd_ping` via MCP returns a valid response on every session.** Confirmed output: `{"ok": true, "version": "5.0.2", "plugin_root": "/Users/.../apd-template", "project_dir": "/Users/.../Test", "runtime": "codex"}`.
- **`SessionStart` hook fires in TUI — but on first user prompt, not at banner display.** Tracked upstream as openai/codex#15269 ("SessionStart not firing on session start instead it fires on first user prompt submission"). Practical effect: gap-analysis runs on the first turn of every fresh TUI session, not at open. If the user cancels before sending the first message, the hook does not fire for that session.
- **`codex_hooks` feature is now `stable` on 0.124** (was "under development" on 0.121).
- **Plugin marketplace upstream is no longer blocked on 0.124.** The 0.121 issue (openai/codex#18258) appears resolved — `plugins` feature flag is stable, GitHub and local marketplaces both register cleanly.

### Documentation updates

- `docs/SPEC.md` §4.2 — version bumped from 0.121 to 0.124; added SessionStart first-prompt quirk + reference to openai/codex#15269.
- `docs/SPEC.md` §11.2 — reworded for 0.124 semantics; added live-validation paragraph with exact session and hook timestamps from the 2026-04-26 test.
- `docs/SPEC.md` §14 — updated SessionStart known-limitation entry; added new entry for the `.mcp.json` plugin-manifest gap (ongoing backlog for v5.1).

### Outstanding research (not blocking)

- **`.mcp.json` in plugin manifest.** Other Codex plugins (cloudflare, build-ios-apps) declare MCP servers via `.mcp.json` at plugin root. APD's `plugins/apd/` does not, so our MCP server is registered via post-install `apd cdx init` rather than natively by the plugin. Worth investigating whether we can ship an `.mcp.json` that tolerates a Python stdio server without hardcoded paths — deferred to v5.1 unless blocking.
- **Which actor wrote `.codex/config.toml` during the first fresh session** — the leading guess is the orchestrator itself, triggered by `defaultPrompt → apd_doctor` spotting the gap. Not a correctness issue but worth confirming so we know whether we can rely on it or need a harder post-install hook.

## v5.0.3 — 2026-04-26

Fixes a project-resolution bug surfaced by the first real Codex 0.124 TUI SessionStart test on a pure-Codex project.

### Context

- **New reality on Codex 0.124.0:** `SessionStart` hook **does** fire in TUI mode (per live test on `~/Projects/Test`, 2026-04-26 21:13:39). The earlier assumption that Codex only fired `SessionStart` in TUI on 0.121 and `codex exec` was blocked is now obsolete — in 0.124, hooks declared in `.codex/hooks.json` are honoured.
- Plugin-based MCP + hooks distribution (registered via `codex plugin marketplace add`) also works end-to-end: `apd_ping` returns a valid response with `version: 5.0.2`, `runtime: codex`, and the right `project_dir` after marketplace install + plugin enable.

### Bug

`bin/lib/resolve-project.sh` only recognised `.claude/` and `CLAUDE.md` as project markers. On a pure-Codex project (only `.codex/` and `AGENTS.md`), the upward walk climbed past the project and matched `~/.claude/` (the user-global CC config), resolving `PROJECT_DIR=$HOME` and tripping `APD_ACTIVE=false`. The session-start script then exited early, skipping the apd-init gap analysis.

Log evidence from the failing run:

```
21:13:39 START pwd=/Users/zoranstevovic/Projects/Test
21:13:39 resolve: PROJECT_DIR=/Users/zoranstevovic APD_ACTIVE=false
21:13:39 EXIT: APD_ACTIVE=false
```

### Fix

- `bin/lib/resolve-project.sh` now treats `.codex/` and `AGENTS.md` as first-class project markers alongside `.claude/` and `CLAUDE.md`, via a new `_apd_has_marker` helper used in all three resolution paths (git toplevel, pwd, upward walk).
- The upward-walk path now explicitly stops at `$HOME` and refuses to resolve `PROJECT_DIR=$HOME`. This prevents `~/.codex/` (global Codex config) and `~/.claude/` (global CC config) from being mistaken for a project root when a hook fires from a path with no markers above it.
- Verified on a clean `~/Projects/Test` (only `.codex/` present): `resolve: PROJECT_DIR=/Users/zoranstevovic/Projects/Test APD_ACTIVE=true gap-analysis: ran`.

### Tests

- `bash bin/core/test-codex-adapter` → **207/0 PASS** (no regressions).
- `verify-apd` on `examples/nodejs-react` → **60/20/2** (baseline held).

## v5.0.2 — 2026-04-26

Two fixes that together close the CRITICAL "SessionStart on Codex" gap, plus a convenience CLI for plugin updates.

### Codex SessionStart equivalent (A + B combined)

The CC `SessionStart` hook was fixed in CC 2.1.101 (re-confirmed on 2.1.119). Codex 0.121.0 fires `SessionStart` in TUI only, never in `codex exec`. Before this release, cdx had no runtime equivalent to CC's `bin/core/session-start` — no dynamic gap-analysis, no shortcut drift guard, no auto apd-init.

- **`bin/adapter/cdx/session-start`** (new) — drains stdin, restores `.codex/bin/apd` shortcut if deleted, runs `apd-init --quick` gap analysis with the same 1h throttle pattern as CC. Silent log at `<APD_PLUGIN_ROOT>/cdx-session-start.log`.
- **`bin/adapter/cdx/install-codex-config`** — new block 6 merges `SessionStart` into `.codex/hooks.json` idempotently, preserving any existing PreToolUse/PostToolUse entries.
- **`plugins/apd/.codex-plugin/plugin.json`** — `defaultPrompt` extended to instruct the orchestrator to call `apd_doctor` at session open. This is the exec-mode path (hook does not fire there). Caveat: activation of the new `defaultPrompt` depends on upstream `/plugin install` marketplace path, which is blocked in Codex 0.121.0 (openai/codex#18258). Fully active once upstream issue resolves.
- **`bin/adapter/cdx/codex-doctor`** — new check reports whether `.codex/hooks.json` wires SessionStart.
- **`bin/core/test-codex-adapter`** — +6 tests covering first-run write, hooks.json content, script executable bit, manifest mention of `apd_doctor`, and merge preservation in the repair scenario. Baseline moved 201 → 207.

### `apd update` convenience CLI

- **`bin/core/apd-update`** (new) — one command that pulls the framework with `git pull --ff-only` and re-runs project init (`install-codex-config` for `.codex/`, `apd-init --quick` for `.claude/`). Idempotent. Flags: `--check-only` (dry-run, exits before pull), `--skip-pull` (reinit only, no git fetch). Aborts cleanly on dirty working tree or non-FF divergence.
- **`bin/apd`** — dispatches `update` / `up` to the new script, help block updated.

### Documentation

- **`docs/SPEC.md`** — §1 (Distribution: `apd update` row), §2 (CLI surface: `update` subcommand), §4.2 (Codex hooks: now 2 hooks, SessionStart table), §11.2 (Codex session-start dual path — TUI hook + exec `defaultPrompt`), §12 (hooks.json content), §14 (SessionStart known-limitations updated).

## v5.0.1 — 2026-04-24

Two small post-merge fixes.

- **`rules/workflow.md`** — align opener of `## 0. Lean vs Full mode` with Codex `AGENTS.md` (*"Not every task needs every gate. Pick the mode at spec time:"*). Previously the CC wording (*"Every pipeline cycle runs in one of two modes"*) read neutrally and the orchestrator defaulted to Full even for Lean-eligible tasks; the Codex phrasing encourages picking the lighter mode when it fits.
- **`bin/core/pipeline-doctor`** — include `guard-compact` and `guard-send-message` in the Guard Coverage section. Both guards exist in `bin/core/` and are wired in `hooks/hooks.json`, but doctor listed only 8/10. Now reports 10/10.

Verified on `examples/nodejs-react`: `verify-apd` baseline unchanged at 60/20/2.

## v5.0.0 — 2026-04-24

**Multi-runtime era.** APD becomes first-class on both Claude Code and OpenAI Codex. The major bump reflects the conceptual shift, not breaking changes — existing CC users see only additive changes (new files under `mcp/`, `plugins/apd/`, `bin/adapter/cdx/`, `bin/compiled/`). Codex side ships an MCP server (8 tools), per-tool approval registration, hook adapter, install flow, 4 Codex-native skills, AGENTS.md template, and direct-drop plus marketplace distribution paths.

The release also bundles four runtime-polish fixes (F1-F4), a documentation reorganisation (Part B for Codex install + authoritative runtime SPEC), and the corrections from two real-world Codex Lean tests (commits `bc6a93a` and `7374bd7`) on the PHP test project.

### Codex adapter (consolidated since v4.7.x)

- **MCP server** (`mcp/apd_mcp_server.py`) — FastMCP wrapper exposing 8 tools: `apd_ping`, `apd_doctor`, `apd_pipeline_state`, `apd_list_agents`, `apd_advance_pipeline`, `apd_guard_write`, `apd_verify_step`, `apd_adversarial_pass`. Defense in depth on `apd_guard_write` (regex `[A-Za-z0-9_.-]+` whitelist + filesystem escape detection). Empty-pass guard on `apd_adversarial_pass` (notes ≥80 chars when total=0). Per-tool approval blocks written into project `.codex/config.toml` (Codex 0.121.0 has no server-wide default).
- **Codex plugin manifest** (`plugins/apd/.codex-plugin/plugin.json`) — APD interface, capabilities, `defaultPrompt` injecting "Follow the APD pipeline …" at session start.
- **Codex marketplace** (`.agents/plugins/marketplace.json`) — `INSTALLED_BY_DEFAULT` registration so APD is first-class in every Codex project (when upstream `/plugin install` works; current 0.121.0 has openai/codex#18258 blocking it — direct-drop is the supported path).
- **Codex skills** (`plugins/apd/skills/{apd-brainstorm, apd-tdd, apd-debug, apd-finish}/`) — markdown body + `agents/openai.yaml` per skill.
- **Codex install adapter** (`bin/adapter/cdx/install-codex-config`) — 8-step idempotent flow: MCP server registration → per-agent sandbox skip (intentional, Codex 0.121.0 doesn't enforce) → `.codex/bin/apd` shortcut → `.apd/config` seed → AGENTS.md write-only-if-missing → `.apd/rules/*` → pure-Codex `.apd/` scaffold (skipped on hybrid) → hooks.json merge.
- **Codex skills install** (`bin/adapter/cdx/skills-install`) — direct-drop (default, symlinks `~/.codex/skills/apd-*` → repo) and `--marketplace` modes (latter experimental, blocked upstream).
- **Codex hook adapter shim** (`bin/adapter/cdx/guard-bash-scope`) — parses Codex hook stdin JSON and forwards to core `guard-bash-scope`. Single PreToolUse Bash event wired (Codex 0.121.0 supports only this reliably in `codex exec` mode).
- **Codex doctor** (`bin/adapter/cdx/codex-doctor`) — 6-section audit (prerequisites, global config, project `.codex/`, .apd content, AGENTS.md, MCP server syntax + 8 tool functions present).
- **AGENTS.md template** (`templates/codex/AGENTS.md`) — Codex orchestrator master guide; mirrors CLAUDE.md role for the Codex runtime.
- **5 Codex agent templates** (`templates/codex/agents/`) — backend-builder, frontend-builder, testing, code-reviewer, adversarial-reviewer.
- **4 Codex rules** (`templates/codex/rules/{brainstorm, debug, finish, tdd}.md`) — phase-specific orchestrator guidance.

### F1 — Inline "Next:" runtime guidance

`bin/core/pipeline-advance` builder/reviewer/verifier cases now print a runtime-neutral "Next:" line at the end of each gate. Reviewer case has 3 branches (Lean opt-out / Full pending / fallback). Spec case retained its existing CC-flavored Next-steps block as separate concern. **Why:** orchestrator was reading lifecycle from AGENTS.md/workflow.md only — runtime reinforcement closes the loop.

### F2 — Reset lifecycle documentation

- `templates/codex/AGENTS.md` — added step 10 (`apd_advance_pipeline("reset")`) to the Order of operations. Previously orchestrator never knew to call reset, causing telemetry loss + stale spec-card.
- `rules/workflow.md` — corrected two false "auto-resets" claims (lines 43, 86); pipeline does NOT auto-reset, must be called manually. Documented the correct command and what it archives.

### F3 — guard-audit.log sanitisation

Heredoc commit messages were producing 51 garbage lines in real Test logs, surfacing as 51 WARNs per `apd report` call.

- **Writers** (`bin/lib/style.sh::log_block` + `bin/core/guard-git::log_block`): collapse newlines/CR in `cmd_summary` so each blocked event is exactly one log line.
- **Parsers** (`bin/core/pipeline-report` + `bin/core/pipeline-advance` reset case): silently skip orphan lines (legacy multi-line entries from pre-fix writers) instead of WARN-spamming. Pattern matches `^YYYY-MM-DD HH:MM:SS|`.

Net: zero WARN output post-fix; legacy garbage is invisible to users; future writes are one-line.

### F4 — Caller-provided "New rule" with "None" default

`pipeline-advance` reset case: caller passes optional learning string as 2nd arg (`apd_advance_pipeline("reset", "always run composer dump-autoload after model changes")`); session-log entry uses it directly. Empty/missing → "None" (no manual session-log edit needed). Newlines sanitised so each event stays one log line.

Removes user-facing placeholder `[fill in or "None"]` that previously required manual session-log edit. AGENTS.md step 10 + workflow.md document the optional 2nd arg.

### Documentation

- **`docs/SPEC.md`** — authoritative runtime map. 23 sections (Part I surface map + Part II internals). Documents every guard, MCP tool, hook event, constant (budget thresholds, timeouts, regex patterns), install step, manifest field. Auto-loaded into framework-internal CLAUDE.md context. **Convention:** code without a SPEC entry is undocumented; update SPEC in the same commit as any framework change.
- **`GETTING-STARTED.md` Part B polish** — Step 1 (marketplace) flagged as Codex 0.121.0 upstream-blocked (openai/codex#18258); Part B (direct-drop) noted as recommended Codex install today.

### Tests

- `bash bin/core/test-codex-adapter` → **201/0 PASS** maintained throughout the F1-F4 series; bash syntax checks (`bash -n`) clean on every modified script.
- Two real-world Codex Lean test cycles: comment-validator-minimum-lengths (1m 32s) and category-validator-no-leading-digit (1m 39s). Test 2 was the definitive Lean decision-logic validation (clean prompt, orchestrator independently picked Lean with original-wording rationale).
- `examples/nodejs-react` verify-apd baseline confirmed at **60/20/2** (the 20 FAILs are structural: install-time files not shipped in example + 8 guard tests needing real hook context).

### Known limitations (carried forward)

- Codex 0.121.0 marketplace install upstream-blocked (openai/codex#18258). Direct-drop is the supported install path.
- Codex `/` slash menu doesn't list APD skills (same upstream).
- `pipeline-advance` spec case retains CC-specific Next-steps block (works for CC, ignored by Codex orchestrator).
- `SessionStart` hook flagged not firing on some projects (CRITICAL backlog).
- F4 caller-provided arg path live-validated only via documentation read in Test 2; arg-path live test pending (default "None" path is exercised on every reset).
- `bump-version` script does NOT update `plugins/apd/.codex-plugin/plugin.json` automatically — fixed manually for this release; backlog item to extend the script.

---

## v4.7.21 — 2026-04-23

Codex usage tuning — four soft levers that shave ~25-35% tokens on a typical mixed workload without touching pipeline gating. Additive changes only; existing callers of `apd_verify_step()` / `apd_pipeline_state()` keep working unchanged.

### Added
- **`templates/codex/AGENTS.md` — Recon section** before "Order of operations". Gives the Codex orchestrator three explicit rules before writing the spec card: (1) structural tools first (`apd_list_agents()` + `apd_pipeline_state()`) instead of opening files, (2) Grep/rg over full-file Read, (3) `≤ 7 file reads` green zone with "decompose the task instead" as the escape hatch beyond that. Pure guidance — no gate. Addresses the biggest concrete token burner observed on real Codex cycles (orchestrator reading 14+ files during recon when 5-7 would suffice).
- **Lean vs Full pipeline documentation** — formalises the previously-undocumented `adversarial: skip — <reason>` opt-out in `bin/core/pipeline-advance`. Lean skips adversarial for small, contained work (<5 files, no migration/auth/public-API/security/cross-module refactor); Full (default) runs every gate. Mechanical cap preserved: opt-out is only honored when the spec has ≤ 2 `R*:` criteria, otherwise the line is ignored. Added to `rules/workflow.md` (new `## 0. Lean vs Full mode` section), `templates/codex/AGENTS.md` (new section + step 7/8 reorder so adversarial correctly precedes the verifier gate — matches actual `pipeline-advance` enforcement), and `templates/codex/rules/brainstorm.md` (mode selection in the "Converge on a design" summary template).
- **`apd_pipeline_state()` `budgets` field** — advisory green/yellow/red status for `spec_criteria` (green ≤4, yellow 5-7), `reviewed_files` (green ≤4 → Lean-eligible, yellow 5-6, red 7+ → split the task), and `verifier_duration_s` (informational, nullable until verifier.done exists). No gate blocks on status — pure visibility to inform the Lean vs Full choice. New helper `_budget_status(value, green_max, yellow_max)`.
- **`apd_verify_step(scope="full"|"fast")` parameter** — fast mode passes `APD_VERIFY_SCOPE=fast` to verify-all.sh so a customised verifier can run build + touched-files tests only during builder REFACTOR iteration. Invalid scope rejected; empty string falls back to `full`. `pipeline-advance verifier` always runs with the default (env var unset → `full`) so the gate is unaffected. Safe-by-default: an uncustomised verify-all.sh just ignores the env var and runs its full logic. Framework reference at `bin/core/verify-all` and generated header in `apd-init` both `export APD_VERIFY_SCOPE="${APD_VERIFY_SCOPE:-full}"`; `.NET` example in `bin/core/verify-all` gains a commented fast-mode branch as the template pattern.

### Fixed
- **Framework-fallback path in `apd_verify_step` dropped `APD_VERIFY_SCOPE`.** When neither `.codex/bin/verify-all.sh` nor `.claude/bin/verify-all.sh` existed, the tool fell through to `_run_core("verify-all", ...)` which built a fresh env dict independently — `scope="fast"` silently degraded to `full` on the fallback. `_run_script`/`_run_core` now accept an optional `env_extra` kwarg overlaid on `_codex_env()`; `apd_verify_step` forwards `{"APD_VERIFY_SCOPE": scope}` explicitly on the fallback call. Caught by code review before landing.

### Tests
- `test-codex-adapter` grows four checks under new section **20c. apd_verify_step scope**: default resolves to `full` with env propagation, `scope="fast"` propagates `APD_VERIFY_SCOPE=fast`, invalid scope rejected with descriptive error, framework-fallback path forwards `APD_VERIFY_SCOPE` through `_run_core` (spy-based). Section 20 (`apd_pipeline_state`) gains a budgets-shape check. Test harness helper extraction now pulls `_budget_status` alongside the existing helpers. Total: **201/0 passing** (up from 196).

---

## v4.7.20 — 2026-04-18

### Added
- **`rules/workflow.md`** — new orchestrator rule explicitly permitting evidence-based verification of review findings against primary external sources (API docs, protocol specs, library contracts). Clarifies the adjacent "NEVER re-read code" rule: `WebFetch`-ing official documentation to check a specific claim in a review finding is NOT the same as replicating review work. Captures real-world pattern from BambiProject where the orchestrator dismissed a `Postmark ContentId` format finding by consulting Postmark docs — reviewer had hallucinated the format requirement, docs confirmed our code was correct. Documents the `accept-with-evidence | dismiss-with-evidence` requirement so future orchestrators don't drift back to feeling-based dismissals.

---

## v4.7.19 — 2026-04-18

### Added
- **`rules/workflow.md`** — new "MaxTurn sizing" subsection under *Model and effort discipline*. Captures the counterintuitive but real finding from two consecutive BambiProject runs: raising `maxTurns` makes pipelines *faster*, not slower, because it eliminates re-dispatch overhead (new agent re-reading spec/plan/sources from scratch) and prevents the context discontinuity bugs that reviewers catch and force fix cycles for. Documents APD defaults (40 builders / 30 reviewers), per-project override path (edit `.claude/agents/<name>.md`, auto-migration preserves non-legacy values), and an anti-pattern warning against lowering maxTurns "to save tokens".

---

## v4.7.18 — 2026-04-18

Deep audit bundle 5 — docs and nits. Closes out the audit cycle.

### Fixed
- **L2. `rotate-session-log` inconsistent echo/printf.** Line 72 used `printf '%s\n'`, line 74 used plain `echo` — the latter drops a trailing newline when the final line of kept content has none. Normalized to `printf '%s\n'` in both branches.

### Added
- **`docs/plans/README.md` + `docs/specs/README.md`** — archival markers explaining that dated planning/design documents reflect the state at time of writing and are not updated as the framework evolves. Points readers to authoritative current sources (CHANGELOG, templates, rules) and flags the specific drifts the audit found (`.claude/.pipeline/` → `.apd/pipeline/` in v4.3.4; `maxTurns` bumped in v4.7.13). Addresses L3 + L4 without editing every historical line — the docs remain as-written for context.

### Not applicable
- **L1** (`adapter/cc/guard-scope` missing scope paths) was a false positive. The adapter receives scope paths via `"$@"` from the per-agent hook template definition (`bash .../guard-scope {{SCOPE_PATHS}}`), which expands to `src/ tests/`-style positional args at template instantiation. Audit assumed hooks don't forward args — but this adapter is only called from template-generated agent frontmatter, not from `hooks/hooks.json`, so the args path works as designed.

---

## v4.7.17 — 2026-04-18

Deep audit bundle 4 — medium cleanup. Seven fixes across guards, init, reset, and test harness.

### Fixed
- **M1. `verify-contracts` file listing broke on spaces.** `for file in $file_list` word-split filenames that contain spaces, silently skipping them. Replaced with NUL-delimited `find -print0 | while read -r -d ''` and inline filtering for `node_modules`/`bin`/`obj`/`.d.ts`.
- **M2. `apd-init` stale-path migration left `.bak` leaks.** Four consecutive `sed -i.bak` calls on the same file each overwrote the previous `.bak`, and any intermediate failure left the file partially patched. Collapsed into one `sed -i.bak -e … -e … -e … -e …` invocation plus a post-loop `rm -f agents/*.bak` safety net.
- **M3. `pipeline-post-commit` regex was fragile to whitespace.** Now tolerant of leading whitespace and multiple spaces between the env var prefix and `git commit`, so CC payload formatters that collapse spaces no longer silently skip the post-commit reset.
- **M4. `verify-apd` session-log cleanup missed `APD-VERIFY-OPT-OUT`.** Only matched `APD-VERIFY-TEST`, so every run leaked one opt-out entry into the permanent log. Now matches any `APD-VERIFY-` prefix (TEST, OPT-OUT, and any future variants).
- **M6. `guard-bash-scope` whitelist was substring match, not prefix.** An allowed path of `src/` matched `other-project/src/foo` because `"src/"` appears as a substring. Now prefix-match after normalizing leading `./` and `~/`. **Behavior change for existing agents:** any agent whose allowed paths only passed via substring coincidence (e.g. allowed `lib/` matching `src/lib/foo`, or allowed `backend/src/` matching `api/backend/src/...`) will now correctly block. If an existing agent starts failing Bash writes after upgrade, the fix is to add the actual directory to the agent's scope paths.
- **M7. `session-start` → `apd-init --quick` timeout risk.** On projects with many agents and legacy frontmatter, the sed loops inside could approach the 5s hook budget on every new session. Cached: re-runs at most once per hour (stored in `.apd/pipeline/.last-init-check`).
- **M8. Half-done reset left no breadcrumb.** A killed `pipeline-advance reset` released the lock on EXIT but left the pipeline dir in a partial state with no indication. Now marks `.reset-in-progress` at reset start, removes it only on clean completion, and emits a `WARN: previous pipeline reset did not complete cleanly` on the next `pipeline-advance` call so the user can inspect.

### Not applicable
- **M5** (spec step deletes `implementation-plan.md` without atomic replace) was already fixed in a prior cleanup — spec-step `rm -f` no longer lists `implementation-plan.md`. Audit caught a false positive from an older source snapshot.

---

## v4.7.16 — 2026-04-18

Deep audit bundle 3 — security hardening across guards and timestamp parsing.

### Fixed
- **`guard-scope` path traversal.** `${FILE_PATH#"$PROJECT_DIR"/}` does not normalize paths, so `src/../../escape/foo` could slip past a prefix match on `src/`. Added canonicalization via `realpath` with a `cd + pwd -P` fallback, plus a defensive `..`-substring check that blocks any unresolved traversal even if normalization failed.
- **Adversarial-ordering check silent skip.** When the `.agents` timestamp couldn't be parsed by either `date -j -f` (BSD) or `date -d` (GNU), `ADV_EPOCH` became 0 and the whole ordering check was bypassed. Now fail-closed: unparseable timestamp → block with `adversarial-timestamp-unparseable` reason.
- **`guard-audit.log` silent skip.** Same pattern in `pipeline-advance` session-log enrichment and `pipeline-report` guard-blocks count — unparseable log timestamps were silently dropped from the count. Now emit a `WARN: … timestamp unparseable …` line before continuing, so the gap is visible.
- **`guard-git` mass-staging regex missed `--all=` long-form.** Expanded trailing character class to include `=`, so `git add --all=anything` and `git add -A=anything` also trip the block.
- **`validate_agent_entry` bash fallback was a single grep.** When the Go binary was missing (unsupported platform, corrupted install), enforcement silently degraded to `grep -q "|evt|name|"` — trivially satisfied by writing one forged line. Now fail-closed by default; users on unsupported platforms can opt in with `APD_ALLOW_UNVALIDATED_AGENTS=1`, which also prints a WARN every run.

### Note
H6 (`eval` with unsanitized `$ts` in `pipeline-report`) was already eliminated in v4.7.14 when the per-agent duration block was refactored — no longer applicable.

---

## v4.7.15 — 2026-04-18

Deep audit bundle 2 — lock handling and atomicity fixes.

### Fixed
- **Stale-lock reclaim race in `pipeline-advance`.** When two processes concurrently detected a stale lock (>5min), both could run `rmdir` + `mkdir` and both thought they owned the lock. The fallback `mkdir` return code is now checked, and a loser bails out with a clear "reclaimed by another session" message.
- **`verify-apd` backup directory collision.** Backup of live `.done` files went to a fixed `/tmp/apd-verify-backup/`, so concurrent runs or a stale leftover could silently restore wrong state into a live pipeline. Backup now uses `mktemp -d` (per-run unique path) and the cleanup restore clears it explicitly.
- **`pipeline-advance reset` agent-log atomicity.** The sequence was: parse `.agents` for metrics → write metrics → write session log → archive `.agents`. A crash between metrics write and archive lost the agent log permanently. Archive now happens immediately after parse, before any other write — the least-reconstructible record is safe first.

### Why it matters
All three issues were invisible under normal operation but guaranteed data loss on specific failure paths: concurrent dispatch (already observed in MEMORY), interrupted verify-apd runs, and Claude-Code timeouts mid-reset. None were reproducible in day-to-day use, hence the need for an audit to find them.

---

## v4.7.14 — 2026-04-18

Deep audit bundle 1 — three quick-win fixes surfaced by the v4.7.13 framework audit.

### Fixed
- **`pipeline-report` per-agent duration was dead code.** The Agents box compared the event field against `"START"`/`"STOP"` (uppercase) while `track-agent` writes lowercase `start`/`stop`, so durations never materialized. The `eval`-based bash parsing also treated the timestamp as an epoch integer when it is actually a human-readable string. Rewrote to lowercase match + `date -j`/`date -d` epoch conversion + tmp-file start/stop pairing (no `eval`).
- **`apd report --history` on Linux silently rendered an empty runs list.** The reverse-display used `tail -r || tac`, but `tail -r` is BSD-only and `tac` is GNU-only — fine on macOS, fine on most Linux distros, but the chain could still fail silently on setups missing both. Replaced with portable `awk` reverse.
- **`gh-sync builder|reviewer|verifier` recursively re-ran the pipeline step.** It added a GitHub comment and then called `pipeline-advance "$STEP"`, but `pipeline-advance` already invokes `gh-sync` at the end of each step — any direct call to `gh-sync builder` double-advanced. Removed the self-referential pipeline-advance call; gh-sync is now strictly side-effects (issue comment).

### Migration
Zero-effort. The per-agent duration section will now populate in `apd report`; the history list renders correctly on all platforms; any existing automation that used `gh-sync builder` directly no longer double-advances the pipeline.

---

## v4.7.13 — 2026-04-18

Follow-up to v4.7.12 (maxTurn metric). The metric revealed that default `maxTurns` values baked into templates were the actual cause of silent agent exhaust — builders capped at 20, reviewers at 15, both too tight for realistic tasks.

### Changed
- **`templates/agent-template.md`** — builder `maxTurns: 20` → `40`
- **`templates/reviewer-template.md`** — `maxTurns: 15` → `30`
- **`templates/adversarial-reviewer-template.md`** — `maxTurns: 15` → `30`
- **`examples/nodejs-react/.claude/agents/*`** — bumped to match new defaults
- **`skills/apd-setup/SKILL.md`** + **`skills/apd-audit/SKILL.md`** — documented new values

### Auto-migration
`apd init` (or `/apd-setup` gap analysis) now detects legacy `maxTurns: 20` on builders and `maxTurns: 15` on reviewers, bumps them to the new defaults, and reports `bumped maxTurns 20 → 40`. User-set values (anything other than the exact legacy numbers) are left untouched.

### How to customize
If you want a different limit on any agent, edit `.claude/agents/<name>.md` directly — the auto-migration only rewrites the exact legacy values.

---

## v4.7.12 — 2026-04-18

Real-world signal surfaced from BambiProject run #24: agents that exhaust maxTurn never fire `SubagentStop`, so the pipeline looked healthy in `apd report` even when 2/4 agents silently hit the budget wall.

### Added
- **MaxTurn exhaust tracking** — `.agents` log is parsed at pipeline reset; counts of total dispatches and exhausted agents (`start` without matching `stop`) are appended as two new columns to `pipeline-metrics.log`.
- **`apd report`** — new `MaxTurn exhaust: N/M agents` line in the current-run Agents box (only when > 0) and in the last-completed Quality box.
- **`apd report --history`** — new `MaxTurn Exhaust` section with aggregate rate across runs (green <10%, yellow <25%, red above), plus `mx:N` marker on each run row.
- **`bin/lib/agents-parse.sh`** — `parse_agents_log FILE` helper for consistent counting across callers.

### Migration
Zero-effort. Existing `pipeline-metrics.log` rows without the new columns render as before (aggregate section hidden). New rows start accumulating from the first post-upgrade pipeline.

---

## v4.7.11 — 2026-04-17

Follow-up to v4.7.10 — auto-refresh existing reviewer agents + stop `apd verify` from polluting metrics.

### Fixed
- **`pipeline-metrics.log` pollution** — `apd verify` creates synthetic APD-VERIFY-TEST / APD-VERIFY-OPT-OUT pipelines to exercise pipeline-advance. Those were being logged as real runs, showing up in `apd report --history` as "…" partial entries. Now `pipeline-advance` skips metrics writes when task name matches `APD-VERIFY-*`.

### Changed
- **`apd-init` auto-refreshes reviewer agents** — detects missing `.reviewed-files` directive (added in v4.7.10) in `code-reviewer.md` / `adversarial-reviewer.md` and regenerates from the current plugin templates. Lets existing projects adopt the scope fix without re-running `/apd-setup`.
- **`apd-init` cleans existing pollution** — one-time pass that strips `APD-VERIFY-*` entries from `pipeline-metrics.log` if present.

### Migration
Run `bash .claude/bin/apd init --quick` on any existing project to:
1. Refresh reviewer templates with the `.reviewed-files` scope directive
2. Clean historical APD-VERIFY pollution from metrics log

---

## v4.7.10 — 2026-04-17

### Fixed
- **Reviewer scope drift** — second real-world incident on BambiProject: `adversarial-reviewer` was auditing files from a previous commit (ProcessFfaiWebhookCommand + WebhookSignatureMiddleware) instead of the current pipeline's changes — all 3 findings out-of-scope. Root cause: templates told the orchestrator "give the reviewer a list of changed files" without defining *how* to compute that list, letting orchestrator reasoning drift to `git diff HEAD~1 HEAD` after a fresh commit.

### Changed
- **`pipeline-advance reviewer`** now writes `.apd/pipeline/.reviewed-files` — the authoritative file scope for the current run. Computed as uncommitted tracked changes (`git diff --name-only HEAD`) plus untracked files (`git ls-files --others --exclude-standard`).
- **`templates/adversarial-reviewer-template.md`** — "What you receive" section rewritten: read ONLY files in `.reviewed-files`, dismiss findings outside that list, stop if empty/missing.
- **`templates/reviewer-template.md`** — new "Scope — files to review" section with the same directive.
- **`pipeline-advance reset` / post-commit cleanup / rollback** — all paths now also remove `.reviewed-files` for consistency.

### Migration notes
Existing projects keep using their generated `code-reviewer.md` / `adversarial-reviewer.md` until re-run of `/apd-setup` or `apd-init`. The `pipeline-advance` scope-write runs immediately for everyone — new runs produce `.reviewed-files`, agents that don't yet reference it will behave as before.

---

## v4.7.9 — 2026-04-16

### Fixed
- **verify-apd test harness** — "verifier passes with adversarial summary" test (lines 775–782) wrote `.adversarial-summary` without first injecting `|start|adversarial-reviewer|` into the agents log. `pipeline-advance` correctly hard-gates this (adversarial-summary-without-dispatch), so the test FAILed even on a healthy framework. The subsequent "adversarial ordering" test (lines 784–813) cascaded: rollback after the failed verifier removed `reviewer.done` instead of the never-created `verifier.done`, breaking setup.

Fix: inject fake `adversarial-reviewer` start/stop entries before writing `.adversarial-summary`, matching the pattern used at lines 796–797 for the ordering test. Reported by an external orchestrator analysis.

---

## v4.7.8 — 2026-04-16

Pipeline report now distinguishes critical guard saves from routine enforcement blocks.

### Changed
- **`apd report` — guard block breakdown** — the Quality section now lists each triggered guard reason with its count, marked `!` (critical save) or `·` (routine enforcement). Previously reports showed only a total count, which treated `destructive-git (2)` the same as `commit-no-prefix (1)`.

### Critical reasons (`!` yellow)
`destructive-git`, `force-push`, `--no-verify`, `secret-access`, `out-of-scope-write`, `out-of-scope-bash-write`, `lockfile-write`, `orchestrator-code-write`, `mass-staging` — these would have caused real damage if allowed through.

### Routine reasons (`·` dim)
`commit-no-prefix`, `push-no-prefix`, `adversarial-before-reviewer`, `pipeline-state-write`, `adversarial-summary-without-dispatch`, `pipeline-incomplete` — framework enforcing ordering/process, not damage prevention.

### Motivation
Real-world run (BambiProject "Verifikacija emaila #31") fired 3 guard blocks — two were `destructive-git` saves (builder tried `git stash drop`, orchestrator tried `git checkout -- . && git clean -fd` on 22 modified files), one was `orchestrator-code-write`. Previous report showed `Guard blocks: 3` with no indication that the framework had just prevented data loss.

---

## v4.7.7 — 2026-04-16

Builder effort bumped to `xhigh` for Opus 4.7 / future Sonnet 4.7 coding gains.

### Changed
- **Builder effort: `high` → `xhigh`** — new Opus 4.7 effort tier is Anthropic's recommended default for coding and agentic tasks. Applied to:
  - `templates/agent-template.md` — master builder frontmatter
  - `skills/apd-tdd/SKILL.md` — TDD skill runs at xhigh
  - `skills/apd-setup/SKILL.md` — setup generates new builders with xhigh
  - `rules/workflow.md` — model/effort discipline tables
  - `templates/CLAUDE.md.reference` — project template table
  - `README.md` — Five roles table

### Forward-compat note
Sonnet 4.6 does not support `xhigh` and will transparently degrade to `high` (Claude Code graceful fallback). Real effect kicks in when Sonnet 4.7 lands. No token cost change on Sonnet 4.6.

### Unchanged
- Orchestrator, Reviewer, Adversarial Reviewer — still `max` (all valid on their respective models).
- Builder model stays `sonnet` — we do not switch to Opus for implementation.

---

## v4.7.6 — 2026-04-15

### Added
- **Case study** — GLM-5 vs Claude Opus comparison on `apd.run` landing page. First completed pipeline run on a non-Anthropic model: 17m 13s, 52 guard blocks, 7/7 spec coverage, 99 files changed.

---

## v4.7.5 — 2026-04-14

### Fixed
- **session-start** — explicit `exit 0` at end prevents monitor from reporting false failure. `apd-init --quick` failure logged but does not propagate.
- **apd-init** — quick mode reports fix count before exiting

---

## v4.7.4 — 2026-04-14

### Fixed
- **monitors.json** — correct schema: `name` (required), `description`, `command`. Removed `timeout_ms` (not in plugin manifest schema, only in Monitor tool schema).

---

## v4.7.3 — 2026-04-14

### Fixed
- **monitors.json** — removed `name` and `persistent` keys not recognized by CC plugin system

---

## v4.7.2 — 2026-04-14

### Updated
- **Homepage** — plugin "Visit website" now links to `apd.run`

---

## v4.7.1 — 2026-04-14

### Added
- **PreCompact guard** — `guard-compact` blocks compaction while pipeline is in progress (CC 2.1.105+). Prevents context loss mid-pipeline. Allows compaction when pipeline is idle or complete.

### New enforcement
| What is blocked | Guard |
|----------------|-------|
| Compaction during active pipeline | `guard-compact` (PreCompact hook) |

---

## v4.7.0 — 2026-04-14

Plugin monitors — reliable session context loading.

### Added
- **Plugin monitors** — `monitors/monitors.json` with `apd-session-context` monitor that auto-arms on session start (CC 2.1.105+). Replaces unreliable SessionStart hook as primary context loader.
- SessionStart hook kept as fallback for CC < 2.1.105. Both are idempotent.

### Infrastructure
- Scanned CC 2.1.105–2.1.107 for APD-relevant changes

---

## v4.6.4 — 2026-04-14

### Added
- **Landing page** — `apd.run` homepage with hero, pipeline visualization, feature cards, stats, and install CTA
- **CNAME** — custom domain configuration for `apd.run`

---

## v4.6.3 — 2026-04-14

### Added
- **Interactive demo** — Report scene added to demo page with auto-padded box drawing
- **Pipeline Runs reports view** — Dashboard/Reports tab toggle with side-by-side terminal reports for Bambi and MojOff (last 10 runs each, all stats: trend, session, adversarial insights)

---

## v4.6.2 — 2026-04-14

### Fixed
- **History limit scopes all stats** — `--history N` now computes all statistics (avg, success rate, adversarial, session, trend) from the last N runs only, not the full log

---

## v4.6.1 — 2026-04-14

### Added
- **History limit** — `apd report --history 5` or `--history=5` shows last N runs
- **Desc sort** — history runs listed newest-first

---

## v4.6.0 — 2026-04-14

Pipeline report command — full recap dashboard for CLI.

### Added
- **`apd report`** — formatted pipeline recap with task info, step timing, spec coverage bar, adversarial findings, guard blocks, and agent durations. Called automatically by `apd-finish` before presenting push/PR options.
- **`apd report --history`** — all completed runs with success rate, trend analysis (last 3 vs prev 3), session stats (today/this week), adversarial insights (most hits, cleanest task).
- **Visual progress bars** — pipeline progress (`████████ 4/4`) and spec coverage (`██████████░░ 5/6`) with color-coded bars.
- **Iteration detection** — warns when builder→reviewer dominates total time, indicating possible rework cycles.
- **Changed files summary** — shows file count and top-level directories affected by the pipeline run.
- **Pipeline report screenshot** in README.

### Updated
- `apd-finish` SKILL.md — new Step 2 shows report before presenting options to user.

---

## v4.5.1 — 2026-04-13

### Added
- **`apd version`** — new command to display current version
- **Version in help** — `apd help` now shows version next to title

---

## v4.5.0 — 2026-04-13

CLI branding and stale hook cleanup.

### Added
- **CLI logo** — `apd_logo()` in `style.sh` renders pixel-art APD logo with terminal colors (violet A, blue P, green D, pipeline indicator). Displayed in `apd help` and `apd init`.
- **Stale SessionStart cleanup** — `apd-init` update mode detects and removes project-level SessionStart hooks from `settings.json` that override the plugin's `hooks.json` (common in pre-v4 projects).

---

## v4.4.0 — 2026-04-12

Runtime contract adapter layer — Phase 2 of ADR-001.

### Architecture
- **Adapter layer** — 9 guard scripts split into `bin/adapter/cc/` (CC-specific stdin JSON parsing) and `bin/core/` (platform-agnostic CLI args). Core guards are now testable without Claude Code or jq.
- **Explicit fail-open/fail-closed policy** — enforcement guards (git, scope, bash-scope, secrets, orchestrator, pipeline-state) fail-closed when jq is missing; advisory guards (lockfile, track-agent, pipeline-post-commit) fail-open with documented rationale.

### Updated
- `hooks.json` — all 8 hook entries point to `bin/adapter/cc/` shims
- Agent templates — all guard references updated to adapter paths
- `verify-apd` — functional tests use CLI args; adapter shim existence checks added; plugin detection validates both core and adapter layers
- `apd-init` — detects and auto-migrates stale `bin/core/guard-*` paths in existing agent files with visible STALE PATH warning

### Infrastructure
- `track-agent` debug logging moved from adapter to core via `--raw-payload` arg — adapter layer stays thin
- ADR-001 design spec and implementation plan added to `docs/`

---

## v4.3.4 — 2026-04-12

Pipeline relocation, quality enforcement, and SubagentStop workaround.

### Breaking change
- **Pipeline directory relocated** — `.claude/.pipeline/` → `.apd/pipeline/`. Claude Code treats `.claude/` as a protected path, causing permission prompts on every Write/Edit regardless of `permissions.allow` settings. Moving to `.apd/pipeline/` eliminates forced prompts.
- **Automatic migration** — `apd init` (update mode) detects old `.claude/.pipeline/`, moves contents to `.apd/pipeline/`, updates `.gitignore`, permission patterns in `settings.json`, and `workflow.md`.

### New enforcement
- **Adversarial dispatch verification** — verifier blocks if `.adversarial-summary` exists but no `adversarial-reviewer` start entry in `.agents` log. Prevents `ADVERSARIAL:0:0:0` bypass without actual dispatch.
- **Orchestrator code write instructions** — stronger workflow.md rules against orchestrator writing code directly or reading files after review to "verify". Reduced code-write guard blocks from 3/task to 0/task.

### Fixes
- **SubagentStop workaround** — CC SubagentStop hook has ~42% failure rate (GitHub #27755). Go binary now accepts agents with start but no stop if 30+ seconds elapsed. Eliminates false "No agent dispatched" blocks.
- **Rollback preserves implementation plan** — `pipeline-advance rollback` of builder step no longer deletes `implementation-plan.md`. Plan is frozen spec.
- **Workflow.md auto-update** — `apd init` update mode now replaces `workflow.md` when it contains stale `.claude/.pipeline` paths.
- **Timezone fix in Go binary** — elapsed time calculation uses local timezone for start timestamp parsing.
- **test-system agent_id format** — fake agent entries use valid CC agent_id format and realistic start/stop timing.

### Infrastructure
- **Agent dispatch debug logging** — `track-agent` logs full SubagentStart/Stop hook JSON to `agent-dispatch-debug.log` for dispatch analysis.
- **bump-version script** — local tool for consistent version updates across all files (plugin.json, marketplace.json, README, CLAUDE.md, memory).
- All guards, templates, rules, documentation, and tests updated for new `.apd/pipeline/` path.

---

## v4.2.0 — 2026-04-11

Enforcement hardening + quality gates.

### New enforcement
- **Adversarial ordering** — verifier blocks if adversarial-reviewer ran before reviewer step completed. Pipeline flow: builder → reviewer → fix → adversarial.
- **Adversarial opt-out limit** — skip only allowed for tasks with <=2 criteria. 3+ criteria = must dispatch adversarial-reviewer.
- **mkdir deny** — `permissions.deny` blocks orchestrator from creating `.pipeline/` directory manually. Must use `apd pipeline spec`.
- **SendMessage guard** — blocks SendMessage during active pipeline (SubagentStart/Stop hooks don't fire for continued agents).

### Fixes
- **Guard read false positive** — `cat spec-card.md 2>/dev/null` no longer blocked (redirect operators excluded from pipeline write check)
- **AGENTS_LOG missing in verifier** — adversarial ordering check was silently skipped because variable was undefined
- **sed criteria terminator** — `^\*\*[^A]` → `^\*\*[A-Z]` (correctly stops at `**Affected modules:`)
- **guard-bash-scope** — `*pipeline*` → `*.pipeline/*` (avoids matching APD tool names)
- **track-agent** — removed `log_block` from SubagentStart warning (not a real block, inflated counter)
- **Glob permissions** — added `**/.pipeline/` wildcard variants for absolute path matching
- **Implementation plan preserved** — `pipeline-advance spec` no longer deletes plan on re-run

### Infrastructure
- **Plugin update flow** — version bump required for `/plugin update` to pull changes (same version = cached)
- **Verify-apd** — adversarial ordering E2E test added (98 checks total)

---

## v4.1.1 — 2026-04-10

Fixes and hardening after real-world testing on Bambi and Test projects.

- **Complete audit trail** — all 8 guards now log to guard-audit.log via shared `log_block()`. Previously only guard-git logged blocks.
- **Forgery detection logged** — verify_done tamper attempts now written to guard-audit.log
- **Plugin cache guard** — fixed false positive blocking script execution (2>&1 matched as write)
- **verify-apd E2E tests** — fixed signed .done parsing, lock cleanup, adversarial agent ordering, trace markers, session-log fill-in cleanup
- **test-hooks** — checks plugin hooks.json instead of project settings.json (removed 3 false WARNs)
- **session-start** — shortcut creation moved before apd-init (prevents hook timeout), debug log includes date
- **apd-setup** — runs session-start as workaround for SessionStart hook not firing
- **guard-bash-scope** — removed over-broad "apd " whitelist bypass
- **.adversarial-summary** — multi-line safe parsing (head -1)
- **Dead feature removed** — pipeline-skip-log.md references cleaned up
- **Pipeline run #8** — documented (Test blog, 3 guard blocks, 8 adversarial findings)

---

## v4.1.0 — 2026-04-10

Tamper-proof pipeline enforcement with compiled Go binary.

### Highlights
- **Compiled Go validator** — `bin/compiled/validate-agent-*` creates HMAC-signed `.done` files. Orchestrator cannot forge pipeline steps — signature verified at every step transition and commit gate.
- **Adversarial reviewer hard gate** — verifier blocks if adversarial-reviewer agent exists but was not dispatched. Opt-out via `adversarial: skip` in spec-card.md.
- **SendMessage guard** — blocks SendMessage during active pipeline (SubagentStart/Stop hooks don't fire for continued agents).

### Enforcement
- Agent dispatch validation via compiled binary (timestamp, hex agent_id, start/stop pairs, duration)
- guard-bash-scope: blocks mkdir, touch, rm on .pipeline/ and all writes to plugin cache
- Criteria counter: counts R* only within Acceptance criteria section
- Git toplevel resolution: `resolve-project.sh` uses `git rev-parse --show-toplevel`
- Pipeline permissions: `apd-init` auto-configures settings.json allowlist
- Stale path detection: `apd-init` and `pipeline-doctor` detect legacy directories and old path references
- workflow.md: all paths updated to `bash .claude/bin/apd pipeline`

### Pipeline runs
- Run #6: First clean run — adversarial gate blocked verifier, forced dispatch
- Run #7: 7 bypass attempts, all blocked (direct edit, fake dispatch, SendMessage, max criteria)

---

## v4.0.0 — 2026-04-10

Scripts restructured — single entry point, clean architecture.

- **`scripts/apd`** — single entry point for all APD commands: `apd pipeline|doctor|verify|trace|init|gh|test`. One shortcut, one interface.
- **`scripts/core/`** — all 22 scripts moved here without `.sh` extensions. Executables have no extension, libraries (lib/) keep `.sh`.
- **Planned agents check** — implementation-plan.md `### Agents` section lists needed agents. pipeline-advance.sh builder warns if planned agents were not dispatched.
- **guard-bash-scope.sh in plugin hooks** — orchestrator's Bash writes to .pipeline/ now blocked (was only in agent templates before).
- **Auto GitHub sync** — gh-sync reuses existing issues instead of creating duplicates, circular call removed.
- **POSIX file lock** — replaced Linux-only flock with mkdir-based lock, auto-removes on exit, stale detection >5min.
- **Pipeline doctor shortcut** — session-start creates `.claude/scripts/apd` (replaces separate apd-pipeline/apd-doctor shortcuts).
- **track-agent.sh warnings** — red WARNING when builder dispatched without pipeline-advance.sh builder.

### Breaking changes
- All hook paths changed: `scripts/<name>.sh` → `scripts/core/<name>`
- Existing projects must run `/apd-setup` to update agent hook paths
- Old shortcuts (apd-pipeline, apd-doctor) auto-removed, replaced by single `apd`

### Enforcement hardening (v4.0.0)
- **Compiled Go validator** — `bin/compiled/validate-agent-*` creates HMAC-signed `.done` files. Orchestrator cannot forge pipeline steps — signatures verified at every step transition and commit gate.
- **Adversarial reviewer hard gate** — `pipeline-advance verifier` blocks if adversarial-reviewer agent exists but was not dispatched. Opt-out via `adversarial: skip` in spec-card.md.
- **Agent dispatch validation** — compiled binary checks timestamp format, hex agent_id, start/stop pairs, minimum duration.
- **SendMessage guard** — `guard-send-message` blocks SendMessage during active pipeline (SubagentStart/Stop hooks don't fire for SendMessage).
- **guard-bash-scope hardened** — blocks mkdir, touch, rm on .pipeline/ and all writes to plugin cache directory.
- **Criteria counter fix** — counts R* only within Acceptance criteria section (sed instead of grep).
- **Git toplevel resolution** — `resolve-project.sh` uses `git rev-parse --show-toplevel` as primary method for correct subdirectory/worktree support.
- **Pipeline permissions** — `apd-init` auto-configures settings.json allowlist for pipeline files and apd commands.
- **Stale path detection** — `apd-init` and `pipeline-doctor` detect and remove legacy `scripts.old/` directories and stale `pipeline-advance` references.
- **workflow.md** — all paths updated from `${CLAUDE_PLUGIN_ROOT}/bin/core/pipeline-advance` to `bash .claude/bin/apd pipeline`.

---

## v3.7.0 — 2026-04-10

Pipeline hardening — mechanical enforcement, anti-bypass, concurrent session protection.

- **Max 7 acceptance criteria** — `pipeline-advance.sh spec` hard-blocks specs with >7 R* criteria, forcing feature decomposition into smaller pipeline cycles.
- **Pre-flight checklist** — after spec step, displays next steps with exact Agent tool dispatch format and superpowers warning.
- **Spec freeze** — sha256 hash saved on spec step, verifier blocks if spec-card.md modified mid-pipeline. Must rollback to change scope.
- **Auto GitHub sync** — `pipeline-advance.sh` calls `gh-sync.sh` at every step (best-effort, non-blocking). Board moves automatically: Spec → In Progress → Review → Testing → Done.
- **Pipeline state guard** — `guard-pipeline-state.sh` blocks Write/Edit to .done, .agents, .spec-hash, .trace-summary. Only pipeline-advance.sh can create state files.
- **Bash write protection** — `guard-bash-scope.sh` always protects `.pipeline/` directory, even without ALLOWED_PATHS. Blocks echo/tee/sed/cp/mv to pipeline state via Bash.
- **File lock** — `flock` prevents concurrent pipeline operations. Second session gets BLOCKED.
- **Reviewer block message** — specific fix instructions with exact Agent tool syntax, "do not rollback" warning.
- **No-rollback rule** — workflow.md: if pipeline step fails, fix and retry instead of rolling back code.
- **Explicit agent dispatch format** — workflow.md documents `Agent({ subagent_type: "code-reviewer" })`, warns against superpowers agents.

---

## v3.6.0 — 2026-04-10

Implementation plan step and enforcement gaps — orchestrator must write plan before dispatching builder, spec-card.md is now mandatory.

- **Implementation plan step** — orchestrator writes `.pipeline/implementation-plan.md` (files to change + 1-2 sentences per file) before dispatching builder. Builder reads the plan instead of searching the codebase. `pipeline-advance.sh builder` hard-blocks without it.
- **Hard block: spec-card.md** — `pipeline-advance.sh spec` now requires spec-card.md to exist with R* acceptance criteria. Previously allowed advance without it, making spec traceability a no-op.
- **Soft warn: adversarial-summary** — `pipeline-advance.sh verifier` warns if adversarial-reviewer agent is configured but `.adversarial-summary` was not written. Does not block.
- **workflow.md** — step 4 clarified with plan file requirement, new section 3c (implementation plan format).
- **Builder template** — reads implementation-plan.md and spec-card.md in workflow step 1.
- **Cleanup** — `implementation-plan.md` added to spec, reset, and builder rollback cleanup.

---

## v3.5.2 — 2026-04-09

- **`apd-init.sh`** — gap analysis now creates `adversarial-reviewer.md` from template when missing. Previously `/apd-setup` reported 100 PASS but didn't detect the missing agent.

---

## v3.5.1 — 2026-04-09

Audit fixes and polish.

- **Critical fix: spec-card.md lifecycle** — was deleted during spec step (before builder/verifier could read it), now correctly deleted on pipeline reset
- **Dynamic version** — `apd-init.sh` reads version from `plugin.json` instead of hardcoding; no more version drift
- **Version sync** — marketplace.json, CLAUDE.md, README.md, apd-setup SKILL.md all aligned
- **README.md** — "Four roles" → "Five roles", added Adversarial Reviewer section and Mermaid diagram update
- **CLAUDE.md** — fixed stale `/apd-init` → `/apd-setup`, updated skills directory listing
- **Templates** — CLAUDE.md.reference and workflow.md section 8 model tables include Adversarial Reviewer
- **Metrics display fix** — "Last 5" and duration loop properly consume adversarial columns, preventing partial task misidentification
- **Adversarial parsing** — triple cat|cut replaced with single IFS read

---

## v3.5.0 — 2026-04-09

Adversarial reviewer — context-free code review that catches what contextual reviewers miss.

- **Adversarial reviewer template** — new agent (sonnet/max, `memory: none`, read-only). Reviews code changes with zero task context. Finds bugs, security issues, and edge cases that the regular reviewer misses because it "knows what the builder was trying to do."
- **Pipeline step 6b** — optional step between reviewer and verifier. Orchestrator dispatches adversarial reviewer, evaluates findings (accept/dismiss), fixes legitimate issues before verifier.
- **Hit rate metrics** — orchestrator writes `ADVERSARIAL:total:accepted:dismissed` to `.pipeline/.adversarial-summary`. Session-log shows per-task hit rate, pipeline metrics show cumulative hit rate across all tasks. Tracks whether the feature adds value or generates noise.
- **Five roles** — workflow.md updated from four to five roles (Orchestrator, Builder, Reviewer, Adversarial Reviewer, Verifier) with model/effort table.
- **Metrics fix** — `grep '|completed$'` pattern updated to handle trailing adversarial columns in pipeline-metrics.log.

---

## v3.4.0 — 2026-04-09

Spec traceability — mechanical verification that every acceptance criterion has test coverage.

- **`verify-trace.sh`** — new verification script. Parses `.pipeline/spec-card.md` for R1-RN acceptance criteria, scans test files for `@trace R*` markers, blocks commit if any criterion lacks test coverage. Stack-aware test file detection (nodejs, python, php, dotnet, go, java). Colored output via style.sh.
- **Spec persistence** — orchestrator writes spec card to `.pipeline/spec-card.md` before advancing pipeline. Ephemeral lifecycle: born on spec step, verified before commit, deleted on reset.
- **Pipeline integration** — `pipeline-advance.sh` validates spec-card.md has R* criteria on spec step, runs verify-trace.sh as verifier gate, caches trace summary for session-log, cleans up on rollback.
- **Session-log enhancement** — auto-generated session-log entries now include `**Spec coverage:**` field (e.g., "3/3 (all covered)").
- **Builder template** — updated workflow: read spec-card.md, add `@trace R*` markers in test files.
- **Reviewer template** — new check: verify `@trace R*` markers cover all acceptance criteria, flag missing as Critical.
- **workflow.md** — R* format for acceptance criteria, spec persistence rule, new section 3b (spec traceability).

---

## v3.3.2 — 2026-04-08

Framework polish and naming consistency.

- **`/apd-audit` skill** — qualitative framework audit (version consistency, stale refs, hook correctness, script quality, docs accuracy)
- **Skill prefix convention** — all skills renamed to `apd-*` prefix (`github-projects` → `apd-github`, `miro-dashboard` → `apd-miro`) to avoid name conflicts with project skills
- **`apd-init.sh --version`** — reads version dynamically from plugin.json
- **verify-apd.sh** — skip guard-scope check for read-only agents (0 WARN for properly configured projects)
- **MCP recommendations** — `/apd-setup` recommends MCP servers based on stack (context7, postgres, github, docker, miro)
- **Correct MCP packages** — `@modelcontextprotocol/server-postgres` and `server-github` (not `@anthropic-ai`)

---

## v3.2.7 — 2026-04-08

Visual identity, skill quality, pipeline fixes. See [GitHub Release](https://github.com/zstevovich/claude-apd/releases/tag/v3.2.7).

---

## v3.2.6 — 2026-04-08

Skill quality overhaul and `/apd-init` → `/apd-setup` rename.

- **Skill refactor** — all 7 skills rewritten with CSO descriptions ("Use when..." trigger-only), Iron Laws, rationalization tables, Red Flags, DOT process diagrams, integration sections
- **`/apd-init` → `/apd-setup`** — renamed to reflect both init and maintenance role
- **`/apd-upgrade` removed** — replaced by `apd-init.sh --quick` auto-update on session start
- **Mandatory skill enforcement** — workflow.md step 9 added, brainstorm/tdd/debug/finish are mandatory at specified pipeline points
- **`allowed-tools`** — apd-tdd and apd-debug get tool access without permission prompts
- **`disable-model-invocation`** — apd-setup is user-only (not auto-triggered)

---

## v3.2.5 — 2026-04-08

Mandatory skill enforcement in workflow and version bump.

---

## v3.2.4 — 2026-04-08

Per-step pipeline colors, agent visual identity, hook and template fixes.

- Per-step colors: spec=violet, builder=blue, reviewer=orange, verifier=green, commit=violet
- Agent `color` field in templates (purple/blue/orange/green)
- ☭ agent dispatch icon in track-agent.sh
- `if` field moved to hook object level in agent/reviewer templates (was at matcher-group)
- ANSI color tuning: lighter violet (177), sharper orange (208)
- TERM-based color detection for Claude Code Bash context
- Auto-allow memory file writes in generated settings.json

---

## v3.2.3 — 2026-04-08

Post-commit hook fix and color detection.

- Fixed `if` patterns in hooks.json — env var prefixes not matched by Claude Code pattern matching. Simplified to `Bash(git *)` and `Bash(git commit*)`
- Added TERM color detection (covers Claude Code Bash tool where no TTY exists)

---

## v3.2.2 — 2026-04-08

Fix verify-apd.sh spec assertion to match new branded header format.

---

## v3.2.1 — 2026-04-08

Unified CLI visual identity. Shared style library replaces inline color definitions and box drawing across all scripts.

### New

- **`scripts/lib/style.sh`** — shared style library with TTY-aware colors, branded markers (■ □ ◆ ✓ ✗ !), and output helpers (apd_header, apd_blocked, pass, fail, warn, ok, fix, skip, err, section, show_pipeline, format_duration)
- **Branded headers** — all script output uses `APD ■ Title` prefix instead of box drawing
- **Minimal sections** — `── Name ──` dim separators replace double-line boxes (╔══╗)
- **Consistent markers** — ✓/✗/! replace [PASS]/[FAIL]/[WARN] in test-hooks.sh

### Changed

- `pipeline-advance.sh` — all box headers/footers removed, uses style.sh (-82 lines)
- `pipeline-gate.sh` — box blocked output → `APD □ BLOCKED:` format
- `session-start.sh` — 5 boxes (version warnings, self-heal, header) → branded headers
- `apd-init.sh` — inline colors/helpers → source style.sh
- `verify-apd.sh` — box header/summary → sections with dim separators
- `verify-contracts.sh` — RED/GREEN/YELLOW → style.sh aliases, boxes → sections
- `test-hooks.sh` — [PASS]/[FAIL]/[WARN] → ✓/✗/!, === → branded header

---

## v3.2.0 — 2026-04-08

Comprehensive audit and fix release. 21 issues fixed across scripts, skills, hooks, templates and documentation.

### Critical fixes

- **hooks.json `if` field placement** — moved from matcher group level to individual hook objects. Conditional hooks (guard-git, guard-lockfile, pipeline-post-commit) now filter correctly instead of firing on every tool call
- **Non-existent `apd-pipeline` command** — `rules/workflow.md` and `templates/CLAUDE.md.reference` referenced `bash .claude/scripts/apd-pipeline` which never existed. Fixed to `bash ${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-advance.sh`
- **verify-apd.sh test assertions** — 4 E2E pipeline tests checked for strings that `pipeline-advance.sh` never emits ("Pipeline started", "Builder completed", etc). Fixed to match actual output ("APD Pipeline", "Builder Complete", etc)
- **Portable sed** — replaced macOS-only `sed -i ''` with `sed -i.bak` + cleanup (5 occurrences in `apd-init.sh`). Replaced `\n` in sed replacement strings with `awk` for cross-platform JSON manipulation
- **Version consistency** — hardcoded versions `3.0.0` and `3.1.2` updated to `3.2.0` across `apd-init.sh`, `apd-init/SKILL.md`, `apd-upgrade/SKILL.md`, `CLAUDE.md`, `README.md`, `MEMORY.md`
- **principles template** — ".claude/ directory must not go to git" was wrong. Fixed to accurate gitignore policy (only `.pipeline/` and `settings.local.json` are excluded)
- **apd-upgrade skill** — `rm -f .claude/rules/workflow.md` replaced with `cp` from plugin, since rules are not auto-loaded from plugins

### Important fixes

- **verify-apd.sh agent cleanup** — dummy agent files created during E2E test now use proper `printf` (not `echo` with `\n`) and are cleaned up via `restore_pipeline_state`
- **pipeline-advance.sh init guard** — changed from counting all repo commits to counting only `.claude/`-related commits. Existing repos with 3+ commits can now init APD without `APD_FORCE_INIT=1`
- **pipeline-advance.sh usage header** — removed non-existent `skip` command, added `init "Description"`
- **apd-brainstorm skill** — bare `pipeline-advance.sh` call fixed to full `bash ${CLAUDE_PLUGIN_ROOT}/scripts/` path
- **apd-finish skill** — relative `.claude/scripts/verify-all.sh` path fixed to use `git rev-parse --show-toplevel`
- **GETTING-STARTED.md** — duplicate "Step 3" heading fixed (now Steps 3, 4, 5)

---

## v3.1.0–v3.1.9 — 2026-04-08

Mechanical enforcement release. Agents must actually run before pipeline advances, orchestrator cannot write code, superpowers plugin blocked.

### Mechanical enforcement (v3.1.0)

- **Agent dispatch verification** — `pipeline-advance.sh builder/reviewer` checks `.agents` log for actual agent dispatch. No more self-reporting
- **guard-orchestrator.sh** — blocks orchestrator from writing code files directly. Forces agent dispatch
- **Standardized reviewer agent** — `reviewer-template.md` with opus/max enforcement
- **Model and effort discipline** — workflow.md enforces sonnet/high for builders, opus/max for reviewers
- **userConfig support** — `plugin.json` userConfig fields for `project_name`, `stack`, `author_name`

### Superpowers blocking (v3.1.1–v3.1.2)

- **APD dormant mode** — hooks exit early in non-initialized projects (no `.apd-config`)
- **Superpowers disabled** — `/apd-setup` writes `"superpowers@claude-plugins-official": false` to project `settings.json`
- **apd-init.sh** — mechanical init/update script with gap analysis for existing projects

### Pipeline automation (v3.1.3–v3.1.6)

- **Shell injection for /apd-setup** — skill auto-executes bash script via `!command` pattern
- **Stronger wording** — MANDATORY run script first, no agent self-analysis
- **session-start.sh runs apd-init.sh --quick** — automatic gap check on every session start
- **Pipeline shortcut** — `session-start.sh` creates `.claude/scripts/apd-pipeline` symlink

### Tracking and cleanup (v3.1.7–v3.1.9)

- **Agent history log** — `track-agent.sh` records agent dispatches to `.agents` and archives to `agent-history.log`
- **Session log agents field** — session-log entries include dispatched agent names
- **workflow.md refresh** — `apd-init.sh` update mode detects and replaces stale `CLAUDE_PLUGIN_ROOT` references in project `workflow.md`

### Visual identity (v3.1.0)

- Stellar violet squares for pipeline indicators (■ □ ◆)
- Enterprise-grade terminal output with consistent color scheme
- 4 APD skills replacing superpowers equivalents: `apd-brainstorm`, `apd-tdd`, `apd-debug`, `apd-finish`

---

## v3.0.0 — 2026-04-08

**Major release: APD evolves from a copy-paste template into a full Claude Code plugin ecosystem.**

APD v1.0 started as a folder you copied into your project. v2.0 grew into a framework with 20 patterns across 4 layers. v3.0 completes the transformation: APD is now a proper Claude Code plugin — install it once, use it everywhere.

### The journey: template → framework → ecosystem

| Version | Era | How it worked |
|---------|-----|---------------|
| v1.0 | Template | Copy `.claude/` into project, replace placeholders manually |
| v2.0–2.8 | Framework | 17 scripts, 4 skills, 20 patterns, but still copy-paste |
| **v3.0** | **Ecosystem** | **Install once via marketplace, `/apd-setup` generates everything** |

### Breaking changes

- APD no longer works by copying `.claude/` into projects
- Install via marketplace: `/plugin marketplace add zstevovich/claude-apd` + `/plugin install claude-apd@zstevovich-plugins`
- Start new session, then run `/apd-setup`
- Scripts live in the plugin (`${CLAUDE_PLUGIN_ROOT}/scripts/`), not in the project
- Only `verify-all.sh` remains in the project (stack-specific build commands)
- Agent hooks use `${CLAUDE_PLUGIN_ROOT}` instead of hardcoded paths

### New architecture

```
Plugin (installed once):           Project (generated per-project):
  scripts/ (17 scripts)              .claude/agents/*.md
  hooks/hooks.json                   .claude/rules/workflow.md
  rules/workflow.md                  .claude/rules/principles.md
  skills/ (4 skills)                 .claude/scripts/verify-all.sh
  templates/agent-template.md        .claude/memory/
  templates/verify-all/              .claude/.apd-config
  templates/principles/              .claude/.apd-version
  templates/memory/                  .claude/settings.json
  .claude-plugin/plugin.json         CLAUDE.md
  .claude-plugin/marketplace.json
```

### New features

- **Plugin distribution** — marketplace.json for self-hosted distribution via `/plugin install`
- **`resolve-project.sh`** — shared library sourced by all scripts. Resolves `PROJECT_DIR` (user's project) and `APD_PLUGIN_ROOT` (plugin install) automatically. Enables scripts to work from any directory
- **`/apd-upgrade` skill** — migrates v2.x copy-paste installations to v3.x plugin architecture (backup, extract config, remove old scripts, update agent hooks)
- **`pipeline-advance.sh init`** — dedicated command for initial project setup. Distinct from `skip` (hotfix): no HOTFIX label, no skip log entry, auto-fills "None" in session log
- **Visual pipeline progress** — ASCII progress bar shows pipeline state at every step:
  ```
  [spec]---[builder]---[reviewer]--- verifier  --> commit
  ```
- **Improved auto-summary** — session-log entries now capture committed files (via `git diff HEAD~1`) instead of working tree. Guard block count filtered by task timestamp (excludes E2E test blocks)
- **Complete settings.json** — `/apd-setup` generates attribution (empty, no AI signatures) and Notification hook
- **`.apd-config`** — project configuration file (`PROJECT_NAME`, `APD_VERSION`, `STACK`) read by session-start.sh for dynamic project name
- **`.apd-version`** — tracks installed APD version for upgrade detection
- **Per-stack verify-all templates** — `templates/verify-all/` with ready-made snippets for .NET, Node.js, Java, Python, Go, PHP
- **Per-language principles templates** — `templates/principles/` for English and Serbian
- **Plugin hooks** — `hooks/hooks.json` with `${CLAUDE_PLUGIN_ROOT}` paths, conditional `if` fields, PostCompact, PermissionDenied

### Full English internationalization

All 400+ Serbian strings translated to English across 46 files:
- 17 bash scripts (comments, echo messages, error output)
- 4 skills (descriptions, procedures, examples)
- Rules, templates, agents, examples, documentation
- README.sr.md removed — single English README

### Deep audit — 52 issues fixed

Pre-release audit identified and fixed 52 issues:
- 11 critical (broken YAML quotes, missing files, wrong paths)
- 13 high (unquoted patterns, non-atomic writes, missing script lists)
- 14 medium (POSIX compatibility, trap cleanup, template gaps)
- 14 low (documentation, comments, minor inconsistencies)

Critical fixes include:
- Agent TEMPLATE.md had missing opening quotes in all `command:` values — hooks would not work
- `[popuni]` grep pattern not updated to `[fill in]` — session-log gate was non-functional
- 6 verify-all templates had untranslated Serbian error messages
- Script paths in skills/rules referenced `.claude/scripts/` instead of `${CLAUDE_PLUGIN_ROOT}/scripts/`

### Plugin system alignment

Verified against real Claude Code v2.1.94 plugin system:
- `hooks/hooks.json` auto-discovered (NOT declared in plugin.json — causes duplicate error)
- `skills/` auto-discovered (NOT declared in plugin.json)
- Agent template moved from `agents/` to `templates/` (avoid auto-discovery as invocable agent)
- Rules NOT auto-loaded from plugins — `/apd-setup` copies `workflow.md` to project
- Marketplace file enables self-hosted distribution

### Real-world validation

Tested end-to-end on a PHP + PostgreSQL + Vanilla JS project:
- `/apd-setup` generated 80 PASS, 0 FAIL setup
- Guard system blocked 16 violations (mass-staging, force-push, pipeline-incomplete, verify-failed)
- Pipeline gate correctly blocked commits without completed steps
- verify-all.sh ran PHPUnit and blocked on test failures
- Session log populated with auto-summaries

### Migration from v2.x

Run `/apd-upgrade` after installing the plugin. It will:
1. Backup your `.claude/` directory
2. Extract configuration from existing files
3. Remove scripts (now in plugin)
4. Update agent hook paths to `${CLAUDE_PLUGIN_ROOT}`
5. Create `.apd-config` and `.apd-version`
6. Verify with `verify-apd.sh`

### Installation

```bash
# In Claude Code:
/plugin marketplace add zstevovich/claude-apd
/plugin install claude-apd@zstevovich-plugins

# Start new session, then:
/apd-setup
```

---

## v2.8 — 2026-04-07

Adopts Claude Code v2.1.85–v2.1.89 platform features. Reduces hook overhead, adds context resilience and audit coverage.

### New features

- **Conditional `if` hooks** (v2.1.85+) — guard-git fires only on `Bash(git *)`, guard-lockfile only on lock file writes, pipeline-post-commit only on `APD_ORCHESTRATOR_COMMIT=1 git commit*`. Eliminates unnecessary process spawning for every `ls`, `cat`, or non-git Bash command
- **PostCompact hook** (v2.1.76+) — re-runs `session-start.sh` after context compaction to reinject project status, pipeline state, and last session. Prevents context loss in long sessions
- **PermissionDenied hook** (v2.1.89+) — `guard-permission-denied.sh` logs denied actions with tool name and agent ID (read from stdin JSON via jq) to `guard-audit.log`. Catches what guard scripts do not cover
- **`effort` frontmatter** (v2.1.80+) — `/apd-setup` runs at `effort: max`, `/miro-dashboard` and `/github-projects` at `effort: high`
- **Version check** — `session-start.sh` warns on startup if Claude Code is below v2.1.89 (recommended) or v2.1.32 (minimum functional). `verify-apd.sh` includes version as a PASS/WARN/FAIL check (54 checks total)

### Review fixes

- PermissionDenied hook changed from inline `echo` with shell env vars (always logged `unknown`/`orchestrator`) to proper script that reads `tool_name` and `agent_id` from stdin JSON
- `if` pattern on guard-git expanded to `Bash(git *) | Bash(APD_ORCHESTRATOR_COMMIT=1 git *)` to catch prefixed commands in both orchestrator and agent contexts
- `verify-apd.sh` now checks PostCompact and PermissionDenied hook registration

### Minimum Claude Code versions

| Level | Version | What works |
|-------|---------|-----------|
| Minimum functional | v2.1.32 | Pipeline, guards, agents |
| Recommended | v2.1.89+ | All features including conditional hooks, PostCompact, PermissionDenied, effort |

---

## v2.7 — 2026-04-06

Performance optimisation based on Trivue production analysis.

### New features

- **Verifier cache** — `pipeline-advance.sh verifier` writes a timestamp to `verified.timestamp`. When `verify-all.sh` runs again during the commit hook (<120s later), it detects the fresh cache and skips the rebuild. Eliminates the double build+test that was causing ~12 min overhead on .NET + Next.js projects
- Cache is invalidated on: pipeline reset, new spec, verifier rollback

### Impact

Trivue reported Reviewer→Verifier taking 12m 39s due to double verification (Verifier agent + guard-git commit hook both running `verify-all.sh`). With cache, the commit hook completes in <1s when Verifier has already passed.

---

## v2.6 — 2026-04-06

- **Getting Started guide** — step-by-step walkthrough from zero to first pipeline commit in 5 minutes. macOS terminal-style examples, verify output as readable table, spec card as blockquote, quick reference table
- **Interactive demo** — animated terminal demo showing guardrails blocking and pipeline flow (GitHub Pages)
- **Demo GIF** — embedded in README for instant visual preview
- **Architecture diagrams** — "20 Patterns in 4 Layers" grid + Pipeline Flow with GitHub Projects feedback loops
- **Gitignore cleanup** — `guard-audit.log` and `pipeline-metrics.log` added as runtime files
- **Review fixes** — session-log gate regex, stat fallback, PostToolUse verification, skip log silent drop

---

## v2.5.2 — 2026-04-06

- **New architecture diagrams** — "20 Patterns in 4 Layers" grid (Memory, Pipeline, Guards, Integrations) + Pipeline Flow with GitHub Projects feedback loops. Both EN and SR README
- **Gitignore cleanup** — added `guard-audit.log` and `pipeline-metrics.log` as runtime files

---

## v2.5.1 — 2026-04-06

Patch release: 2 HIGH and 4 MEDIUM fixes from code review.

### Bug fixes

- **HIGH: Session-log gate bypassed** — v2.4 gate checked for `[fill in]` but v2.5 auto-generated entries wrote `[fill in or "None"]` which didn't match. Gate was non-functional against auto-summaries. Fixed: pattern now matches `[fill in` (any variant)
- **HIGH: Spurious pipeline reset** — empty `stat` output in self-healing evaluated as `now - 0`, producing a massive age that triggered stale pipeline reset. Fixed: validates output before arithmetic
- **MEDIUM: PostToolUse hook not verified** — `verify-apd.sh` (51 checks now) and `test-hooks.sh` now check that `pipeline-post-commit.sh` is registered
- **MEDIUM: E2E test blocked by gate** — `verify-apd.sh` pipeline test now backs up and cleans session-log before `spec` step
- **MEDIUM: Skip log silent drop** — `pipeline-advance.sh skip` now always appends even if skip-log file doesn't exist

---

## v2.5 — 2026-04-06

Dream Consolidation: auto-generated session-log summaries from pipeline context.

### New features

- **Auto-summary on pipeline reset** — `pipeline-advance.sh reset` now generates populated session-log entries from pipeline context instead of `[fill in]` skeletons. Collects: changed files from `git diff`, guard blocks from `guard-audit.log`, bottleneck detection from step timestamps. Only **New rule** remains as `[fill in]` (requires human judgement)
- **Meta-summary on session-log rotation** — `rotate-session-log.sh` now generates a one-line consolidation when archiving entries: total tasks, date range, problem count, guard block count, new rules count
- **Fixed rotation regex** — `rotate-session-log.sh` now correctly matches `## [date]` format (was missing the brackets)

### Context

Production analysis (MojOff, 19 tasks) showed 12 of 14 auto-generated entries had unfilled `[fill in]` placeholders. v2.4 added a gate that blocks new tasks until entries are filled. v2.5 eliminates most placeholders by auto-generating content from data already available in the pipeline.

### Closes

- Closes #2 — auto-generate session-log summary from pipeline context

---

## v2.4 — 2026-04-06

Session-log enforcement based on real-world production findings.

### New features

- **Session-log gate** — `pipeline-advance.sh spec` now blocks new tasks if the previous session-log entry contains unfilled `[fill in]` placeholders. Shows which entry needs completion and lists the required fields. Forces the orchestrator to document what was done before starting new work

### Context

Production analysis of MojOff (19 pipeline tasks, 77 PASS verify-apd) revealed that 12 of 14 auto-generated session-log entries had unfilled `[fill in]` placeholders. The auto-append on pipeline reset creates skeleton entries, but without enforcement the orchestrator skips filling them in. This was the only soft rule in APD without mechanical enforcement — now it is enforced at the pipeline level.

### Edge cases verified

- Template session-log with HTML-commented examples: passes (no `[fill in]` in examples)
- Empty session-log: passes
- Missing session-log file: passes
- Properly filled entry: passes
- Entry with `[fill in]`: blocks with clear error message

---

## v2.3 — 2026-04-04

Security and reliability fixes based on independent framework audit.

### Bug fixes

- **CRITICAL: Pipeline reset timing** — moved pipeline reset from PreToolUse (before commit) to PostToolUse (after successful commit). Previously, if `git commit` failed after guard-git approved it (merge conflict, disk full, native pre-commit hook), the pipeline was already reset and the next commit would bypass pipeline checks. Now `pipeline-post-commit.sh` runs only after successful commit execution
- **guard-secrets coverage** — added guard-secrets.sh to `Read` and `Write|Edit` matchers in agent TEMPLATE.md. Previously, agents could `Read .env.production` or `Write` to sensitive files without being blocked (guard-secrets was only on the `Bash` matcher)

### New features

- **gh-sync.sh** — wrapper script that synchronises pipeline steps with GitHub Projects. Creates issues with spec cards, adds comments on each step, closes with commit reference or skip label. Remembers issue number across pipeline steps
- **pipeline-post-commit.sh** — PostToolUse hook that resets pipeline only after confirmed successful commit

### Updated files

- `.claude/scripts/guard-git.sh` — removed background pipeline reset (the timing bug)
- `.claude/scripts/pipeline-post-commit.sh` — new PostToolUse hook
- `.claude/scripts/gh-sync.sh` — new GitHub sync wrapper
- `.claude/settings.json` — added PostToolUse hook registration
- `.claude/agents/TEMPLATE.md` — guard-secrets on Read + Write|Edit matchers
- `.claude/skills/github-projects/SKILL.md` — gh-sync.sh documentation
- `examples/nodejs-react/` — both agents updated with new hook coverage

---

## v2.2 — 2026-04-04

Adds GitHub Projects integration for pipeline task tracking.

### New features

- **`/github-projects` skill** — maps APD pipeline phases to GitHub Projects v2 board columns (Spec → In Progress → Review → Testing → Done). Creates issues with spec cards, moves cards through columns, closes on commit
- **GitHub Projects section in CLAUDE.md** — configurable `{{GITHUB_PROJECT_URL}}` placeholder with pipeline tracking rules
- **`/apd-setup` updated** — asks for GitHub Projects URL during setup
- **README.md** — full GitHub Projects integration docs with column mapping, labels, metrics, and Miro vs GitHub comparison table

---

## v2.1 — 2026-04-04

Adopts Claude Code v2.1.72+ features for improved agent control and observability.

### New features

- **effort frontmatter** — `high` for Builders, `max` for Reviewer/Verifier. Enforces reasoning effort at the agent level instead of relying on documentation alone
- **agent_id audit logging** — `guard-git.sh` now logs every blocked action with agent ID, type, reason, and command to `guard-audit.log`. Enables per-agent activity analysis
- **Miro channels** — `claude --channels miro` enables real-time push notifications when the board changes. Supports board change alerts, CI/CD integration, and async human gate approval

### Updated files

- `.claude/agents/TEMPLATE.md` — added `effort: {{effort}}` frontmatter field
- `.claude/scripts/guard-git.sh` — agent metadata extraction + `log_block()` on all 10 exit points
- `.claude/skills/apd-setup/SKILL.md` — effort and channels guidance
- `CLAUDE.md` — Miro channels and dashboard references
- `README.md` — channels documentation in Miro integration section
- `examples/nodejs-react/` — both agents updated with `effort: high`

---

## v2.0 — 2026-04-04

Major release: from template to full-stack agentic development framework.

### New features

**Guardrails**
- Runtime write detection in `guard-bash-scope.sh` — blocks `node -e`, `python -c`, `ruby -e`, `php -r`, `perl -e` filesystem writes outside scope
- `verify-contracts.sh` — cross-layer type verification (TypeScript + C# parser) with nullable awareness, MATCH/MISMATCH/MISSING detection
- `verify-apd.sh` — 50 automated checks across 10 categories with summary table
- Self-healing session start — auto-fixes broken permissions, stale pipelines, shows merge conflict locations

**Pipeline**
- `pipeline-advance.sh metrics` — dashboard with avg/min/max duration, per-step averages, skip rate, last 5 tasks
- `pipeline-advance.sh rollback` — revert one step without full reset
- `pipeline-metrics.log` — append-only structured log for analytics
- Auto-append to session-log on pipeline reset

**Integrations**
- Figma integration — configurable design source with MCP and skill references
- Miro integration — board as source of truth for specs, architecture, planning
- `/miro-dashboard` skill — pushes pipeline status and metrics to Miro board
- Auto-detect agent scope in `/apd-setup` — reads project structure and proposes agents

**Documentation**
- English README (international English) + Serbian README.sr.md with cross-links
- Mermaid architecture diagrams (pipeline flow + guardrail infrastructure)
- CQRS architecture section with agents per stack, spec card templates, contract table
- Agent examples for 7 stacks: .NET, Node.js, Java/Spring Boot, Python/Django, Python/FastAPI, Go, PHP/Symfony
- Populated example project (`examples/nodejs-react/`)

**Quality**
- Canary upgraded to self-healing (auto chmod +x, auto pipeline reset, merge conflict detection)
- `test-hooks.sh` for quick static verification
- Pipeline skip log with `stats` command and >30% threshold warning

### Breaking changes

None. Fully backwards-compatible with v1.x configurations.

---

## v1.4 — 2026-04-04

- Hardened `guard-bash-scope.sh` — exit 2 (block) instead of exit 0 (warn)
- Added `test-hooks.sh` — 21 checks for hook configuration
- Added `pipeline-advance.sh rollback` command
- Added session-log example entries for onboarding
- Auto-append session-log on pipeline reset
- Removed obsolete files (setup.sh, conventions.md, superpowers specs/plans)

## v1.3 — 2026-03-25

- Interactive `/apd-setup` skill for project configuration
- ADR framework with templates
- Guard-lockfile for lock file protection
- Pipeline flag system (spec → builder → reviewer → verifier)
- Pipeline gate (blocks commit without all steps)
- Session log rotation
- MCP configuration example

## v1.2

- Guard-bash-scope and guard-secrets hooks
- Agent template with full hook coverage
- Pipeline advance with timestamps

## v1.0

- Initial APD template
- guard-git.sh, guard-scope.sh
- CLAUDE.md template with placeholders
- Workflow and principles rules
- Memory system (MEMORY.md, status.md, session-log.md)
