---
name: apd-profile
description: Switch the model/effort profile of the project's APD pipeline agents — the economy vs quality dial. Use when the user asks to change agent models, switch to a cheaper or stronger profile, mentions "burn", "cruise", "eco", "model profile", "prebaci profil", "jaci/jeftiniji modeli", or before a launch-critical task (burn) / batch of small fixes (eco). Presents available profiles, applies the chosen one to .claude/agents frontmatter, then runs /reload-plugins so the new models take effect in the current session.
effort: low
allowed-tools: Bash AskUserQuestion SlashCommand
---

# APD Model Profile

Economy vs quality dial for pipeline agents. A profile maps role classes to a
(model, effort) pair: `default` (builders — context-heavy, carry the tier) and
`adversarial` (positional value — fresh context matters more than model tier,
so it may sit one tier below builders, never meaningfully above them).

Profiles are data, not code: defaults ship in the plugin
(`templates/model-profiles.conf`); a project may override the whole table via
`.apd/model-profiles.conf`. CC-only — Codex `.toml` agents are not touched.

## When to use

- User asks to change agent models, make the pipeline cheaper or stronger, or
  names a profile (burn / cruise / eco).
- Before a launch-critical feature → suggest `burn`.
- Before a batch of small pre-scoped fixes / Lean tasks → suggest `eco`.

## When to skip

- Mid-pipeline (active spec-card) — the script refuses; finish or reset first.
- User wants a one-off model change for a single agent — that is a manual
  frontmatter edit, not a profile (but warn that `apd profile status` will
  flag it as drift afterwards).

## Steps

1. Show current state:

   ```bash
   bash .claude/bin/apd profile status
   ```

2. Show available profiles and what each maps to:

   ```bash
   bash .claude/bin/apd profile list
   ```

3. Ask the user which profile to apply (AskUserQuestion with the profiles as
   options, current one marked). Briefly state the trade-off: `burn` =
   maximum quality / maximum cost, `cruise` = strong daily default, `eco` =
   cheapest, for small well-scoped work.

4. Apply:

   ```bash
   bash .claude/bin/apd profile <name>
   ```

   The script rewrites `model:` + `effort:` in `.claude/agents/*.md`
   (adversarial-reviewer gets the `adversarial` row, `apd-verify-*` reserved
   names are never touched), records `MODEL_PROFILE=<name>` in the APD config,
   and writes an INFO entry to guard-audit.log.

5. **Tell the USER to run `/reload-plugins` — you cannot.** `/reload-plugins`
   is an interactive slash command; only the user can run it (the orchestrator
   has no way to). The running session keeps the old models until agent
   definitions are reloaded — `/reload-plugins` is sufficient (verified live),
   a full session restart also works. Do not claim the change is live before one
   of the two happened.

6. **APD now blocks subagent dispatch until the reload happens (drift guard).**
   When `apd profile` changes agents it drops a `.apd/.pending-reload` marker;
   the SubagentStart guard hard-blocks any dispatch while it stands — so a
   forgotten reload surfaces as a clear block, not a silent stale-model run.
   After the user runs `/reload-plugins`, clear it with **`apd reload-done`**
   (or just restart — a fresh session clears the marker automatically).

## Exit criteria

- Profile applied (script reported "applied: N changed") and `/reload-plugins`
  was run (or the user was told to restart the session).
- Or: script refused (active pipeline / unknown profile) and you relayed the
  reason verbatim instead of working around it.

## Anti-patterns

| Don't | Do |
|---|---|
| Hand-edit `model:` across agents to "switch profile" | Run `apd profile <name>` — config + audit trail stay consistent |
| Switch profiles while a pipeline task is active | Finish (commit) or reset first — mid-run swap pollutes the run's model attribution |
| Claim the new models are active immediately after apply | The USER runs `/reload-plugins` (you can't) — only then are the new models live |
| Dispatch agents right after apply, assuming it worked | APD blocks dispatch until reload (drift guard); user runs `/reload-plugins` + `apd reload-done`, or restarts |
| Invent profile names or model IDs | Only offer what `apd profile list` prints; new mappings belong in model-profiles.conf |
