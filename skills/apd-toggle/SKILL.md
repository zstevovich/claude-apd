---
name: apd-toggle
description: Toggle claude-apd@zstevovich-plugins enabled state in CC settings without leaving the session. Use when the user asks to disable APD, turn it off, enable it, switch APD on/off, or hit a guard block they want to bypass intentionally for non-APD work. Defaults to flipping current state; explicit on/off arg sets directly. Smart-detection picks the right settings file (settings.local.json → settings.json → ~/.claude/settings.json) so the toggle actually affects what CC sees. After the JSON edit, runs /reload-plugins to apply in the active session.
effort: low
allowed-tools: Bash SlashCommand
---

# APD Toggle

Quick switch for the claude-apd plugin's `enabledPlugins` state in CC settings. CC-only — Codex has no equivalent concept.

## When to use

- User asks: "turn off APD", "iskljuci APD", "disable apd", "enable apd", "switch APD off", "ugasi APD u ovoj sesiji", "vrati APD nazad", or any phrasing requesting plugin toggle.
- User wants to do quick non-APD work in a project that has APD enabled, without leaving the session.
- User wants to enable APD in a project where it's currently off.
- User asks "kako da ugasim APD" — answer with this skill, not with manual JSON edit instructions.

## When NOT to use

- User wants to UNINSTALL the plugin entirely (use `/plugin uninstall` directly — different operation).
- User is on Codex — no `enabledPlugins` concept exists, this skill does nothing useful there.
- User wants to disable a different plugin (e.g. superpowers) — this skill is APD-specific.

## Process

### Step 1 — Parse intent

User intent → flag:

| User said | Flag |
|---|---|
| "turn off", "disable", "iskljuci", "ugasi" | `off` |
| "turn on", "enable", "ukljuci", "vrati" | `on` |
| "toggle", "flip", "switch", or unspecified | (no arg — flip current state) |

If user mentioned `--global` / `globalno` / "user-wide", append `--global`. Same for `--project` (tracked) and `--local` (gitignored). Default is smart-detection (no flag).

### Step 2 — Run the toggle

```bash
bash .claude/bin/apd toggle [on|off] [--global|--project|--local]
```

The script prints:
- Old value → new value
- Which settings file was edited
- Detection rationale (smart-detection note, if applied)

### Step 3 — Reload plugins in-session

After the JSON edit succeeds, invoke `/reload-plugins` via the SlashCommand tool. This applies the change without requiring CC restart.

If the user explicitly asked you NOT to reload (e.g., "edit but don't reload"), skip this step and tell them to run `/reload-plugins` manually when ready.

### Step 4 — Report

One concise line confirming the new state. If toggled OFF, mention briefly that pipeline gates / guards / skills are now inert until re-enabled.

## Anti-patterns

| Don't | Do |
|---|---|
| Manually edit settings.json with Edit/Write tool | Always go through `apd toggle` — it handles smart-detection, file creation, JSON safety via jq |
| Toggle and forget to reload | Always run `/reload-plugins` after the edit unless user explicitly opted out |
| Assume settings.local.json is the only place — write blindly | Trust the script's smart-detection; it knows where the active value lives |
| Report success without showing the new state | Always include the old → new transition + which file was edited |

## Exit criteria

- The toggle script ran successfully (exit 0).
- The user knows the new state (on/off).
- The user knows which file was edited (settings.local.json is most common).
- `/reload-plugins` was invoked (unless user opted out).
