# Changelog

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
