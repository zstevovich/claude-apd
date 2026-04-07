---
name: apd-upgrade
description: Migriraj postojeći APD projekat na novu verziju — backup, update fajlova, verifikacija
effort: max
---

# APD Upgrade

Migrira projekat sa starije verzije APD-a na najnoviju. Podržava:
- **v2.x → v3.0** — migracija sa copy-paste na plugin arhitekturu
- **v3.x → v3.y** — verzija-na-verziju update projektnih fajlova

## Preduslov

APD plugin mora biti instaliran: `npx skills add zstevovich/claude-apd`

## Procedura

### 1. Detektuj trenutnu verziju

```bash
# Pročitaj .apd-version ako postoji
cat .claude/.apd-version 2>/dev/null || echo "v2.x ili starije"
```

### 2. Backup

```bash
cp -r .claude/ .claude-backup-$(date +%Y-%m-%d)/
```

Prikaži korisniku: "Backup kreiran u .claude-backup-{datum}/"

### 3. Migracija po verziji

#### v2.x → v3.0 (copy-paste → plugin)

Ovo je najveća migracija:

1. **Izvuci konfiguraciju iz postojećih fajlova:**
   - Ime projekta: prvi heading iz CLAUDE.md (`# Ime`)
   - Stack: iz CLAUDE.md Stack tabele
   - Agenti: lista iz `.claude/agents/*.md` (osim TEMPLATE.md)
   - Scope-ovi: iz agent hook argumenata (`guard-scope.sh putanja1/ putanja2/`)
   - Portovi: iz CLAUDE.md Portovi tabele
   - Figma/Miro/GitHub URLs: iz CLAUDE.md sekcija

2. **Kreiraj `.apd-config`:**
   ```
   PROJECT_NAME={izvučeno ime}
   APD_VERSION=3.0.0
   STACK={izvučen stack}
   ```

3. **Kreiraj `.apd-version`:** `3.0.0`

4. **Obriši skripte iz projekta** (sada su u plugin-u):
   ```bash
   # Zadrži SAMO verify-all.sh
   for script in guard-git.sh guard-scope.sh guard-bash-scope.sh guard-secrets.sh \
     guard-lockfile.sh guard-permission-denied.sh pipeline-advance.sh pipeline-gate.sh \
     pipeline-post-commit.sh rotate-session-log.sh session-start.sh verify-apd.sh \
     verify-contracts.sh test-hooks.sh gh-sync.sh; do
     rm -f .claude/scripts/$script
   done
   ```

5. **Ažuriraj agent hook putanje:**
   Za svaki `.claude/agents/*.md`:
   - Zameni `{{PROJECT_PATH}}/.claude/scripts/` sa `${CLAUDE_PLUGIN_ROOT}/scripts/`
   - Zameni hardkodirane apsolutne putanje (`/Users/.../scripts/`) sa `${CLAUDE_PLUGIN_ROOT}/scripts/`

6. **Regeneriši settings.json:**
   Sačuvaj samo Notification hook (sa imenom projekta), env i attribution.
   Obriši sve PreToolUse/PostToolUse/SessionStart hook-ove (sada u plugin-u).

7. **Obriši stare fajlove:**
   ```bash
   rm -f .claude/agents/TEMPLATE.md    # Sada u plugin-u
   rm -f .claude/rules/workflow.md      # Sada u plugin-u
   ```

8. **Sačuvaj memory fajlove** — NE DIRAJ:
   - MEMORY.md, status.md, session-log.md, pipeline-skip-log.md

#### v3.x → v3.y (minor update)

1. Pročitaj `.apd-version` i uporedi sa plugin verzijom
2. Ako je ista → "Već si na najnovijoj verziji"
3. Ako je starija → prikaži changelog diff
4. Ažuriraj `.apd-version`
5. Ažuriraj `.apd-config` ako ima novih polja

### 4. Verifikuj

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify-apd.sh
```

### 5. Prikaži rezultat

```
Migracija v2.8 → v3.0 završena:
  ✓ .apd-config kreiran
  ✓ 14 skripti uklonjeno iz projekta (sada u plugin-u)
  ✓ 5 agenata ažurirano (${CLAUDE_PLUGIN_ROOT} putanje)
  ✓ settings.json regenerisan (minimal)
  ✓ Memory fajlovi sačuvani (netaknuti)
  ✓ Backup u .claude-backup-2026-04-07/

  verify-apd.sh: 52 PASS, 0 FAIL

  Obriši backup kad potvrdš da sve radi:
  rm -rf .claude-backup-2026-04-07/
```
