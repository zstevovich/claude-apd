---
name: apd-audit
description: Use when verifying that APD is correctly configured on Codex in the current project — qualitative deep audit of agents under .apd/agents/, AGENTS.md, MCP server registration, .codex/hooks.json, and pipeline health. Goes deeper than apd:apd_doctor. Triggers on "audit APD", "review setup", "is APD configured", "verify framework", "check APD", "APD health", "is everything wired", after any major framework upgrade or version bump.
---

# APD Project Audit (Codex)

> Qualitative review of how APD is configured in the project — content quality,
> not just file existence. Pairs with `apd:apd_doctor()` MCP tool (mechanical checks).

## When to use / When to skip

**Use when:**
- First session after `apd cdx init` — confirm everything is correct
- After manually editing `.apd/agents/`, `AGENTS.md`, or `.codex/config.toml`
- When the pipeline behaves unexpectedly
- When `apd:apd_doctor()` passes but something "feels off"
- Before handing the project to another developer

**Skip when:**
- `apd:apd_doctor()` itself is failing — fix those mechanical issues first
- You only need a yes/no health check — `apd:apd_doctor()` is faster
- Mid-pipeline — audit is for between cycles, not during

## What This Checks (apd:apd_doctor Does NOT)

| apd:apd_doctor | apd-audit |
|---|---|
| Files exist? | Content correct and complete? |
| TOML valid? | Hook config actually wires to live scripts? |
| Agents have scope? | Scope paths match the project layout? |
| Pipeline runs? | Pipeline output matches the expected format? |
| Mechanical ✓/✗ | Qualitative review |

## Process

### 1. Run apd:apd_doctor first

```
apd:apd_doctor()
```

If it reports errors → fix those first. This skill builds on top of
`apd:apd_doctor`, not replaces it.

### 2. Agent quality

For each agent in `.apd/agents/*.md`:

**Roles that must EXIST** — check presence before quality:
- `code-reviewer` — missing → the reviewer advance BLOCKs
- `adversarial-reviewer` — missing → the reviewer advance BLOCKs (`adversarial-agent-missing`).
  Until v7.0 its absence silently disabled the whole adversarial layer, so a project that
  has been running "clean" without this file was running without the layer. On Codex that
  layer is the ONLY independent review the pipeline has — supervision is inert here.

**Frontmatter check:**
- `scope:` list — paths actually exist in the repo? A writable role with no scope in either
  the YAML key or the `guard-scope` hook command fails CLOSED at `apd:apd_guard_write` (v6.37)
- `model:` (if present) — the gpt-* namespace. `MODEL_PROFILE` is CC-only and **inert under
  Codex**, so a Claude model name in a Codex project's config is never applied — `apd doctor`
  warns about exactly this
- `effort:` (if present) — builders `xhigh`, reviewers `max`
- `memory:` — `none` on `adversarial-reviewer` (decontextualization contract); flagging it
  for a missing `memory: project` inverts what makes the role worth dispatching

**Body check:**
- Has a FORBIDDEN section with commit prohibition for builders
- Has a workflow description matching the role
- Scope paths match `apd:apd_guard_write` arguments used elsewhere

### 3. AGENTS.md quality

Check that `AGENTS.md` has all required sections:
- `## Stack` — technology table
- `## APD` — orchestrator role description
- `### Pipeline` — enforced pipeline reference
- `### Guardrails` — guard list
- `### Mandatory skills` — the table must name **`apd-pipeline-guide`** (mandatory before
  every task since v6.15, hard-gated by `.guide-marker`); brainstorm is advisory, not the gate
- `### Human gate` — approval requirements

Check that `AGENTS.md` does NOT contain:
- `{{PLACEHOLDER}}` unreplaced values
- References to old skill names
- `.claude/` paths (that's CC; Codex uses `.apd/`)

### 4. MCP registration

Verify `.codex/config.toml` has:
- `[mcp_servers.apd]` block with `command = "bash"` and `args` pointing at the version-agnostic `.codex/bin/apd-mcp` launcher (v6.35 — NO pinned `cwd`; the launcher resolves the current plugin cache at runtime so the config survives a plugin upgrade). A pinned `cwd = ".../apd/<version>"` is a pre-v6.35 install → run `apd cdx init` to migrate.
- All 10 `[mcp_servers.apd.tools.<name>]` blocks (one per APD MCP tool — `_APD_TOOLS` in `install-codex-config` is the authority; the count grew with `apd_pipeline_metrics` in v6.2 and `apd_prepare_dispatch` in v6.36)
- Approval modes are appropriate for the project's risk profile

Run `apd:apd_ping()` to confirm the MCP server actually answers.

### 5. Hooks

Verify `.codex/hooks.json` has:
- `PreToolUse` Bash matcher → `bin/adapter/cdx/guard-bash-scope`
- a second `PreToolUse` Bash hook → `bin/adapter/cdx/guard-bash-portability` (macOS/BSD vs Linux command forms; wired by `apd cdx init` alongside the scope guard — `apd doctor` does not check this one, so the audit must)
- `PreToolUse` `apply_patch|Edit|Write` matcher → `bin/adapter/cdx/guard-file-edit`
- `SessionStart` → `bin/adapter/cdx/session-start`
- No stale paths from previous APD versions

### 6. Pipeline health

```
apd:apd_pipeline_state()
```

- Returns without error
- `next_step` reflects actual state on disk (`.apd/pipeline/`)
- No phantom locks

### 7. Memory files

Check `.apd/memory/`:
- `MEMORY.md` — not empty, has project context
- `status.md` — has current phase
- `session-log.md` — exists (may be empty for new projects)
- No `[fill in]` placeholders blocking the next task

### 8. Drift detection (v6.10+)

Invoke the drift script via Bash hook or shell:

```bash
bash ${APD_PLUGIN_ROOT}/bin/core/pipeline-audit-drift
```

(Path resolution: `$APD_PLUGIN_ROOT` is the plugin's `plugins/apd/` directory; resolved automatically by `resolve-project.sh` which the script sources.)

**Four dimensions — and what they mean on Codex.** Dimensions A, C and D read CC files (`.claude/settings.json`, `.claude/rules/workflow.md`, `CLAUDE.md`). On a **pure-Codex** project those files do not exist and the script skips them silently — only dimension B applies there, and the Codex-side equivalents (`AGENTS.md`, `.codex/hooks.json`, `.codex/config.toml`) are covered by sections 3–5 of this audit, not by the script. On a hybrid CC+Codex project all four run.

1. **A — `.claude/settings.json` deny patterns** — compares against the current framework baseline (8 mkdir patterns: 4 slash-prefixed + 4 bare-dir). Pre-v6.10 re-inits left projects with only 4 patterns. CC file; skipped on pure-Codex.
2. **B — `APD_VERSION`** (`.claude/.apd-config`, or `.apd/config` on pure-Codex) — compares against the currently loaded plugin version. Stale value (minor/major lag) means stale workflow/agent templates. The one dimension that always applies.
3. **C — `.claude/rules/workflow.md` content** — five guidance markers (`Implements:`, `rationale gate`, `unconditional`, `apd-pipeline-guide`, `SUPERVISION`), then a byte comparison against the shipped copy when every marker is present (v7.0.3). If this list and the script disagree, the script is the authority. CC file; skipped on pure-Codex. **v7.1.6 — record-aware:** `apd-init` records the shipped copy the project took in `.apd/.workflow.md.shipped` and merges framework changes into the project's copy with `git merge-file` (local edits kept; a conflict leaves the copy untouched and init says so at session start). With the record present, dim C distinguishes two IMPORTANT findings: the framework's file changed since the record (the merge has not happened, or conflicted), and a copy that differs while the record equals the shipped file (local edits, or an older text put back — the record cannot tell them apart; byte-equality stays the contract, init keeps local edits through its merge but does not sanction them). Without the record (set up before v7.1.6) the byte comparison stands and the finding names the missing record — `/apd-setup` step 5c creates it. The marker list is one file, `bin/lib/workflow-markers.sh`, read by init and this script.
4. **D — feature claim drift** (v6.12.3+) — scans workflow.md and CLAUDE.md for orchestrator confabulation: any line mentioning BOTH a contracts command (`verify-contracts`/`apd contracts`) AND an unsupported language (PHP/Python/Java/Go/Ruby/Kotlin/Rust). Festico apd-setup 2026-05-28 generated a false "verify-contracts checks PHP automatically" claim; the framework supports TS ↔ C# only. CC files; skipped on pure-Codex.

Output buckets: CRITICAL / IMPORTANT (most common) / INFO / CLEAN. Recovery actions point to re-run of `apd cdx init` (Codex) or `/apd-setup` (CC); v6.10+ python merge fix writes all 8 deny patterns.

Exit code 1 on any IMPORTANT or CRITICAL finding; 0 on INFO-only or CLEAN.

## Output Format

```
APD Project Audit — {project name}

CRITICAL:
  1. [file:line] Description

IMPORTANT:
  1. [file:line] Description

CLEAN:
  ✓ Agents (X builder + 1 reviewer)
  ✓ AGENTS.md sections complete
  ✓ MCP registered + apd:apd_ping responds
  ✓ Hooks wired
  ✓ Pipeline healthy
  ✓ Memory files present

Result: X findings (Y critical, Z important)
```

## Common rationalizations

| Excuse | Reality |
|--------|---------|
| "apd:apd_doctor passes so it's fine" | apd:apd_doctor checks structure, not content quality |
| "Agents work, no need to audit" | Wrong scope or missing FORBIDDEN section wastes review cycles |
| "AGENTS.md looks ok" | Missing sections mean orchestrator skips important rules |
| "I'll fix it when it breaks" | Broken pipeline produces broken code silently |

## Examples

**Example 1 — Builder agent scope drifted from layout.**

*Input:* `.apd/agents/backend-api.md` lists `scope: src/api/**` but the project moved everything to `services/api/**`. `apd:apd_doctor()` passed (file exists, parses); every `apd:apd_guard_write` call rejects builder writes.

*Output:*
```
CRITICAL:
  1. [.apd/agents/backend-api.md:3] Scope path src/api/** does not exist
     Effect: apd:apd_guard_write rejects every builder write — pipeline cannot ship
     Fix: update to `scope: services/api/**` (or run `apd cdx init` to regenerate)
```

**Example 2 — Stale `.claude/` reference in AGENTS.md.**

*Input:* `AGENTS.md` Pipeline section references `.claude/bin/apd pipeline status`. The project is Codex-only — `.claude/` does not exist.

*Output:*
```
IMPORTANT:
  1. [AGENTS.md:97] References .claude/bin/apd — Codex uses .apd/
     Effect: orchestrator follows a non-existent path, falls back to manual workflow
     Fix: replace `.claude/bin/apd pipeline` with `apd:apd_pipeline_state()` (MCP tool)
```

**Example 3 — Missing per-tool approval block.**

*Input:* `.codex/config.toml` has `[mcp_servers.apd]` plus 9 of 10 `[mcp_servers.apd.tools.*]` blocks. `apd:apd_advance_pipeline` block is missing. Codex prompts "Allow tool" on every pipeline transition.

*Output:*
```
IMPORTANT:
  1. [.codex/config.toml] Missing approval block for apd:apd_advance_pipeline
     Effect: Codex prompts the user on every pipeline transition
     Fix: re-run `apd cdx init` to rewrite all 10 per-tool blocks idempotently
```

## Exit criteria

You're done when:
- Every agent under `.apd/agents/` has been opened and frontmatter checked
- Every required section in `AGENTS.md` is present and free of unreplaced `{{PLACEHOLDER}}` values
- `.codex/config.toml` has the `[mcp_servers.apd]` block plus 10 per-tool approval blocks
- `apd:apd_ping()` returns a valid response
- `apd:apd_pipeline_state()` runs without error
- Findings are sorted into CRITICAL / IMPORTANT / CLEAN buckets in the output format
- If any CRITICAL is reported, the user has been told what to fix and in what order

## Hand-off

- After audit completes with CRITICAL findings → invoke `apd cdx init` (CLI, outside Codex) to regenerate missing pieces
- After audit completes clean → continue with normal development
- If audit reveals a structural finding not covered by `apd cdx init` → escalate to user with concrete file:line references
