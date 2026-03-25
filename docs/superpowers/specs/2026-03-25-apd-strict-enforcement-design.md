# APD Strict Enforcement — Design Spec

**Cilj:** Obezbediti striktno poštovanje APD workflow-a tako da orkestrator ne zaboravlja pravila tokom dugih sesija, a agenti ne mogu izaći iz svog scope-a.

**Pristup:** Hibrid — kognitivna zaštita (CLAUDE.md hard rules) + mehanička zaštita (hook skripte).

**Van scope-a:** Runtime agent sandboxing, izolacija fajl sistema na OS nivou, Bash-based file writing bypass (poznato ograničenje — dokumentovano u rizicima).

**Rollback:** `git revert` poslednjeg commit-a. Sve promene su u template fajlovima bez eksternih zavisnosti.

---

## Problem

Tri identifikovana problema:

1. **Orkestrator zaboravlja pravila** — u dugim sesijama context kompresija gubi sadržaj `.claude/rules/` fajlova. Orkestrator onda ne zna commit flag, preskače Reviewer/Verifier faze, ili zaboravlja session memory update.
2. **Orkestrator pogađa commit sintaksu** — svaki put prvo pokuša običan `git commit`, bude blokiran, pa se ispravlja. Poruka greške ne daje tačnu sintaksu.
3. **Agenti izlaze iz scope-a** — ništa ih mehanički ne sprečava da menjaju fajlove van svog domena (npr. backend-builder edituje frontend).

## Rešenja

### 1. Kompresija-otporan CLAUDE.md (Sekcija "APD Hard Rules")

**Šta:** Dodati u CLAUDE.md kompaktnu sekciju (~20 linija) sa kritičnim pravilima koja prežive kompresiju.

**Zašto:** CLAUDE.md je jedini fajl koji je UVEK u kontekstu — nikad se ne kompresuje. Rules fajlovi se učitaju na početku ali mogu ispasti iz konteksta.

**Sadržaj sekcije:**

```markdown
## APD Hard Rules — NE KOMPRESOVATI, NE ZAOBILAZITI

### Commit pravilo
- Svaki git commit MORA koristiti prefix: `APD_ORCHESTRATOR_COMMIT=1 git commit ...`
- Svaki git push MORA koristiti prefix: `APD_ORCHESTRATOR_COMMIT=1 git push ...`
- Bez prefiksa → hook blokira. NE pokušavaj bez njega.

### Pipeline redosled — OBAVEZAN
Spec → Builder → Reviewer → Verifier → Commit
- NIKADA preskočiti Reviewer, čak ni za "trivijalne" promene
- NIKADA commitovati pre nego Verifier prođe

### Agent scope
- Builder agenti menjaju SAMO fajlove u svom domenu
- SAMO orkestrator commituje, push-uje, komunicira sa korisnikom

### Human gate
- API promene, migracije, auth logika, deploy → korisnik MORA odobriti pre akcije

### Session memory
- Posle SVAKOG taska → append u .claude/memory/session-log.md
```

**Pogođeni fajlovi:** `CLAUDE.md`

---

### 2. Ojačan guard-git.sh

**Šta:** Poboljšati poruke greške i zatvoriti dodatne rupe.

**Izmene:**

| Izmena | Razlog |
|--------|--------|
| Bolja poruka pri blokadi commit-a — ispisuje tačnu komandu `APD_ORCHESTRATOR_COMMIT=1 git commit -m "..."` | Orkestrator odmah vidi sintaksu umesto da pogađa |
| Blokada `git add .`, `git add -A`, `git add --all`, `git add -u`, `git add *` | Sprečava slučajno staging svih fajlova — forsira eksplicitno dodavanje po imenu |
| Blokada `git commit -a` / `git commit --all` (bez APD prefiksa) | Sprečava bypass staging kontrole kroz commit -a |
| Blokada `--no-verify` na raw komandi (pre normalizacije) | Sprečava zaobilaženje hook-ova; detektuje bilo gde u komandi |

**Pogođeni fajlovi:** `.claude/scripts/guard-git.sh`

---

### 3. File-scope guard (guard-scope.sh)

**Šta:** Novi hook skript koji blokira agente da menjaju fajlove van svog definisanog domena.

**Kako radi:**

1. Dozvoljene putanje se prosleđuju kao **argumenti skripte** u hook definiciji svakog agenta:
   ```yaml
   hooks:
     PreToolUse:
       - matcher: "Write|Edit"
         hooks:
           - type: command
             command: "bash [APSOLUTNA_PUTANJA]/.claude/scripts/guard-scope.sh src/ tests/"
             timeout: 5
   ```
   Ovo rešava problem identiteta agenta — skript ne mora znati koji agent ga poziva jer su dozvoljene putanje prosleđene eksplicitno.

2. Skript čita tool input JSON sa stdin-a i extrahuje `file_path`:
   ```json
   // Write tool input: { "tool_input": { "file_path": "/abs/path/to/file", "content": "..." } }
   // Edit tool input:  { "tool_input": { "file_path": "/abs/path/to/file", "old_string": "...", "new_string": "..." } }
   ```

3. Skript konvertuje apsolutnu putanju u relativnu (u odnosu na PROJECT_DIR), pa proverava da li počinje sa jednim od dozvoljenih prefiksa.

4. Ako putanja nije dozvoljena:
   ```
   BLOKIRANO: Fajl apps/frontend/App.tsx je van dozvoljenog scope-a.
   Dozvoljene putanje: src/, tests/
   ```

5. **guard-scope.sh hook-ovi se definišu SAMO u agent `.md` fajlovima, NIKADA u `settings.json`.** Ovo osigurava da orkestrator zadrži pun pristup svim fajlovima.

**Ograničenje:** Ne pokriva Bash pisanje fajlova (`echo > file`). Ovo je poznato ograničenje — Bash hook već štiti git operacije, a Write/Edit su primarni alati za pisanje fajlova.

**Pogođeni fajlovi:** `.claude/scripts/guard-scope.sh` (novi), `.claude/agents/TEMPLATE.md`, `.claude/agents/EXAMPLE-backend-builder.md`

---

### 4. Integracione izmene

**setup.sh:**
- Dodati zamenu `[APSOLUTNA_PUTANJA]` u agent fajlovima koji referenciraju guard-scope.sh (već pokriveno postojećom logikom za agent fajlove)
- Nema novih interaktivnih koraka

**Agent TEMPLATE.md:**
- Dodati `Write|Edit` hook matcher sa guard-scope.sh i placeholder putanjama
- Ažurirati ZABRANJENO sekciju
- Dodati komentar koji objašnjava da se dozvoljene putanje prosleđuju kao argumenti

**EXAMPLE-backend-builder.md:**
- Dodati konkretan primer sa `src/` i `tests/` kao argumentima guard-scope.sh
- Dodati Write|Edit hook

**settings.json:**
- Bez promena — guard-scope se NE dodaje ovde (samo u agent fajlovima)
- Guard-git ostaje globalan (za orkestratora i agente)

**Pogođeni fajlovi:** `.claude/scripts/setup.sh`, `.claude/agents/TEMPLATE.md`, `.claude/agents/EXAMPLE-backend-builder.md`

---

## Kompletna lista pogođenih fajlova

| Fajl | Akcija |
|------|--------|
| `CLAUDE.md` | Modify — dodati APD Hard Rules sekciju |
| `.claude/scripts/guard-git.sh` | Modify — bolje poruke, blokada add ./--no-verify/commit -a |
| `.claude/scripts/guard-scope.sh` | Create — file-scope guard za agente |
| `.claude/scripts/setup.sh` | Modify — podrška za guard-scope.sh putanje (minimalna, postojeća logika pokriva) |
| `.claude/agents/TEMPLATE.md` | Modify — Write/Edit hook sa guard-scope.sh |
| `.claude/agents/EXAMPLE-backend-builder.md` | Modify — konkretan primer sa scope argumentima |
| `.claude/settings.json` | Bez promena — guard-scope namerno isključen (orkestrator zadrži pun pristup) |

## Rizici

| Rizik | Mitigacija |
|-------|-----------|
| guard-scope.sh pogrešno blokira legitimne operacije | Dozvoljene putanje su argumenti po agentu — lako se prošire |
| CLAUDE.md postaje predugačak | Hard Rules sekcija je ~20 linija — minimalan overhead |
| Bash pisanje fajlova zaobilazi scope guard | Poznato ograničenje; guard-git pokriva Bash git operacije; dokumentovano |
| `git add *` zaobiđe glob blokadu | Blokira se regex-om koji pokriva `git add` sa wildcard i dot patternima |

## Acceptance kriterijumi

- [ ] Orkestrator koristi commit flag iz prvog pokušaja (ne pokušava bez njega)
  - **Verifikacija:** CLAUDE.md sadrži Hard Rules sekciju sa eksplicitnom commit sintaksom
- [ ] `git add .`, `git add -A`, `git add --all`, `git add -u` su blokirani sa jasnom porukom
  - **Verifikacija:** `echo '{"tool_input":{"command":"git add ."}}' | bash .claude/scripts/guard-git.sh` → BLOKIRANO
- [ ] `--no-verify` je blokiran bilo gde u komandi
  - **Verifikacija:** `echo '{"tool_input":{"command":"git commit --no-verify -m test"}}' | bash .claude/scripts/guard-git.sh` → BLOKIRANO
- [ ] `git commit -a` bez APD prefiksa je blokiran
  - **Verifikacija:** `echo '{"tool_input":{"command":"git commit -a -m test"}}' | bash .claude/scripts/guard-git.sh` → BLOKIRANO
- [ ] Agent ne može editovati fajl van svog dozvoljenog scope-a
  - **Verifikacija:** `echo '{"tool_input":{"file_path":"/project/apps/frontend/X.tsx"}}' | bash .claude/scripts/guard-scope.sh src/ tests/` → BLOKIRANO
- [ ] Guard-scope poruka jasno kaže koji fajl je blokiran i koje putanje su dozvoljene
- [ ] Setup.sh zamenjuje putanje u svim agent fajlovima (uključujući guard-scope.sh reference)
- [ ] APD Hard Rules sekcija postoji u CLAUDE.md i pokriva: commit flag, pipeline redosled, agent scope, human gate, session memory
