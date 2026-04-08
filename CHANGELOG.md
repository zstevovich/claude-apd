# Changelog

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
