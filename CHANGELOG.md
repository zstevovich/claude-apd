# Changelog

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

- **`docs/SPEC.md`** — §1 (Distribution: `apd update` row), §2 (CLI surface: `update` subcommand), §4.2 (Codex hooks: now 2 hooks, SessionStart tabela), §11.2 (Codex session-start dual path — TUI hook + exec `defaultPrompt`), §12 (hooks.json content), §14 (SessionStart known-limitations updated).

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
