# Codex Adapter — Phase 1 POC

**Goal:** Prove that APD can run under Codex CLI 0.121.0 by shipping a minimal `bin/adapter/cdx/` peer to the existing `bin/adapter/cc/`, with a working `.codex-plugin/plugin.json` and a per-plugin `hooks.json`. Scope is end-to-end smoke test, not feature parity.

**Non-goals for Phase 1:**
- Full guard parity (scope-write enforcement, reviewer dispatch, etc.) — deferred to Phase 2
- Skill translation (agent YAML sidecars) — deferred to Phase 2
- CI matrix across both runtimes — deferred to Phase 5

**Reference:** `.claude/memory/project-codex-plugin-structure-verified.md` (observed layout + official spec corrections)

---

## Architecture

```
apd-template/                             # shared source of truth
├── .claude-plugin/plugin.json            # existing CC manifest
├── .codex-plugin/plugin.json             # NEW — Codex manifest (phase 1)
├── .agents/plugins/marketplace.json      # NEW — registers self for `codex marketplace add`
├── bin/
│   ├── core/                             # unchanged — runtime-agnostic
│   ├── adapter/cc/                       # unchanged — CC shims
│   └── adapter/cdx/                      # NEW — Codex shims (phase 1: 4 events)
├── hooks/
│   ├── hooks.json                        # existing — CC hooks
│   └── hooks.codex.json                  # NEW — Codex hooks (referenced from .codex-plugin/plugin.json)
└── ...
```

## Phase 1 deliverables

| # | Artefact | Status |
|---|---|---|
| 1 | Plan document (this file) | in progress |
| 2 | `.codex-plugin/plugin.json` | pending |
| 3 | `hooks/hooks.codex.json` | pending |
| 4 | `bin/adapter/cdx/session-start` (SessionStart shim) | pending |
| 5 | `bin/adapter/cdx/guard-bash-scope` (preToolUse-Bash shim) | pending |
| 6 | `bin/adapter/cdx/track-agent` (postToolUse + stop shim) | pending |
| 7 | `.agents/plugins/marketplace.json` | pending |
| 8 | Manual test in `Projects/Test/codex-apd-test/` | pending |
| 9 | Tag `v4.8.0-alpha.1` on branch | pending |

## Task breakdown

### Task 1 — Scaffold reference plugin (research)
Generate a reference Codex plugin with the official scaffolder and inspect its `hooks.json` to confirm schema.

```bash
python3 "$(codex_skill_path plugin-creator)/scripts/create_basic_plugin.py" \
  apd-reference --path /tmp --with-hooks --with-skills
```

Copy the generated `hooks.json` into this plan as the authoritative schema reference, then discard the scratch plugin.

### Task 2 — `.codex-plugin/plugin.json`
Minimal manifest:
- name: `apd` (or `codex-apd` if `apd` collides)
- version: `4.8.0-alpha.1`
- description: copied from existing `.claude-plugin/plugin.json`
- skills: `./skills/` (reuse existing directory)
- hooks: `./hooks/hooks.codex.json`
- interface: displayName, shortDescription, brandColor, logo (reuse existing `docs/assets/apd-logo.svg` or converted PNG)

### Task 3 — `hooks/hooks.codex.json`
Register 4 Phase 1 events pointing to adapter shims:
- `sessionStart` → `bin/adapter/cdx/session-start`
- `preToolUse` (matcher: Bash) → `bin/adapter/cdx/guard-bash-scope`
- `postToolUse` → `bin/adapter/cdx/track-agent --event postToolUse`
- `stop` → `bin/adapter/cdx/track-agent --event stop`

Exact schema confirmed from Task 1 output.

### Task 4 — Adapter shims (`bin/adapter/cdx/`)

Each shim translates Codex hook stdin JSON into arguments for the runtime-agnostic `bin/core/` scripts. Mirror the pattern used in `bin/adapter/cc/`.

**`session-start`:** Read stdin → extract `cwd`, `source` (startup|clear) → exec `bin/core/session-start`.

**`guard-bash-scope`:** Read stdin → extract `tool_input.command`, `identity.agent_id` → delegate to `bin/core/guard-bash-scope --command "$CMD" --agent-id "$AID"`.

**`track-agent`:** Read stdin → extract `tool_name`, `tool_input`, `hook_event_name` → delegate to `bin/core/track-agent --raw-payload "$JSON"`.

All shims exit with the core script's exit code (block = 2, allow = 0).

### Task 5 — Marketplace registration
`.agents/plugins/marketplace.json` — minimal:
```json
{
  "name": "apd",
  "interface": { "displayName": "APD" },
  "plugins": [{
    "name": "apd",
    "source": { "source": "local", "path": "./" },
    "policy": { "installation": "AVAILABLE", "authentication": "NONE" },
    "category": "Development"
  }]
}
```

### Task 6 — Test project `Projects/Test/codex-apd-test/`

Fresh git repo. Steps:

```bash
mkdir -p ~/Projects/Test/codex-apd-test
cd ~/Projects/Test/codex-apd-test
git init && echo "# codex-apd-test" > README.md && git add . && git commit -m "init"

codex marketplace add /Users/zoranstevovic/Projects/apd-template --ref feature/codex-adapter
# expected: marketplace added, plugin visible

codex -c 'plugins."apd@apd".enabled=true' "Run the APD health check and print version"
# expected: sessionStart hook fires, APD version banner appears, no hook-related errors in ~/.codex/log
```

Smoke-test acceptance:
- [ ] `codex marketplace add` completes without error
- [ ] Plugin appears in `codex marketplace list` (or equivalent)
- [ ] `sessionStart` hook executes and produces output in session log
- [ ] `preToolUse` hook blocks a test bash write outside scope (dummy scope config)
- [ ] `postToolUse` hook logs a tool call to `.apd/agents.log` or equivalent
- [ ] `stop` hook fires and logs session end

### Task 7 — Tag + draft PR
Once manual test passes:
```bash
git tag v4.8.0-alpha.1
git push origin feature/codex-adapter
gh pr create --draft --title "feat: Codex CLI adapter (Phase 1–5 WIP)" \
  --body "Tracks phases 1–5 from project-dual-runtime-codex.md"
```

## Open questions (resolve during implementation)

1. **Plugin name collision** — `apd` may collide with other marketplaces. Fallback: `codex-apd` or `apd-codex`.
2. **Scoping without `preToolUse` Write/Edit support** — Codex's preToolUse only covers Bash. Write/Edit scope enforcement either (a) requires filesystem-level `permissions.<profile>` (Phase 2) or (b) stays CC-only in Phase 1 with documented known gap.
3. **`resolve-project.sh` adaptation** — currently reads `CLAUDE_PLUGIN_ROOT`. Needs to accept `CODEX_PLUGIN_ROOT` as peer. Minimal change: `APD_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-$fallback}}"`.
4. **SKILL.md frontmatter compatibility** — APD skills use `effort` field (CC-specific?). Verify Codex tolerates unknown frontmatter keys.

## Exit criteria

Phase 1 is done when:
- All smoke-test checkboxes in Task 6 pass
- Tag `v4.8.0-alpha.1` pushed
- Draft PR opened with Phase 1–5 checklist
- Any blocking gaps documented as follow-up tasks for Phase 2

Total estimated scope: ~400 LOC across shims + manifests + 1 config shim in `resolve-project.sh`. One focused session.

---

## 2026-04-18 POC findings (addendum)

**Status after first scaffolding session:** Manifest, hooks.codex.json, and `guard-bash-scope` adapter shim committed on `feature/codex-adapter`. End-to-end smoke test **blocked**.

### What worked

- `.codex-plugin/plugin.json` parsed by Codex 0.121.0 without manifest warnings
- Plugin cache layout confirmed: `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/` (requires version subdir — flat structure rejected)
- Hook schema extracted from `codex app-server generate-ts`: 5 events (`preToolUse`, `postToolUse`, `sessionStart`, `userPromptSubmit`, `stop`), config uses PascalCase matchers, schema matches CC pattern
- `codex marketplace add <local-dir>` registers marketplace in `~/.codex/config.toml` under `[marketplaces.<name>]`
- `codex features enable codex_hooks` activates the hook subsystem (confirmed `CodexHooks` in runtime feature list)

### Blocking discovery

**Hooks do not fire in `codex exec` non-interactive mode.** Verified via:
- Hook probe script wired into `SessionStart` and `PreToolUse` hooks
- Plugin loaded cleanly (no manifest warnings at any log level)
- `RUST_LOG=trace` output contains zero hook-loading or hook-firing entries
- Probe log file never written after multiple runs

Likely root cause: `codex_hooks` is still under-development in 0.121.0, and hook execution is only wired into TUI / app-server code paths, not `codex exec`. This is a Codex limitation, not an APD bug.

### Distribution adjustment

`.agents/plugins/marketplace.json` removed from the repo — the committed structure pointed `path: "./"` which Codex rejects (needs `./plugins/<name>/` subdir). APD can't be its own marketplace root without restructuring. End-user distribution plan:

- **Git-based (target for end users):** `codex marketplace add zstevovich/claude-apd --ref feature/codex-adapter`
- **Local dev testing:** create scratch marketplace dir with symlinked plugin, e.g. `/tmp/apd-marketplace/plugins/apd -> /path/to/apd-template`

### Revised Phase 1 exit gate

Replace original Task 6 smoke-test criteria with:

- [ ] User manually verifies `SessionStart` hook fires in Codex TUI interactive mode (probe script writes to log)
- [ ] User manually verifies `PreToolUse` Bash hook fires in TUI (probe script captures command)
- [ ] If both pass: proceed with Task 7 (tag `v4.8.0-alpha.1`)
- [ ] If either fails: open issue against Codex; pivot Phase 2 plan — possibly switch APD enforcement surface from hooks to MCP server (`codex mcp-server`)

### Memory written during POC

- `feedback-codex-hooks-exec-mode-blocked.md` — this blocker, what was tested, what's next
- `reference-codex-hook-schema.md` — authoritative hook event names + hooks.json format from TS schema
- `project-codex-plugin-structure-verified.md` — plugin layout corrections vs earlier research assumptions
