# Stall-watch — structural stall detection + notification

## Problem
CC subagent dispatches hit **stream stalls** (model emits zero bytes for 15–47 min; CC's own byte-watchdog recovery is broken upstream — GitHub #49716/#39755, subagent-abort not planned #61405). The pipeline hangs and the user waits blind. There is no in-CC fix; the only lever is a human pressing `Esc` on the stalled dispatch. So: **detect the stall externally, alert the user, let them recover in one keystroke.** (Distinct from the memory-Edit permission hang — that's the separate `**/.claude/memory/**` apd-init fix.)

## Goal
A first-class, cross-platform APD feature that, while a pipeline runs, watches for a stalled subagent and fires a desktop notification whose **click focuses that project's VS Code window**. Visible in the CLI status line. Auto-managed by the pipeline — the user does nothing.

## Design (locked)
- **Detection:** watch the newest subagent transcript on disk (`~/.claude/projects/<slug>/*/subagents/agent-<id>.jsonl`); a **zero-byte gap ≥ threshold (default 150s) while the agent is still running** = stall. "Finished/not-blocking" (suppress false alarm) = last event `stop_reason=end_turn` **or** a STOP in `.agents` **or** the session's MAIN transcript is newer than the subagent (orchestrator moved on).
- **Notification (cross-platform):** macOS → `terminal-notifier` (accepted dependency); Linux → `notify-send`. Title carries the project name. **Click → runs `code <project-path>`** → VS Code focuses that project's own window (handles full-screen/virtual-desktops itself; no fragile window-hunting). Re-ping every 30s while still stalled ("STILL stalled").
- **Lifecycle (automatic):** launched by `pipeline-advance spec` (pipeline start), detached; **default ON, opt-out via config**; self-exits when `spec-card.md` is gone (commit/reset), plus a defensive cap for an orphaned session. Dup-guard: one watcher per project.
- **Status line:** model (a) — the watcher writes its state to a file; APD exposes `apd stall-status` which prints an indicator (`⚠ STALL: backend-work 3m` when firing, quiet `👁 2` while watching, empty otherwise). The user adds it to **their own** statusLine in one line. APD never clobbers the user's statusLine.

## Components
1. **`plugins/apd/bin/stall-watch`** (new) — the per-project watcher. Ported+hardened from the prototype: mtime detection, the 3 finished-signals, notify layer with OS dispatch + click→`code`, state-file write, self-exit on spec-card-gone + orphan cap, PID-file dup-guard, macOS/Linux guards.
2. **`plugins/apd/bin/core/pipeline-advance`** (edit) — `spec` case launches the watcher detached when enabled + platform supported + deps present; degrades to bell-only (still detects, no rich notify) if the notifier binary is missing. Never writes to CC stdout (log to file).
3. **`apd stall-status`** (new dispatch + small reader) — scans the per-project state files (`~/.claude/run/stall/*.state`), prints one indicator line. Fast, read-only, safe to call from a status line every render.
4. **Config flag** — `STALL_WATCH=on|off` in `.apd/config` (default `on`). `pipeline-advance` respects it.
5. **`apd-init` / apd-doctor** — dependency check: warn + point to `brew install terminal-notifier` (macOS) / distro `notify-send` (Linux) if absent; feature still runs degraded.
6. **Tests** — `test-codex-adapter` section: watcher exists+exec, launch wired in `spec` case behind the flag, `stall-status` prints from a state file, OS guards present, config opt-out honored.
7. **Docs** — SPEC.md (CLI + lifecycle + state-file rows), CHANGELOG, README/GETTING-STARTED note + the one-line statusLine snippet.

## State file
`~/.claude/run/stall/<slug>.state` per active watcher: `project|status(watching|stalled)|agent|since_ts`. Watcher creates on launch, updates on state change, removes on exit. `apd stall-status` aggregates across all of them.

## Cross-platform notes
- macOS: `terminal-notifier -title … -message … -execute "code <path>"` (click runs the command).
- Linux: `notify-send` click-to-run needs an action listener (`notify-send --wait --action`, or `gio`/`dunstify`) — **impl detail to resolve during build**; fallback = notification without click-action + bell.

## Non-goals
- Not catching main-loop stalls or permission hangs (separate concern; permission hang fixed via apd-init memory rules).
- Not a general OS process monitor — only APD pipeline subagent transcripts.

## Rollout
Feature ships via bump/test/marketplace. Default ON with opt-out. apd-setup/doctor surfaces the dependency + the statusLine snippet. Supersedes the personal `~/.claude/scripts/stall-watch`/`stall-supervisor` prototypes (to be removed once shipped).
