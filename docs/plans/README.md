# Implementation plans — archival

Dated planning documents that drove past releases. They reflect the world at time of writing and are **not updated** as the framework evolves.

When reading these, assume any concrete value (maxTurns, file paths under `.claude/.pipeline/` → now `.apd/pipeline/`, config field names, exit codes) may have changed. Authoritative sources for current behavior:

- **`CHANGELOG.md`** — every functional change since v3.0.
- **`templates/`** — current agent / reviewer frontmatter (maxTurns, model, effort).
- **`bin/core/` source** — the actual enforcement and pipeline logic.
- **`rules/workflow.md`** — the current APD workflow.

Specifically, readers of the April 2026 planning docs should note:

- `.claude/.pipeline/` was relocated to `.apd/pipeline/` in v4.3.4.
- `maxTurns: 15` (reviewers) and `maxTurns: 20` (builders) bumped to 30 / 40 in v4.7.13.
- `/apd-upgrade` was removed; `/apd-setup` is the single entry point.
