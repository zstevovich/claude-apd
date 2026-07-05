# Contributing to APD

Thanks for your interest in APD (Agent Pipeline Development) — a Claude Code plugin for disciplined AI-assisted software development.

## Reporting issues

Use the issue templates. For bug reports, the three fields that matter most are the APD version (`apd version`), the runtime (Claude Code or Codex), and the relevant output — a BLOCK message or lines from `guard-audit.log` (in your project's APD memory directory, `.apd/memory/` or `.claude/memory/`). Without those, most reports cannot be reproduced.

## Before you start

- This is a **framework** repository, not an application. Do not run the APD pipeline on APD itself — the framework detects its own source repo and stays dormant (`APD_FRAMEWORK_SELF`).
- There is no build step. The runtime is bash scripts plus prebuilt Go binaries (`plugins/apd/bin/compiled/` — you generally don't need to touch these).
- `docs/SPEC.md` is the authoritative runtime map. Read it before grepping the internals, and update it in the same commit as any framework change.

## Testing

Every change to scripts must pass the primary E2E suite before you submit:

```bash
bash plugins/apd/bin/core/test-codex-adapter
```

Expect 800+ checks and **0 FAIL**. For a quick static pass there is also `plugins/apd/bin/core/test-hooks`.

Scripts must work on both macOS (BSD userland, bash 3.2) and Linux (GNU). BSD/GNU differences in `grep`, `sed`, and `find` have caused real bugs — test on macOS if you can.

## Conventions

**Scripts**
- Live under `plugins/apd/bin/` (`core/` for pipeline logic, `adapter/cc/` and `adapter/cdx/` for per-runtime glue, `lib/` for shared helpers).
- Every script starts with a comment describing what it does.
- No hardcoded project paths — source `plugins/apd/bin/lib/resolve-project.sh` and use the variables it exports (`PROJECT_DIR`, `APD_PLUGIN_ROOT`, …). Hook paths use `${CLAUDE_PLUGIN_ROOT}`.
- Guard scripts communicate via exit codes: `2` = BLOCK, `0` = ALLOW.

**Skills** — each in its own directory as `skills/<name>/SKILL.md` with YAML frontmatter (`name`, `description`, `effort`). Most Claude Code skills have a Codex mirror under `plugins/apd/skills/` — keep them in sync.

**Templates** — placeholders use the `{{PLACEHOLDER_NAME}}` format and are filled by `/apd-setup`.

**Commits** — short, English, imperative mood ("add X", not "added X"). No AI signatures or watermarks anywhere: not in code, not in docs, not in commit messages.

## Design principle: the enforcement floor is non-negotiable

APD's value is the guaranteed floor, not the average case. Pull requests that loosen or remove guards, gates, or blocking behavior will not be merged on the argument that models "usually behave" — that is an observation about the average, and the floor exists for the rest. If a gate gets in the way of a legitimate workflow, the accepted pattern is an **additive sanctioned path** (a new explicit command or channel, with friction and an audit trail), never a weaker gate.

## Versioning

The maintainer handles version bumps, `CHANGELOG.md`, and tags. Do not bump `plugins/apd/VERSION` or edit the changelog in a PR — describe the change and it will be versioned on merge.

## License

MIT. By contributing you agree that your contributions are licensed under the same terms.
