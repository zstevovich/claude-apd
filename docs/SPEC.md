# APD Framework — Specification

> Authoritative runtime map. Documents every executable mechanism, configuration surface, template, guard, gate, MCP tool, manifest field, and constant in the framework.
> **Audience:** framework maintainer, advanced operator debugging behavior, anyone consuming APD as a library.
> **Status:** living document. Code without a SPEC entry is undocumented — update this in the same commit as any framework change.

---

## 0. Conventions

- **CC** = Claude Code runtime (`.claude/`-based)
- **Codex** = OpenAI Codex CLI runtime (`.codex/` + `.apd/`-based)
- **Both** = same code path serves both runtimes
- **Hybrid project** = has both `.claude/` and `.codex/` (CC paths authoritative; Codex falls back to `.apd/` only if `.claude/` absent)
- **Pure-Codex project** = `.codex/` only

---

# Part I — Surface map

## 1. Distribution

| Layer | CC | Codex |
|---|---|---|
| Plugin manifest | `.claude-plugin/plugin.json` (v4.7.21) | `plugins/apd/.codex-plugin/plugin.json` (v4.7.20 — one behind, manual sync needed) |
| Marketplace registration | `.claude-plugin/marketplace.json` (`zstevovich-plugins` namespace) | `.agents/plugins/marketplace.json` (`codex-apd` namespace, `INSTALLED_BY_DEFAULT` policy) |
| Install command | `/plugin marketplace add zstevovich/claude-apd` → `/plugin install` | `codex plugin marketplace add zstevovich/claude-apd` (Codex 0.124+; on 0.121 was upstream-blocked, openai/codex#18258 since fixed) |
| Direct-drop | n/a | `apd cdx skills install --legacy-symlink` symlinks `~/.codex/skills/apd-*` → `plugins/apd/skills/<name>`. Deprecated since v5.0.8; default is now marketplace registration. |
| Live source resolution | from CC plugin runtime cache | direct lokalni path (Test project's MCP server points at `apd-template/mcp/` directly; marketplace cache stale by design for dev workflow) |
| In-place update (dev workflow) | n/a (use CC `/plugin update`) | `apd update [project]` — `git pull --ff-only` on framework + reinit project's `.codex/` hooks/config. Idempotent. Dry-run via `--check-only`. |

GitHub repo: `zstevovich/claude-apd`. Branch flow: `feature/codex-adapter` (pre-merge), `main` (released).

## 2. CLI surface — `bin/apd`

Top-level dispatcher routes by 1st arg. Resolves project root via `bin/lib/resolve-project.sh`.

| Subcommand | Target | Purpose |
|---|---|---|
| `init` / `setup` | `bin/core/apd-init` | Initialize APD inside a project |
| `update` / `up` | `bin/core/apd-update` | `git pull --ff-only` on framework repo + re-run `install-codex-config` / `apd-init --quick` on target project. Aborts on dirty tree or non-FF. Flags: `--check-only`, `--skip-pull`. |
| `pipeline` / `pl` | `bin/core/pipeline-advance` | Pipeline gate operations (steps + reset/rollback/status/stats/metrics) |
| `doctor` / `dr` | `bin/core/pipeline-doctor` | 11-section audit of pipeline + project |
| `report` / `rp` | `bin/core/pipeline-report` | Render formatted summary |
| `gh` / `github` | `bin/core/gh-sync` | GitHub Issues sync (best-effort, never blocks) |
| `test` | `bin/core/test-hooks` | Static hook check |
| `test-system` | `bin/core/test-system` | E2E synthetic pipeline smoke |
| `cdx` / `codex` | `bin/adapter/cdx/<sub>` | Codex adapter sub-router |

`apd cdx` sub-commands: `init|setup`, `agents [list|add]`, `verify-setup [list|<stack>]`, `skills [status|install|uninstall]`, `doctor|dr`, `test`.

Per-project shortcuts: `.claude/bin/apd` (CC) and `.codex/bin/apd` (Codex) — both exec the plugin entry. Codex shortcut auto-created by MCP server bootstrap on first call.

## 3. MCP server (Codex-only) — `plugins/apd/mcp/apd_mcp_server.py`

FastMCP wrapper, runs via `uv run --with mcp python …`. **v6.0 self-registers via plugin-shipped `plugins/apd/.mcp.json`** with `cwd: "."` (resolves to plugin root in the Codex plugin cache, where `mcp/apd_mcp_server.py` now lives because all framework binaries moved into `plugins/apd/` in v6.0). 8 tools (full param details + security in §18).

`<project>/.codex/config.toml` carries a complete `[mcp_servers.apd]` override written by `install-codex-config`: `command = "uv"`, `args = ["run", "--with", "mcp", "python", "mcp/apd_mcp_server.py"]`, `cwd = "<plugin-root>"`, plus all 8 `[mcp_servers.apd.tools.<name>] approval_mode = "approve"` blocks. This is deliberate even though plugin `.mcp.json` also contains approval metadata: live Codex 0.125 testing showed plugin-shipped `approval_mode` does not suppress the TUI MCP approval prompt, while project `config.toml` approvals do. Per-tool blocks must not be written without the parent transport block, because TOML then creates an implicit `mcp_servers.apd` table and Codex fails with `invalid transport in mcp_servers.apd`.

**Failed v5.0.9–10 self-registration:** Codex's plugin cache previously only included `plugins/apd/`, not repo-root `mcp/`, `bin/`, or `VERSION`. With `cwd: "../.."` set, Codex spawned `uv run python mcp/apd_mcp_server.py` from the plugin cache root and got `[Errno 2] No such file or directory`. v6.0 resolves this by moving every dependency *inside* `plugins/apd/`, so plugin cache contents are sufficient for the MCP server to start. Reverted in v5.0.11; resolved in v6.0.

| Tool | Purpose |
|---|---|
| `apd_ping` | Liveness — returns version + paths |
| `apd_doctor` | Wraps `codex-doctor` for in-conversation diagnostics |
| `apd_pipeline_state` | Structured snapshot of all gate state + advisory budgets + next_step hint |
| `apd_list_agents` | Inventory of agent registry with parsed frontmatter |
| `apd_advance_pipeline` | Wraps `pipeline-advance`. Steps whitelist: spec, builder, reviewer, verifier, init, status, stats, metrics, reset, rollback. Reset's optional 2nd arg → session-log "New rule" |
| `apd_guard_write` | Pre-write authorization with regex-validated `apd_role` + filesystem escape defense |
| `apd_verify_step` | Runs project's `verify-all.sh` with optional `scope="fast"` env-var injection |
| `apd_adversarial_pass` | Records `.adversarial-summary` with mandatory ≥80-char notes when total=0 |

## 4. Hooks

### 4.1 CC hooks — `hooks/hooks.json` (13 entries across 8 event types)

**v6.0 path note:** the hook config file itself stays on the repo root (`hooks/hooks.json`) because Claude Code auto-discovers it from `${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json`. All hook commands now reference `${CLAUDE_PLUGIN_ROOT}/plugins/apd/bin/...` since `bin/` moved into the plugin folder.

| Event | Matcher | Handler | Block? |
|---|---|---|---|
| `SessionStart` | `startup` | `session-start` | No (load + heal) |
| `PreToolUse` | `Bash(git *)` | `guard-git` | Yes (exit 2) |
| `PreToolUse` | `Bash` | `guard-bash-scope` | Yes |
| `PreToolUse` | `SendMessage` | `guard-send-message` | Yes (during pipeline) |
| `PreToolUse` | `Write\|Edit` | `guard-orchestrator` | Yes |
| `PreToolUse` | `Write\|Edit` | `guard-pipeline-state` | Yes |
| `PreToolUse` | `Write\|Edit(*lockfile patterns)` | `guard-lockfile` | Yes |
| `PostToolUse` | `Bash(git commit*)` | `pipeline-post-commit` | No (only triggers reset) |
| `SubagentStart` | (none) | `track-agent --event start` | No |
| `SubagentStop` | (none) | `track-agent --event stop` | No |
| `PreCompact` | (none) | `guard-compact` | Yes (during active pipeline) |
| `PostCompact` | (none) | `session-start` | No (re-inject context) |
| `PermissionDenied` | (none) | `guard-permission-denied` | No (telemetry) |

### 4.2 Codex hooks — generated per-project at `<project>/.codex/hooks.json`

Written by `bin/adapter/cdx/install-codex-config`. Codex 0.124.0 fires `PreToolUse Bash` reliably in both exec and TUI modes; `SessionStart` fires in TUI only. Two hooks wired:

| Event | Shim | Timeout | Purpose |
|---|---|---|---|
| `PreToolUse` (matcher `Bash`) | `plugins/apd/bin/adapter/cdx/guard-bash-scope` | 5s | Scope enforcement on Bash tool calls |
| `SessionStart` | `plugins/apd/bin/adapter/cdx/session-start` | 10s | Shortcut drift guard + `apd-init --quick` gap analysis (throttled 1h). TUI only — `codex exec` has no equivalent bootstrap path (see §14). |

Requires global `codex features enable codex_hooks` (stable as of 0.124; was "under development" on 0.121).

**Codex 0.124 SessionStart quirk — fires on first user prompt, not at banner display.** A live TUI session does not fire `SessionStart` when the TUI first renders; the hook executes only when the user submits the first message. This is upstream behaviour, tracked in openai/codex#15269 ("SessionStart not firing on session start instead it fires on first user prompt submission"). Practical implication: gap-analysis runs on first turn, not at open. If the first turn is cancelled before a prompt is sent, the hook does not fire for that session.

### 4.3 Guards — `bin/core/guard-*` (10 scripts)

See §17.2 for per-guard internals. Block convention: exit 2 = BLOCK, exit 0 = ALLOW. All blocks logged to `<memory>/guard-audit.log` via shared `log_block` helper in `bin/lib/style.sh` (sanitises newlines/CR per F3 since v4.7.21+).

**Why guards, not CC permission prompts.** APD's enforcement boundary is `exit 2` from a guard plus the compiled `validate-agent` Go binary (§16.4) — never a CC permission prompt. Permission rules are bypassable: `--dangerously-skip-permissions` skips writes to `.claude/skills/`, `.claude/agents/`, `.claude/commands/` (CC 2.1.121+) and the entire `.claude/`, `.git/`, `.vscode/`, and shell config files (CC 2.1.126+). Guards run inside CC's hook engine and cannot be skipped without disabling hooks at the harness level. Compiled validators raise the bar further: the exit code is the contract, regardless of what the orchestrator claims to the harness.

## 5. Pipeline lifecycle

### 5.1 Phase order (7 phases)

1. **spec** — `apd_advance_pipeline("spec", task)` validates ≤7 R-criteria, freezes spec-card.md via SHA256, archives prior `.agents` log
2. **builder** — orchestrator writes `implementation-plan.md`, dispatches builder agent (CC) or implements inline (Codex). Advance blocks if planned agents not dispatched
3. **reviewer** — diff review. Sets `.adversarial-pending` (Full) OR honors `adversarial: skip — <reason>` line in spec-card if ≤2 R-criteria (Lean opt-out)
4. **adversarial pass** (Full only) — records via `apd_adversarial_pass(...)` (Codex) or direct Write to `.adversarial-summary` (CC)
5. **verifier** — runs `verify-all.sh`; blocks on failure; in Full mode also blocks on missing `.adversarial-summary`
6. **commit** — gated by `APD_ORCHESTRATOR_COMMIT=1` env + `pipeline-gate` check that all 4 `*.done` markers present
7. **reset** — caller-invoked. Archives metrics + agent-history, writes session-log auto-summary, clears artifacts. Optional 2nd arg → "New rule" entry (default "None"). NOT auto-triggered.

### 5.2 Lean vs Full

- **Full** (default): all 5 gates + adversarial pass
- **Lean**: spec → builder → reviewer → verifier → commit (no adversarial). Activated by `adversarial: skip — <reason>` line. **Mechanical cap: ≤2 R-criteria.**

### 5.3 Pipeline state files (`.apd/pipeline/`)

| File | Set by | Purpose |
|---|---|---|
| `spec-card.md` | spec phase | Frozen task spec |
| `.spec-hash` | spec phase | SHA256 of spec body for tamper detection |
| `.spec-max-defects-history` | spec phase | `<task>\|<value>` snapshot of last accepted `max_defects` for the task; pipeline-advance blocks re-spec that RAISES the value for the same task (v6.3 D). Reset wipes — explicit pivot escape valve |
| `implementation-plan.md` | orchestrator pre-builder | Files + agents to dispatch |
| `*.done` (4 files) | each `pipeline-advance` step | Gate completion markers; line 1 = `<epoch>\|<human-time>[\|<task>]`, line 2 = HMAC signature (validate-agent) |
| `.reviewed-files` | reviewer phase | Reviewer-scoped file list |
| `.adversarial-pending` | reviewer phase | Full mode flag + green light for adversarial dispatch (v6.1 B1 pre-flight gate) |
| `spec-card.md` `adversarial:` line | spec phase | Optional. `skip — <reason>` (opt-out, ≤2 R) or `max_defects=N\|unlimited` (v6.1 B2 severity gate). Default = unlimited |
| `.adversarial-summary` | adversarial phase | `ADVERSARIAL:T:A:D` + Notes block |
| `.trace-summary` | verifier phase | `TRACE:<covered>/<total>:<uncovered_ids>` |
| `verified.timestamp` | verifier phase | 120s TTL cache |
| `.agents` | track-agent (CC SubagentStart/Stop), Codex orchestrator | Pipe-delimited dispatch log |
| `.last-init-check` | session-start | 3600s TTL, survives reset |
| `.gh-issue` | gh-sync | Persists GitHub issue number across phases |

### 5.4 Telemetry (written by reset flow)

| File | Format | Notes |
|---|---|---|
| `pipeline-metrics.log` | Pipe-delimited per-task: `ts\|task\|spec_ts\|builder_ts\|reviewer_ts\|verifier_ts\|status\|adv_t\|adv_a\|adv_d\|agents_t\|agents_x` | Skips `APD-VERIFY-*` synthetic test runs |
| `agent-history.log` | Concatenated `.agents` files | Skips `APD-VERIFY-*` |
| `session-log.md` | Markdown auto-summary entry per task | Uses `NEW_RULE` arg or "None" default |
| `guard-audit.log` | Pipe-delimited: `ts\|TYPE\|agent_info\|reason\|cmd_summary` | Sanitised newlines since F3 |

Memory dir: `<project>/.claude/memory/` (CC + hybrid) or `<project>/.apd/memory/` (pure-Codex). Resolved by `bin/lib/resolve-project.sh`.

## 6. Agent system

### 6.1 Templates (in repo)

| File | Role |
|---|---|
| `templates/agent-template.md` | Master schema (frontmatter + body conventions) |
| `templates/adversarial-reviewer-template.md` | Context-free reviewer (model: sonnet, effort: max, color: red, memory: none) |
| `templates/reviewer-template.md` | Standard reviewer (model: opus, effort: max, color: orange, memory: project) |
| `templates/codex/agents/{adversarial-reviewer, backend-builder, code-reviewer, frontend-builder, testing}.md` | Codex agent registry templates |

### 6.2 Per-project install

CC: `.claude/agents/<name>.md`. Codex: `.apd/agents/<name>.md`. Same frontmatter schema (§21.1). Scaffolded by `apd cdx agents add <name>` or `apd-setup` skill.

### 6.3 Validation

`bin/compiled/validate-agent-<os>-<arch>` — Go binaries cross-compiled for darwin/linux × amd64/arm64. Validates frontmatter against schema, computes/verifies signatures on `.done` markers (HMAC-style; defeats orchestrator forging via fake `.agents` entries). Source at `cmd/validate-agent/main.go` is gitignored — kept out of repo so orchestrator cannot read validation rules. See §23.

### 6.4 Scope enforcement

Server-side reads `scope: [...]` from agent's frontmatter. Caller-supplied `allowed_paths` ignored. Readonly agents (`readonly: true`) always block writes. Unscoped (no `scope`) allows all.

## 7. Skills

### 7.1 CC skills (`skills/`, 8 total)

| Skill | Trigger | Phase |
|---|---|---|
| `apd-setup` | Initial / re-init project | Bootstrap |
| `apd-brainstorm` | Pre-spec clarification (vague task) | Pre-spec |
| `apd-tdd` | TDD discipline during builder | Builder |
| `apd-debug` | Test/build/verify failure | Builder/Verifier |
| `apd-finish` | Post-commit decision (push/PR/keep/discard) | Post-commit |
| `apd-audit` | Project configuration audit | Anytime |
| `apd-github` | GitHub Projects integration | Anytime |
| `apd-miro` | Miro dashboard sync | Anytime |

### 7.2 Codex skills (`plugins/apd/skills/`, 7 total)

`apd-brainstorm`, `apd-tdd`, `apd-debug`, `apd-finish`, `apd-audit`, `apd-github`, `apd-miro`. Each: `SKILL.md` (markdown body) + `agents/openai.yaml` (Codex skill manifest). `apd-setup` remains CC-only — Codex uses the `apd cdx init` CLI.

### 7.3 Skill evals (`plugins/apd/evals/`, 27 scenarios)

Scenario-driven evaluation framework for shipped skills. Canonical source under `plugins/apd/evals/<skill>/*.json`; mirrored into `skills/<skill>/evals/` (CC, 24 scenarios; Codex-only scenarios excluded) and `plugins/apd/skills/<skill>/evals/` (Codex, 24 scenarios; no apd-setup) by `bin/core/eval-mirror`.

| Field | Purpose |
|---|---|
| `id` | Unique across all scenarios. Convention `<skill>-NN-<slug>`. |
| `skill`, `runtime` | Target skill + runtime (`cc`, `codex`, `both`). |
| `query` | User prompt that should trigger the skill. |
| `files` | Map of `path → content` materialized into a scratch dir before agent spawn. |
| `expected_behavior` | Plain-English assertion list; consumed by both rubric and LLM judge. |

Runner: `bin/core/skill-eval` — modes `--list`, `--dry-run`, `--rubric`, `--judge`; runtimes `cc` (`claude -p`) or `codex` (`codex exec`). `--list` shows each scenario's runtime. `--rubric` and `--judge` execute only scenarios whose `runtime` is `both` or matches `--runtime`; explicit `--dry-run --runtime <cc|codex>` validates that same no-spawn execution subset. Schema validation + duplicate-id check are part of `test-codex-adapter`. Evals are advisory — they are NOT a pipeline gate.

## 8. Templates & per-project scaffolding

| Template | Install behavior |
|---|---|
| `templates/CLAUDE.md.reference` (or `templates/codex/AGENTS.md`) | **Write-only-if-missing** — regen requires manual delete + re-init |
| `templates/codex/rules/{brainstorm, debug, finish, tdd}.md` | Always written (both pure-Codex and hybrid); only if missing |
| `templates/memory/{MEMORY, status, session-log, pipeline-skip-log}.md` | Per-project copy on init |
| `templates/principles/{en,sr}.md` | Per-project copy on language pick |
| `templates/verify-all/{node, php, python, go, java, dotnet}.sh` | `apd cdx verify-setup <stack>` writes wrapped script to `.codex/bin/verify-all.sh`; refuses overwrite without `--force` |

Idempotent installer: `_backup_if_exists` for files that must be modified (config.toml, hooks.json); pure skip for already-present scaffolds. See §19.1 for `install-codex-config` 8 steps.

## 9. Validation & test scripts

| Script | Coverage |
|---|---|
| `bin/core/test-codex-adapter` | 341 checks: tool registration, contract, env propagation, opt-out flow, report rendering, skill-eval schema/runtime filtering, adversarial pre-flight gate, severity gate, spec-card markdown-bold tolerance, guard-bash-scope read/write distinction, pipeline-gate stage completeness, parallel same-type dispatch gate, mkdir deny patterns, spec/builder/superpowers lock-in, apd_pipeline_metrics MCP tool, C2 Phase 2a/2b parser+migrate, codex-doctor C2 hint, v6.3 D max_defects immutability, v6.3 E communication discipline |
| `bin/core/test-hooks` | Static: hooks.json schema, placeholder fillness |
| `bin/core/test-system` | E2E synthetic pipeline (creates `/tmp/apd-test-XXXX`); 2 sections (Pipeline Lifecycle, Spec Enforcement) |
| `bin/core/verify-apd` | 60+ checks on configured project. **In-monorepo run mis-resolves** — copy example to `/tmp` for accurate result. |
| `bin/core/verify-contracts` | Cross-layer type contract check (TypeScript ↔ C#); regex-based, ~80% coverage |
| `bin/core/verify-trace` | `@trace R*` markers in tests; emits `TRACE:<covered>/<total>:<uncovered_ids>` to stdout |
| `bin/core/verify-all` | Project-side build+test runner; project ships `.codex/bin/verify-all.sh` to override |

## 10. Helpers (`bin/lib/`)

| File | Purpose |
|---|---|
| `resolve-project.sh` | `git rev-parse --show-toplevel` primary; cwd-walk + project-marker fallback. Sets `PROJECT_DIR`, `APD_PLUGIN_ROOT`, `MEMORY_DIR`, `PIPELINE_DIR`, `APD_AGENTS_DIR`. All scripts source it. |
| `style.sh` | ANSI helpers (`${D}`, `${R}`, `${V}`, `${G}`, `${RED}`); `apd_header`, `show_pipeline`, `_box_line`; `log_block` (sanitises newlines per F3) |
| `agents-parse.sh` | `parse_agents_log` → counts dispatch starts/exhausts (start without stop = maxTurn hit) |

## 11. Bootstrap

### 11.1 Session start (CC)

`hooks/hooks.json` registers `SessionStart` (matcher `startup`) and `PostCompact` against `bin/core/session-start`. Hook fires reliably from CC 2.1.101+ (re-confirmed on 2.1.119). Self-healing checks: jq install, script executability, settings.json validity, stale pipeline detection (>24h offers reset). 3600s TTL cache via `.last-init-check`.

### 11.2 Codex session-start (TUI hook only)

Codex 0.124+ fires `SessionStart` in TUI mode only, and timed to the first user prompt rather than the TUI banner:

1. **TUI path — `bin/adapter/cdx/session-start`** (wired via `.codex/hooks.json`, see §4.2). Drains stdin, restores `.codex/bin/apd` shortcut if deleted, runs `apd-init --quick` (gap analysis) throttled via `.last-init-check` (same 1h TTL as CC). Silent log at `<APD_PLUGIN_ROOT>/cdx-session-start.log`. Per openai/codex#15269, the hook fires when the user submits the first message in the TUI, not when the TUI renders.
2. **Exec mode — no automatic bootstrap path.** Earlier (pre-0.124) the manifest's `interface.defaultPrompt` could be used as a long system-style instruction, hypothetically picked up by the orchestrator. From Codex 0.124 the field is hard-capped at 3 entries × 128 chars and treated as user-facing starter prompts, not orchestrator guidance — see §14. `codex exec` users currently must invoke `apd_doctor` manually (or use `defaultPrompt` as a clickable starter prompt in TUI).
3. **Install-time** — MCP server `_bootstrap_shortcut()` creates `.codex/bin/apd` when `.codex/` already exists; runs on every MCP-tool invocation, idempotent.

**Live-validated on 2026-04-26 against Codex 0.124.0 + 0.125.0 in `~/Projects/Test`:** TUI session, first prompt submitted, hook fires and writes `START / resolve: PROJECT_DIR=/Users/zoranstevovic/Projects/Test APD_ACTIVE=true / gap-analysis: ran / END`. `apd_ping` via MCP returns `{version: <plugin-version>, runtime: codex, project_dir: <project>}` on every session.

## 12. Configuration surfaces

| Surface | Scope | Owner | Contains |
|---|---|---|---|
| `.claude/settings.json` | Project | apd-setup | CC project hooks + permissions |
| `.claude/settings.local.json` | Project | User | Local CC overrides (gitignored) |
| `~/.codex/config.toml` | User-global | User + APD bootstrap | `[features]` (codex_hooks, multi_agent), `[marketplaces.codex-apd]`, `[plugins."apd@codex-apd"]`, per-project trust levels |
| `plugins/apd/.mcp.json` | Plugin | Repo (shipped) | v6.0+ self-registers the APD MCP server with `cwd: "."` (resolves to plugin cache root, where `mcp/apd_mcp_server.py` lives). Contains per-tool approval metadata, but Codex 0.125 does not honor it for TUI prompts. |
| `<project>/.codex/config.toml` | Project | install-codex-config | Complete `[mcp_servers.apd]` transport override plus 8 `[mcp_servers.apd.tools.<name>] approval_mode = "approve"` blocks. This is the effective no-prompt path for APD MCP tools in Codex 0.125. Other sections (codex features, plugin trust) are user-managed. |
| `<project>/.codex/hooks.json` | Project | install-codex-config | PreToolUse Bash → guard-bash-scope shim; SessionStart → cdx session-start (TUI only) |
| `.apd/config` (or legacy `.claude/.apd-config`) | Project | apd-init | `PROJECT_NAME`, `APD_VERSION`, `STACK` metadata |
| `.apd/agents/<name>.md` (Codex) / `.claude/agents/<name>.md` (CC) | Project | apd-setup or `apd cdx agents add` | Per-agent scope + frontmatter |

## 13. Versioning

- Source of truth: `plugins/apd/VERSION` file + `version` field in plugin manifests (`.claude-plugin/plugin.json` for CC, `plugins/apd/.codex-plugin/plugin.json` for Codex). Pre-v6.0 the VERSION file lived at repo root; moved into the plugin folder so the Codex plugin cache can see it.
- `bump-version` script (gitignored) updates VERSION + manifest version + CHANGELOG entry
- Semantic versioning: major (breaking), minor (feature), patch (fix)
- **No bumps without explicit user request** (durable rule)

## 14. Known limitations & gaps

- **`pipeline-advance` spec case** has CC-specific Next-steps block — works for CC, ignored by Codex orchestrator.
- **`SessionStart` hook in Codex TUI** — fires only on first user prompt, not at TUI banner (openai/codex#15269). Live-validated on 0.124.0 + 0.125.0; not re-tested on 0.128. CC side resolved in CC 2.1.101.
- **`codex exec` has no APD bootstrap** — `SessionStart` does not fire in exec mode, and `interface.defaultPrompt` is hard-capped at 3 × 128 chars (treated as user-facing starter prompts). exec-mode users must invoke `apd_doctor` manually. No upstream entry point yet.
- **`guard-parallel-same-agent` missing** — 3× parallel dispatch caused conflicts (backlog).
- **In-monorepo `verify-apd`** mis-resolves project root.
- **CC `SubagentStop` hook** is the only `.agents` log telemetry source on CC; Codex has no equivalent (relies on inline orchestrator state).
- **Pipeline reset is NOT auto-triggered** — orchestrator must explicitly call. Design choice, not a bug.
- **`mkdir .pipeline/` orchestrator bypass** — backlog: address via `permissions.deny`.
- **Superpowers plugin conflict** — mechanical blocking needed (backlog).

---

# Part II — Internal mechanics

## 15. Constants reference

| Category | Constant | Value | Source |
|---|---|---|---|
| Budget — spec_criteria | green_max | 4 | `_budget_status` in MCP server |
| Budget — spec_criteria | yellow_max | 7 | same; also enforced as hard limit by `pipeline-advance spec` |
| Budget — reviewed_files | green_max | 4 | MCP server |
| Budget — reviewed_files | yellow_max | 6 | MCP server |
| Budget — verifier_duration_s | thresholds | none | informational only |
| Lean eligibility | reviewed_files ≤ 4 AND spec_criteria ≤ 2 | — | MCP `apd_pipeline_state` |
| Adversarial — empty pass notes | min chars (when total=0) | 80 | `apd_adversarial_pass` |
| Verifier cache | TTL (skip if fresh) | 120s | verify-all.sh + `verified.timestamp` |
| `.last-init-check` | TTL (re-check init) | 3600s | session-start |
| Stale pipeline | warn threshold | 24h | session-start auto-offer-to-reset |
| Timeout — `_run_script` default | 30s | MCP `_run_script` |
| Timeout — `apd_verify_step` | 300s | MCP |
| Timeout — `codex-doctor` | 10s | MCP |
| Timeout — guard-bash-scope hook | 5s | `<project>/.codex/hooks.json` |
| Regex — `apd_role` whitelist | `[A-Za-z0-9_.-]+` | `apd_guard_write` |
| Default agent maxTurns | 40 (builders), 30 (reviewers) | agent templates |
| Effort levels | xhigh ≈ 40 turns, max ≈ 30 turns | agent template guidance |

## 16. CLI scripts deep dive

### 16.1 Pipeline lifecycle scripts

**`apd-init`** (CC primary; sets up project from scratch or gap-fills)
- CLI flags: `--version`, `--quick` (skip verification)
- Reads userConfig: `CLAUDE_PLUGIN_OPTION_PROJECT_NAME`, `CLAUDE_PLUGIN_OPTION_STACK`, `CLAUDE_PLUGIN_OPTION_AUTHOR_NAME`
- NEW mode: creates `.apd-config`, `.apd-version`, `workflow.md`, `principles.md`, stack-specific `verify-all.sh`, three default agents (`backend-api`, `code-reviewer`, `adversarial-reviewer`), `settings.json` with hooks+permissions
- UPDATE mode: gap-fills missing files, validates agent frontmatter, updates `.apd-version`
- Stack selector chooses verify-all.sh template
- Version embedded at build time via `APD_VERSION` env var

**`pipeline-advance`** — single entry for all gate operations. Steps:
- `spec <task>` — validates ≤7 criteria, archives prior `.agents`, writes spec.done + `.spec-hash` + `.spec-max-defects-history`. v6.3 D: BLOCKS if `max_defects` is raised for the same task across re-advance (rollback+re-spec loophole). Reset wipes the snapshot.
- `builder` — checks `implementation-plan.md` present + `### Agents` section dispatched (CC), else BLOCK; writes builder.done
- `reviewer` — sets `.adversarial-pending` flag (Full) OR honors `adversarial: skip` if ≤2 criteria (Lean opt-out); writes reviewer.done
- `verifier` — runs `verify-all.sh`; blocks on failure; in Full mode blocks on missing `.adversarial-summary`; writes verifier.done + `verified.timestamp`
- `reset [learning-text]` — full archive + cleanup flow (see §16.4 telemetry)
- `rollback` — undoes last completed step (sequential: verifier → reviewer → builder → spec)
- `status` — prints current state
- `stats` / `metrics` — read from `pipeline-metrics.log`
- `init` — first-run scaffolding (called by apd-init)

**`pipeline-doctor`** — 11-section audit:
1. Pipeline state (which `.done` files exist, sequence)
2. Spec card existence
3. Spec freeze (SHA256 vs `.spec-hash`)
4. Implementation plan presence
5. Agent registry (frontmatter parsed)
6. Guard executability (chmod +x check)
7. Trace coverage (calls `verify-trace --summary`)
8. Adversarial summary presence
9. GitHub sync status
10. Plugin version
11. Legacy directory + stale path detection

Exit 0 if no FAIL; 1 otherwise. Auto-heals legacy hook paths if found.

**`pipeline-gate`** — pre-commit hook caller via `git commit` with `APD_ORCHESTRATOR_COMMIT=1`. Verifies all 4 `.done` files exist; if validate-agent binary available, calls `validate-agent verify -step <step>` to detect forged signatures. Exit 0 = OK, 2 = block.

**`pipeline-post-commit`** — PostToolUse hook on `Bash(git commit*)` with `APD_ORCHESTRATOR_COMMIT=1`. Calls `pipeline-advance reset` after successful commit. Hook never blocks (always exit 0).

**`pipeline-report`** — render formatted summary box. Reads `*.done` timestamps, spec criteria count, adversarial summary (renders "rationale recorded" if 0/0/0 with notes; "N/A" if Lean skipped), `guard-audit.log` (silent skip orphan lines per F3).

### 16.2 Guards — full table

| Guard | Trigger | Concrete checks |
|---|---|---|
| `guard-git` | PreToolUse Bash + git matcher | Force-push, `git add .`, `--no-verify`, `git reset --hard`, commits without `APD_ORCHESTRATOR_COMMIT` env when pipeline incomplete |
| `guard-bash-scope` | PreToolUse Bash | Bash writes outside agent scope: `cp`, `mv`, `mkdir`, `>`/`>>` redirect, runtime exec (`node -e`, `python -c`) targeting forbidden paths |
| `guard-scope` | PreToolUse Write/Edit | Canonicalizes via realpath; rejects unresolved `..`; checks file inside PROJECT_DIR; prefix-matches against `--allowed_paths` list |
| `guard-orchestrator` | PreToolUse Write/Edit | Blocks if no `agent_id` (= orchestrator) AND target matches stack code patterns (php=`.php`, nodejs=`.js\|.ts\|.tsx\|.jsx\|.mjs\|.cjs`, python=`.py`, dotnet=`.cs\|.fs`, go=`.go`, java=`.java\|.kt\|.scala`). Allows `.claude/*`, `CLAUDE.md`, `.gitignore`, `*.md`, `docs/*`, config formats (json, yaml, toml, xml, lock) |
| `guard-pipeline-state` | PreToolUse Write/Edit | Only guards `.apd/pipeline/*`; allows orchestrator to write `spec-card.md`, `implementation-plan.md`, `.adversarial-summary`; blocks all others (`.done`, `.agents`, `.spec-hash`, `.trace-summary`, `verified.timestamp`) |
| `guard-lockfile` | PreToolUse Write/Edit | Basename whitelist: `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `packages.lock.json`, `composer.lock`, `Gemfile.lock`, `poetry.lock`, `Cargo.lock`, `go.sum` |
| `guard-secrets` | PreToolUse Write/Edit/Bash | Customizable pattern list (default: `.env.production`, `.env.staging`, `.pem`, `.key`, `id_rsa`, `id_ed25519`, `credentials.json`, `.docker/config.json`, `appsettings.Production.json`, `user-secrets`); checks both file path and command text |
| `guard-send-message` | PreToolUse SendMessage | Blocks if `spec.done` exists (active pipeline) — SendMessage bypasses SubagentStart/Stop hooks so dispatch wouldn't be recorded |
| `guard-compact` | PreCompact | Blocks if pipeline incomplete (any `.done` missing); preserves state across CC compaction |
| `guard-permission-denied` | PostToolUse PermissionDenied | Telemetry only; appends to guard-audit.log; never blocks |

All log via shared `log_block` to `<memory>/guard-audit.log` (sanitised newlines/CR per F3).

### 16.3 Telemetry & tracking

**`track-agent`**
- CC: invoked by SubagentStart/SubagentStop hooks via `--event start|stop`
- Codex: adapter invokes manually (no equivalent hook)
- Appends `<ts>|<event>|<agent_type>|<agent_id>` to `.apd/pipeline/.agents`
- Warnings on SubagentStart: builder dispatched without `pipeline-advance builder` call; adversarial dispatched before reviewer.done
- Side effect: also writes raw hook payload to `agent-dispatch-debug.log` for troubleshooting Codex adapter mismatches

**`rotate-session-log`**
- Manual or end-of-pipeline reset; arg `MAX_ENTRIES` (default 10)
- Counts `^## \[` headers; keeps last N; archives older to `session-log-archive.md` with meta-summary (task count, problem count, guard block count, rule count, date range)
- Skips if entries ≤ MAX_ENTRIES
- CC only

**`gh-sync`**
- Steps: `spec` (create issue or find by title), `builder/reviewer/verifier` (add comment), `done` (close + commit link), `skip` (close + apd-skip label), `status` (show)
- Persists issue number in `.gh-issue` (cleared on close/skip)
- Best-effort, non-blocking; pipeline proceeds even if `gh` CLI fails

### 16.4 Verification scripts

**`verify-all.sh`** (project-shipped)
- Reads `APD_VERIFY_SCOPE` env from `apd_verify_step`: `"fast"` = build+touched tests, `"full"` = complete suite (default)
- Cache: skips if `verified.timestamp` <120s AND no new git changes
- Per-stack templates wrap header (cache + CHANGED_FILES) + body (ERRORS array population) + footer (exit 1 if ERRORS, else 0)

**`verify-contracts`**
- Modes: `<backend_dir> <frontend_dir>`, `--changed`, `--help`
- Parsers: TypeScript regex (`export interface/type` + fields), C# regex (`public class/record` + properties)
- Builds type maps `typename|fieldname|fieldtype|nullable`; reports mismatches
- ~80% coverage; complex generics need manual review
- Portable awk (BSD + GNU compatible)

**`verify-trace`**
- Modes: full report (stderr), `--summary` (stdout)
- Parses `R*` IDs from spec-card; discovers test files (stack-aware patterns); scans tests + code for `@trace R<n>` markers
- Detects extras (`@trace R5` without R5 in spec)
- Stdout summary: `TRACE:<covered>/<total>:<uncovered_ids>`
- Backward-compatible: no spec-card → exit 0

**`test-system`**
- Creates `/tmp/apd-test-XXXX` isolated project; cleans via trap
- 2 sections: Pipeline Lifecycle (spec hash, builder-without-plan block, agent dispatch validation, reset cleanup) + Spec Enforcement (max 7 criteria, tampering detection)
- Helper functions: `run`, `run_exit`, `guard_test` (pipes stdin to guard)

### 16.5 Bootstrap (`session-start`)

- Early action: creates `.claude/bin/apd` shortcut (idempotent) before anything that might timeout
- Gap analysis: runs `apd-init --quick` once per hour (cached via `.last-init-check`)
- Self-healing: validates jq, chmod +x core scripts, detects settings.json conflicts, flags stale pipeline (>24h) with auto-offer-to-reset
- Version checks: reads `MIN_CC_VERSION` and `FUNC_CC_VERSION` from plugin; warns if CC too old (numeric comparison: major*10000 + minor*100 + patch)
- Always exit 0
- CC only

## 17. MCP server internals — `plugins/apd/mcp/apd_mcp_server.py`

### 17.1 Module-level + bootstrap

- FastMCP wrapper: `mcp = FastMCP("apd")`. Functions decorated `@mcp.tool()` auto-exposed.
- 8 tools registered.
- No persistent daemon — Codex spawns fresh process per session via `uv run --with mcp python mcp/apd_mcp_server.py` (cwd resolves to plugin root via plugin-shipped `.mcp.json`).
- `APD_PLUGIN_ROOT = Path(__file__).resolve().parent.parent` resolves to `plugins/apd/` (v6.0+). All sibling paths (`bin/`, `templates/`, `rules/`, `VERSION`) live in the same plugin folder so Codex's plugin cache contains everything the server needs.
- `_bootstrap_shortcut()` fires on `__name__ == "__main__"`. Creates `<project>/.codex/bin/apd` shell wrapper execing plugin entry. Idempotent: skips if shortcut exists with correct path substring. Only runs if `.codex/` dir exists. `mkdir -p` parent + `chmod 0o755`.

### 17.2 Project resolution — `_project_dir()` + `_is_project_root()`

Algorithm (priority order):
1. `APD_PROJECT_DIR` env var if set
2. `git rev-parse --show-toplevel` if path contains any project marker
3. cwd walk upward, return first dir with marker
4. Fallback: cwd

Project markers (`_PROJECT_MARKERS`): `.codex/`, `AGENTS.md`, `.claude/`, `CLAUDE.md` (file or dir).

### 17.3 Subprocess helpers

**`_run_script(path, *args, timeout=30, env_extra=None)`**
- Pins `cwd` and `APD_PROJECT_DIR` env to resolved project
- `_codex_env()` base: copy `os.environ` + add `APD_RUNTIME=codex` + `APD_PROJECT_DIR`
- `env_extra` overlays via `env.update()` (later wins)
- Returns `{ok, exit_code, stdout, stderr}`; on timeout: `{ok: false, error: "timed out after Xs"}`

**`_run_core(script, *args, timeout, env_extra)`**
- Thin wrapper: resolves script name to `bin/core/<script>` path
- Identical env propagation

Example: `apd_verify_step()` calls `_run_core("verify-all", timeout=300, env_extra={"APD_VERIFY_SCOPE": scope})` so verify-all.sh can read `$APD_VERIFY_SCOPE`.

### 17.4 Agent registry — `_agents_dir()` + `_parse_agent_frontmatter()`

- Resolution: CC-first (`.claude/agents/`), Codex fallback (`.apd/agents/`), None if neither
- Hand-rolled YAML parser (no external dep): splits on `\n---`, handles scalars (name, description, model, effort, maxTurns, memory, color, permissionMode, readonly) + lists (`scope:` with `- item` or flow `[a,b]`)
- Coerces `maxTurns` to int, strips quotes from scalars
- Returns `{}` if file missing/malformed
- `apd_list_agents()` normalizes scope to always-list

### 17.5 Budget thresholds — `_budget_status()`

```
value <= green_max  → "green"
value <= yellow_max → "yellow"
else                → "red"
```

See §15 for actual numbers. `verifier_duration_s` is informational only (no thresholds).

### 17.6 `.done` file format — `_read_done()`

- Line 1: `<epoch_seconds>|<human-readable-time>[|<task-name>]`
- Line 2: HMAC signature (validate-agent verifies; MCP ignores)
- Parses with `split("|", 2)`; returns `{done, ts, time, task?}`
- Malformed/missing: returns `{done: false}` gracefully

### 17.7 Per-tool security

**`apd_advance_pipeline(step, arg)`**
- Step whitelist: `{spec, builder, reviewer, verifier, init, status, stats, metrics, reset, rollback}`
- Returns error dict if unknown
- `arg` passed through (task name for spec, learning text for reset, description for init); no further validation

**`apd_guard_write(apd_role, file_path)`** — defense in depth:
1. `apd_role` regex whitelist `[A-Za-z0-9_.-]+`; rejects path separators, parent refs, dots-only
2. Filesystem escape defense: resolves `agents_dir` and `agent_file` to canonical paths; confirms `agent_file.parent == agents_dir` (blocks symlink breakouts)
3. `readonly` coercion: bool, string ("true"/"yes"/"1"); if true → exit_code 2 + error
4. `scope` coercion: always list; empty if missing
5. Delegates to `bin/core/guard-scope`

**`apd_verify_step(scope)`**
- Whitelist `{full, fast}`
- Looks up project verify-all.sh: `.codex/bin/verify-all.sh` (Codex) → `.claude/bin/verify-all.sh` (hybrid fallback) → framework default
- 300s timeout; `APD_VERIFY_SCOPE` env propagation

**`apd_adversarial_pass(total, accepted, dismissed, notes)`**
- `total, accepted, dismissed >= 0`
- `accepted + dismissed <= total`
- If `total == 0`: `notes` required ≥ 80 chars (rubber-stamp prevention)
- Writes `.adversarial-summary`: `ADVERSARIAL:T:A:D` + optional Notes block

## 18. Codex adapter scripts — `plugins/apd/bin/adapter/cdx/`

### 18.1 `install-codex-config` — full 8 steps

**Pre-flight guard:** refuses to run if resolved project path == APD framework repo path (canonical comparison via `pwd -P`). Prevents accidentally scaffolding APD into APD source. Bypass not possible — must pass explicit non-framework project path.

1. **MCP Server Registration / Repair** — Python idempotence check that writes or repairs APD-owned `[mcp_servers.apd]` config. Desired state is a full transport block (`command = "uv"`, relative `mcp/apd_mcp_server.py`, `cwd = "<plugin-root>"`) plus all 8 per-tool `approval_mode = "approve"` sections. Any stale APD-owned block is replaced atomically; unrelated TOML sections are preserved. Exit code 10 signals a write/update happened.
2. **Per-Agent Sandbox Profiles** — INTENTIONALLY DISABLED. Codex 0.121.0 doesn't enforce FileSystemSandboxPolicy at runtime. Per-agent stays in MCP `apd_guard_write`.
3. **`.codex/bin/apd` Shortcut** — idempotent; creates wrapper execing `bin/apd`, chmod +x.
4. **`.apd/config` Seed** — only if neither `.apd/config` nor `.claude/.apd-config` exist. Contents: `PROJECT_NAME=<basename>`, `APD_VERSION=<from VERSION or plugin.json>`, `STACK=`. Activates pure-Codex without touching `.claude/`.
5. **AGENTS.md** — write-only-if-missing; templated `{{PROJECT_NAME}}` substitution.
6. **`.apd/rules/{brainstorm,tdd,debug,finish}.md`** — always written for both pure-Codex + hybrid; only if missing.
7. **`.apd/` Scaffold** — pure-Codex only (skip if `.claude/` exists). Memory tree: MEMORY.md, status.md, session-log.md. `.apd/.apd-version`. Empty `.apd/agents/` placeholder. Workflow rules rewritten: `.claude/bin/apd` → `.codex/bin/apd` paths.
8. **hooks.json Merge** — Python checks for existing PreToolUse Bash entry. Desired: `{type:"command", command:"bash <guard-bash-scope-path>", timeout:5}`. Idempotent (skip if present), updates timeout if stale, replaces old APD entries at same slot. Backs up existing hooks.json.

### 18.2 `agents-scaffold`

- `list|ls` — available templates + installed agents
- `add <name> [scope-paths...]` — copy template; `--force` to overwrite existing
- Template substitution: `{{PROJECT_NAME}}` via sed
- Scope override (Python inline): finds opening/closing `---`, isolates frontmatter; if `scope:` present, replaces + skips list items; if absent, inserts after first `---`

### 18.3 `codex-doctor`

- **Invocation:** `apd cdx doctor [project]` — optional first arg is project path; if omitted, resolves to cwd
- Exit codes: 0 = no FAIL (may have WARN), N = N failed checks
- 6 sections: Prerequisites (uv, python3, jq, codex CLI), Global Codex config (`~/.codex/config.toml` + `codex_hooks` flag), Project `.codex/` (checks project `[mcp_servers.apd]` override + 8 approvals, plugin `.mcp.json` fallback, hooks.json guard wire, `.codex/bin/apd` shortcut), .apd content (config marker, workflow.md, memory files, agents dir, .apd-version), AGENTS.md at root, MCP server (syntax check, all 8 tool functions present)

### 18.4 `skills-install`

Modes:
- **Marketplace (default since v5.0.8)**: registers plugin repo as a local Codex marketplace and enables `[plugins."apd@codex-apd"]` in `~/.codex/config.toml`. On Codex 0.124+ this surfaces every APD skill in the `/` slash menu under the APD plugin entry. Equivalent to running `codex plugin marketplace add <plugin-root>` plus toggling the plugin block. After this, run `codex plugin marketplace upgrade codex-apd` in a fresh TUI to populate the plugin cache.
- **`--legacy-symlink` (deprecated)**: symlinks into `~/.codex/skills/<name>/`. Flags: `--copy` (copy not symlink), `--force` (overwrite user-modified). Defaults to all 4 skills if none named. Was the default through v5.0.7 (Codex 0.121 era when marketplace was upstream-blocked); on 0.124+ these symlinks now coexist with the plugin cache and produce duplicates in the slash menu, so the mode prints a deprecation warning. Will be removed in a future major.

Overwrite protection: symlinks always replaced (safe); real dirs replaced only if SKILL.md matches canonical OR `--force`.

Status check output: `✓ symlink → path` / `✓ (copy)` / `— not installed`.

### 18.5 `verify-setup`

- `list|--list|ls` — show available stacks
- `<stack> [--force]` — scaffold `.codex/bin/verify-all.sh` from template; refuses overwrite without `--force`
- Wraps fragment with header (cache logic + CHANGED_FILES via git) + footer (exit on ERRORS array)

### 18.6 `guard-bash-scope` shim

- Reads stdin via `cat`
- Tries field paths in order: `.tool_input.command` → `.toolInput.command` → `.command` (Codex schema not finalized; falls back to jq empty if all fail)
- Passes normalized `--command <value>` to core `guard-bash-scope`

## 19. Plugin manifests — full field detail

### 19.1 `.claude-plugin/plugin.json` (CC)

| Field | Value | Meaning |
|---|---|---|
| `name` | `claude-apd` | Marketplace identifier |
| `version` | mirrors `plugins/apd/VERSION` (source of truth) | Bumped via `bump-version` |
| `description` | "Agent Pipeline Development — enforced multi-agent pipelines with mechanical guardrails" | Positioning |
| `author.name` | Zoran Stevovic | No AI co-authors |
| `homepage` | https://apd.run | Marketing |
| `repository` | https://github.com/zstevovich/claude-apd | Source |
| `license` | MIT | OSS license |
| `userConfig` | 3 fields | Install-time prompts |

userConfig fields (prompted during `/apd-setup`):
- `project_name` (string)
- `stack` (selector: nodejs, php, python, dotnet, go, java)
- `author_name` (string)

### 19.2 `.claude-plugin/marketplace.json`

Single plugin entry under `zstevovich-plugins` namespace; mirrors plugin.json fields with GitHub source link.

### 19.3 `plugins/apd/.codex-plugin/plugin.json` (Codex)

| Field | Value |
|---|---|
| `name` | `apd` |
| `version` | `4.7.20` (lags CC by one — manual sync) |
| `description` | "Enforced spec → builder → reviewer → verifier pipeline" + MCP mention |
| `skills` | `./skills/` (directory of `.md` skill files) |
| `interface.displayName` | APD |
| `interface.shortDescription` | Pipeline one-liner |
| `interface.longDescription` | 3-sentence MCP server explanation |
| `interface.category` | Coding |
| `capabilities` | `[Interactive, Write]` |
| `defaultPrompt` | 3 user-facing starter prompts (≤128 chars each per Codex 0.124+ spec): bootstrap APD, brainstorm a spec card, audit APD setup. |

### 19.4 `.agents/plugins/marketplace.json` (Codex marketplace)

Single plugin entry under `codex-apd` namespace; `policy: INSTALLED_BY_DEFAULT`. Codex auto-registers APD as first-class plugin; no manual install step.

## 20. Templates schema deep dive

### 20.1 Master agent template (`templates/agent-template.md`)

Frontmatter:
| Field | Example | Purpose |
|---|---|---|
| `name` | `{{agent-name}}` | Identifier; used in `apd_guard_write(apd_role)` |
| `description` | "Short domain + responsibility" | Listing label |
| `tools` | Read, Write, Edit, Glob, Grep, Bash | Tool whitelist |
| `model` | sonnet / opus | LLM assignment |
| `effort` | xhigh ≈ 40 turns, max ≈ 30 turns | Context budget hint |
| `color` | `{{AGENT_COLOR}}` | UI indicator |
| `maxTurns` | 40 (builders), 30 (reviewers) | Turn budget cap |
| `permissionMode` | `bypassPermissions` (builders), `plan` (reviewers) | CC permission mode |
| `memory` | `project` (builders), `none` (adversarial) | Session memory scope |
| `scope` (body comment) | `# src/ tests/` | Allowed paths; enforced by guard-scope |

Per-agent hooks in frontmatter:
- `Read` → guard-secrets
- `Write|Edit` → guard-scope `{{SCOPE_PATHS}}` + guard-secrets
- `Bash(git *)` → guard-git
- `Bash` → guard-bash-scope `{{SCOPE_PATHS}}` + guard-secrets

### 20.2 Reviewer / Adversarial templates

| | Reviewer | Adversarial |
|---|---|---|
| Model | opus | sonnet |
| Effort | max | max |
| Color | orange | red |
| maxTurns | 30 | 30 |
| permissionMode | plan | plan |
| memory | project | **none** (context-free) |
| Reads | files in `.reviewed-files` | discovered by scope |
| Output | findings (Critical/Important/Minor with file:line) | findings + total/accepted/dismissed counts |
| `apd_guard_write` | not called | MUST NOT call (read-only) |
| Mandatory notes when total=0 | n/a | yes (≥80 chars) |

### 20.3 Codex agent templates

| Agent | Model | maxTurns | Scope (default) |
|---|---|---|---|
| backend-builder | sonnet | 40 | `src/`, `config/` |
| frontend-builder | sonnet | 40 | `assets/`, `templates/` |
| testing | sonnet | 30 | `tests/` |
| code-reviewer | opus | 30 | (read-only) |
| adversarial-reviewer | opus | 30 | (read-only) |

### 20.4 Codex rules (`templates/codex/rules/`)

| Rule | Activation | Principle |
|---|---|---|
| `brainstorm.md` | Vague/broad/unclear task | "NO SPEC WITHOUT SHARED UNDERSTANDING FIRST"; one question at a time, present trade-offs, converge, wait for approval |
| `tdd.md` | Builder phase | "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST"; red→green→refactor; minimal code; every write through `apd_guard_write` |
| `debug.md` | Failure (test/build/verify/critical review) | "NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST"; 4 phases (root cause + reproduce, pattern analysis, hypothesis + controlled test (escalate after 3 fails), fix with TDD) |
| `finish.md` | Pipeline complete pre-push | "NO PUSH WITHOUT USER DECISION FIRST"; verify tests, show report, present 4 options (push, push+PR, keep local, discard) |

### 20.5 Memory scaffolds (`templates/memory/`)

| File | Purpose |
|---|---|
| `MEMORY.md` | Index of cross-session learnings; quick reference (stack, branches, ports), links to status/session-log/pipeline-skip-log |
| `status.md` | Current phase + focus; updated end-of-session |
| `pipeline-skip-log.md` | Audit table of skipped tasks (date, reason, category); enables retrospective analysis of enforcement gaps |
| `session-log.md` | Append-only chronological log; one entry per task cycle; "New rule" field filled by `pipeline-advance reset` arg |

### 20.6 Principles (`templates/principles/`)

Two language variants (`en.md`, `sr.md`), identical structure:

| Category | Rule |
|---|---|
| Language | Docs + communication in [English/Serbian]; technical terms always English; professional tone, no AI sound |
| Code | Minimal comments (logic-only); i18n support from start |
| Git | No AI signatures (`Co-Authored-By`); branches develop→staging→main; `.claude/settings.local.json` + `.apd/pipeline/` gitignored; commits short + English + imperative mood |
| Docker | Infrastructure only (DB, cache, monitoring); apps run from IDE debug mode |

### 20.7 verify-all per-stack scaffolds

Stack templates at `templates/verify-all/<stack>.sh`. Generic shape: detect entry point, run build, run test suite, populate ERRORS array. Wrapped at install time by `verify-setup` with header (cache + CHANGED_FILES) + footer (exit on ERRORS).

| Stack | Build + test |
|---|---|
| node | `npm build` + `npm test`; separate frontend if present |
| python | `pip install`, `pytest`, coverage |
| php | `composer install`, `phpunit` |
| dotnet | `dotnet build`, `dotnet test` |
| go | `go build`, `go test` |
| java | Maven or Gradle + test suite |

## 21. Documentation map

### 21.1 Top-level docs

| File | Lines | Purpose |
|---|---|---|
| `README.md` | 319 | Pipeline diagram, 5-role table, two install paths (CC + Codex), commands table, pipeline report sample |
| `CLAUDE.md` | 111 | Framework-level project context (this is APD's self-CLAUDE.md, not per-project template); critical rules, stack table, architecture tree, dev conventions |
| `GETTING-STARTED.md` | 437 | Part A (CC: marketplace install + apd-setup) + Part B (Codex: git clone + apd cdx init); marketplace caveat for Codex |
| `CHANGELOG.md` | 1101 | Per-version Added/Fixed/Tests sections back through v3.x |

### 21.2 ADR-001: Runtime Contract & Adapter Architecture

`docs/adr/001-runtime-contract.md` — Accepted decision.

**Problem:** 9 mixed guards directly parse CC hook stdin JSON; if CC protocol changes, all break simultaneously.

**Decision:** 3 parts:
1. Define APD Runtime Contract — 7 normalized events: identity, dispatch_start, dispatch_stop, tool_request, tool_result, transition_request, audit_entry. JSON shape; guard verdicts: `allow` / `block`.
2. Classify components: Core (pipeline-advance, validate-agent, verify-trace, etc.) vs. Adapter (hooks.json, guard-send-message, skill defs) vs. Mixed (guards with both policy logic + CC I/O parsing).
3. Migration: Phase 1 (name boundary, now), Phase 2 (normalize input layer with thin shims), Phase 3 (second runtime adapter).

**Consequences:** Positive — CC updates only affect adapter shims; core testable without CC; second runtime support bounded. Negative — indirection layer; testing covers both layers; CC quirks (SendMessage gap) remain in adapter.

### 21.3 Plans + specs (`docs/plans/`, `docs/specs/`)

April 2026 cohort:

| Plan | Topic | Status |
|---|---|---|
| 2026-04-09-adversarial-reviewer | Context-free reviewer + hit-rate metrics | Implemented (v4.7.0+) |
| 2026-04-09-spec-traceability | `@trace R*` coverage in verifier gate | Implemented |
| 2026-04-10-plan-step-and-enforcement | Hard-enforce spec-card + implementation-plan; soft-warn adversarial-summary | Implemented |
| 2026-04-12-runtime-contract-adapter | Refactor CC stdin parsing to thin shim | In-progress (Phase 1+2) |
| 2026-04-18-codex-adapter-phase1 | Codex POC | Complete; manifest layout changed |
| 2026-04-18-codex-adapter-phase2 | Codex hybrid enforcement (supersedes phase 1) | Complete |

`docs/plans/README.md` flags state-at-time; authoritative sources are CHANGELOG, templates, `bin/core/`. Drifts noted: `.claude/.pipeline/` → `.apd/pipeline/` (v4.3.4); `maxTurns` bumped (v4.7.13).

### 21.4 `mcp/README.md`

Codex runtime integration doc: install (pip/uv), wire into `.codex/config.toml`, 8 tools listed with brief descriptions, "Coming later: apd_dispatch_agent" (awaits Codex agent-dispatch semantics).

## 22. `validate-agent` Go binary

### 22.1 Purpose

Validates agent frontmatter integrity. Computes/verifies signatures on `.done` markers (line 2 of each `.done` file). Defeats orchestrator forging via fake `.agents` entries that earlier bash-based validator routinely missed.

### 22.2 Execution points

- Every `pipeline-advance` step (validates step-specific invariants)
- `pipeline-gate` pre-commit (verifies all 4 `.done` signatures via `validate-agent verify -step <step>`)

### 22.3 Distribution

| Binary | Platform | Size |
|---|---|---|
| `validate-agent-darwin-arm64` | macOS M1+ | 2.7 MB |
| `validate-agent-darwin-amd64` | macOS Intel | 2.8 MB |
| `validate-agent-linux-amd64` | Linux x64 | 2.8 MB |
| `validate-agent-linux-arm64` | Linux ARM64 | 2.8 MB |

### 22.4 Source location + rationale

Source: `cmd/validate-agent/main.go` — **gitignored locally**. Reason: if source were in repo, orchestrator would learn validation rules, defeating compilation-based enforcement. Reference: `.claude/memory/reference-go-source.md` documents location, build commands, gitignore rationale.

Build: `GOOS=<os> GOARCH=<arch> go build -ldflags="-s -w" -o bin/compiled/validate-agent-<os>-<arch> cmd/validate-agent/main.go` for all 4 platforms; commit only binaries.

---

## 23. Document maintenance

This SPEC was first written incrementally as of `1dab772` (2026-04-24) then expanded with deep-dive details from 3 parallel codebase audits in the same session.

It is the authoritative reference. Code without an entry here is undocumented. Any framework change that adds, renames, or removes a script, MCP tool, hook event, guard, gate, telemetry file, agent/skill/template, configuration surface, or constant SHOULD update this document in the same commit.

Sections most likely to drift over time: §15 (constants), §16.2 (guard table), §17.7 (per-tool security), §18.1 (install-codex-config steps), §19 (manifest fields). Set a recurring review on these whenever a runtime change ships.
