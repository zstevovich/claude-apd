---
name: apd-upgrade
description: Migrate an existing APD project to a new version — backup, update files, verify
effort: max
---

# APD Upgrade

Migrates a project from an older APD version to the latest. Supports:
- **v2.x → v3.0** — migration from copy-paste to plugin architecture
- **v3.x → v3.y** — version-to-version update of project files

## Prerequisite

APD plugin must be installed: `/plugin marketplace add zstevovich/claude-apd` then `/plugin install claude-apd@zstevovich-plugins`

## Procedure

### 1. Detect current version

```bash
# Read .apd-version if it exists
cat .claude/.apd-version 2>/dev/null || echo "v2.x or older"
```

### 2. Backup

```bash
cp -r .claude/ .claude-backup-$(date +%Y-%m-%d)/
```

Show to the user: "Backup created in .claude-backup-{date}/"

### 3. Migration by version

#### v2.x → v3.0 (copy-paste → plugin)

This is the largest migration:

1. **Extract configuration from existing files:**
   - Project name: first heading from CLAUDE.md (`# Name`)
   - Stack: from CLAUDE.md Stack table
   - Agents: list from `.claude/agents/*.md` (except TEMPLATE.md)
   - Scopes: from agent hook arguments (`guard-scope.sh path1/ path2/`)
   - Ports: from CLAUDE.md Ports table
   - Figma/Miro/GitHub URLs: from CLAUDE.md sections

2. **Create `.apd-config`:**
   ```
   PROJECT_NAME={extracted name}
   APD_VERSION=3.2.1
   STACK={extracted stack}
   ```

3. **Create `.apd-version`:** `3.2.1`

4. **Delete scripts from the project** (now in the plugin):
   ```bash
   # Keep ONLY verify-all.sh
   for script in guard-git.sh guard-scope.sh guard-bash-scope.sh guard-secrets.sh \
     guard-lockfile.sh guard-permission-denied.sh pipeline-advance.sh pipeline-gate.sh \
     pipeline-post-commit.sh rotate-session-log.sh session-start.sh verify-apd.sh \
     verify-contracts.sh test-hooks.sh gh-sync.sh; do
     rm -f .claude/scripts/$script
   done
   ```

5. **Update agent hook paths:**
   For each `.claude/agents/*.md`:
   - Replace `{{PROJECT_PATH}}/.claude/scripts/` with `${CLAUDE_PLUGIN_ROOT}/scripts/`
   - Replace hardcoded absolute paths (`/Users/.../scripts/`) with `${CLAUDE_PLUGIN_ROOT}/scripts/`

6. **Regenerate settings.json:**
   Keep only the Notification hook (with project name), env and attribution.
   Delete all PreToolUse/PostToolUse/SessionStart hooks (now in the plugin).

7. **Delete old files:**
   ```bash
   rm -f .claude/agents/TEMPLATE.md    # Now in the plugin
   cp "${CLAUDE_PLUGIN_ROOT}/rules/workflow.md" .claude/rules/workflow.md  # Refresh from plugin (rules are NOT auto-loaded from plugins)
   ```

8. **Preserve memory files** — DO NOT TOUCH:
   - MEMORY.md, status.md, session-log.md, pipeline-skip-log.md

#### v3.x → v3.y (minor update)

1. Read `.apd-version` and compare with plugin version
2. If the same → "You are already on the latest version"
3. If older → show changelog diff
4. Update `.apd-version`
5. Update `.apd-config` if there are new fields

### 4. Verify

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify-apd.sh
```

### 5. Show result

```
Migration v2.8 → v3.0 complete:
  ✓ .apd-config created
  ✓ 14 scripts removed from the project (now in the plugin)
  ✓ 5 agents updated (${CLAUDE_PLUGIN_ROOT} paths)
  ✓ settings.json regenerated (minimal)
  ✓ Memory files preserved (untouched)
  ✓ Backup in .claude-backup-{YYYY-MM-DD}/

  verify-apd.sh: 52 PASS, 0 FAIL

  Delete backup once you confirm everything works:
  rm -rf .claude-backup-{YYYY-MM-DD}/
```
