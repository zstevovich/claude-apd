---
name: apd-audit
description: Use when changes have been made to the APD framework itself and you need to verify quality, consistency, and correctness before release. Qualitative audit beyond what verify-apd.sh checks mechanically.
effort: max
allowed-tools: Read Glob Grep Bash
disable-model-invocation: true
---

# APD Framework Audit

## The Iron Law

```
NO RELEASE WITHOUT A CLEAN AUDIT FIRST
```

If the audit finds issues, fix them before bumping version or pushing.

## When to Use

- After significant changes to scripts, skills, hooks, or templates
- Before version bump or release tag
- After refactoring (renames, moves, deletions)
- When something "feels off" but verify-apd.sh passes

## What This Skill Checks (verify-apd.sh Does NOT)

verify-apd.sh checks a PROJECT's APD installation mechanically. This skill checks the FRAMEWORK itself qualitatively:

| verify-apd.sh | /apd-audit |
|---|---|
| Files exist? | Content consistent? |
| JSON valid? | `if` patterns correct? |
| Pipeline works? | Versions aligned? |
| Agents have model? | Stale references? |
| Mechanical ✓/✗ | Qualitative review |

## Process

Dispatch **parallel audit agents** for each category, then consolidate findings.

### Category 1: Version Consistency

Check that ALL version references match the current version in `plugin.json`:

```bash
# Get current version
CURRENT=$(grep '"version"' .claude-plugin/plugin.json | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

# Check all locations
grep -rn "$CURRENT" .claude-plugin/plugin.json       # must match
grep -rn "$CURRENT" .claude-plugin/marketplace.json   # must match
grep -rn "$CURRENT" scripts/apd-init.sh               # 3 occurrences
grep -rn "$CURRENT" skills/apd-setup/SKILL.md          # 2 occurrences
```

Also check README.md heading and CLAUDE.md Versioning section (these are often stale).

### Category 2: Stale References

Grep the entire codebase for references to things that no longer exist:

```bash
# Removed skills
grep -rn '/apd-upgrade' --include='*.md' --include='*.sh' --include='*.json' | grep -v CHANGELOG
grep -rn '/apd-init' --include='*.md' --include='*.sh' --include='*.json' | grep -v CHANGELOG | grep -v 'apd-init\.sh'

# Non-existent scripts
grep -rn 'apd-pipeline' --include='*.md' --include='*.sh' | grep -v 'apd-pipeline.*label'

# Removed markers
grep -rn 'MARK_NEXT\|◆' scripts/ --include='*.sh'

# Old counter variables
grep -rn '\$PASS[^_]' scripts/ --include='*.sh' | grep -v PASS_COUNT

# Box drawing in scripts (should be removed)
grep -rn '╭\|╮\|╰\|╯\|╔\|╗\|╚\|╝' scripts/ --include='*.sh'

# "coming soon" for shipped features
grep -rn 'coming soon' README.md
```

### Category 3: Hook Correctness

```bash
# Validate hooks.json
python3 -c "import json; json.load(open('hooks/hooks.json'))"

# Check if field is inside hook objects (not matcher groups)
# The `if` must be a sibling of `type` and `command`, not of `matcher`
```

Read `hooks/hooks.json` and verify:
- Every `if` field is inside the `hooks[]` array objects, NOT at the matcher-group level
- No `if` patterns contain env var prefixes (`APD_ORCHESTRATOR_COMMIT=1`)
- All referenced scripts exist in `scripts/`

Check agent templates (`templates/agent-template.md`, `templates/reviewer-template.md`):
- Same `if` placement rule applies in YAML hooks

### Category 4: Script Quality

```bash
# Inline color definitions (should only be in style.sh)
grep -rn "033\[38;5\|033\[32m\|033\[33m\|033\[31m" scripts/ --include='*.sh' | grep -v 'lib/style.sh'

# `local` keyword outside functions
# Check each script — local is only valid inside function bodies

# Scripts that should source style.sh but don't
# (scripts with visual output: pipeline-advance, pipeline-gate, session-start, apd-init, verify-apd, verify-contracts, test-hooks, track-agent)
```

### Category 5: Skill Quality

For each skill in `skills/*/SKILL.md`:
- Description starts with "Use when" (CSO format)
- Has frontmatter fields: name, description, effort
- No references to non-existent scripts or skills
- Script paths use `${CLAUDE_PLUGIN_ROOT}/scripts/` (not relative paths)

### Category 6: Documentation Accuracy

- README.md version matches plugin.json
- README skills directory listing matches actual `skills/` contents
- GETTING-STARTED.md references `/apd-setup` (not `/apd-init`)
- CHANGELOG has entries for current version
- No "coming soon" for shipped features

### Category 7: Template Integrity

- `templates/CLAUDE.md.reference` — references `/apd-setup`, has mandatory skills table
- `templates/agent-template.md` — has `color` field, `if` inside hook objects
- `templates/reviewer-template.md` — has `color: orange`, `if` inside hook objects
- `templates/principles/en.md` and `sr.md` — correct gitignore policy
- `rules/workflow.md` — uses `pipeline-advance.sh`, has step 9 (finish), has mandatory skills section

## Execution

1. **Run all category checks** — dispatch parallel agents or run inline
2. **Consolidate findings** — group by severity (Critical / Important / Minor)
3. **Present to user** — table with file:line references
4. **Fix all Critical and Important** issues before proceeding
5. **Re-run affected categories** after fixes to verify

## Output Format

```
APD Framework Audit — v{version}

CRITICAL (must fix):
  1. [file:line] Description

IMPORTANT (should fix):
  1. [file:line] Description

MINOR (nice to have):
  1. [file:line] Description

CLEAN:
  ✓ Version consistency
  ✓ Hook correctness
  ✓ Script quality
  ...

Result: X issues found (Y critical, Z important)
```

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "verify-apd.sh passes so it's fine" | verify-apd.sh checks PROJECT setup, not FRAMEWORK quality |
| "It's just a version mismatch" | Version mismatches confuse users and break upgrade detection |
| "The stale reference doesn't hurt" | Stale references mislead agents and waste debugging time |
| "I'll fix the docs later" | Docs are the first thing users read. Wrong docs = wrong setup |
| "Only one file is affected" | One file affects every project that uses the template |

## Integration

- **Called by:** Developer after framework changes, before version bump
- **Pairs with:** `verify-apd.sh` (mechanical project audit)
- **Leads to:** Fix → re-audit → version bump → release tag
