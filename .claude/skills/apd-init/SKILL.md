---
name: apd-init
description: Inicijalizuj APD okruženje za novi projekat — zameni placeholder-e, kreiraj agente, podesi settings
effort: max
---

# APD Init

Pokreni ovaj skill na novom projektu da konfigurišeš APD okruženje.

## Koraci

1. **Prikupi informacije od korisnika:**
   - Ime projekta
   - Apsolutna putanja projekta
   - Stack (backend, frontend, mobile, baza, cache)
   - Direktorijumi za svaki sloj (npr. `src/`, `apps/frontend/`, `apps/mobile/`)
   - Portovi (API, baza, cache, frontend)
   - Autor (ime i email za git)
   - Jezik dokumentacije
   - Agenti koje treba kreirati (po sloju)
   - Figma URL (ako postoji dizajn)
   - Miro board URL (ako postoji board za specifikacije/arhitekturu)
   - GitHub Projects URL (ako koristi GitHub Projects za tracking)

2. **Zameni placeholder-e u svim fajlovima:**
   - `{{PROJECT_NAME}}` → ime projekta
   - `{{PROJECT_PATH}}` → apsolutna putanja
   - `{{LANGUAGE}}` → jezik dokumentacije
   - `{{AUTHOR_NAME}}` → autor
   - `{{BACKEND_STACK}}`, `{{FRONTEND_STACK}}`, `{{MOBILE_STACK}}`, `{{DATABASE}}`
   - `{{PORT_RANGE}}`, `{{API_PORT}}`, `{{DB_PORT}}`, `{{CACHE_PORT}}`, `{{FRONTEND_PORT}}`
   - `{{ARCHITECTURE_PATTERN}}`
   - `{{PROJECT_STRUCTURE}}` → generisano iz `ls`
   - `{{AGENT_TABLE}}` → tabela agenata
   - `{{AGENT_LIST}}` → lista agenata
   - `{{STACK}}` → kratki opis stack-a
   - `{{FIGMA_URL}}` → Figma link ili ukloni Figma sekciju iz CLAUDE.md ako nema dizajn
   - `{{MIRO_BOARD_URL}}` → Miro link ili ukloni Miro sekciju iz CLAUDE.md ako nema board
   - `{{GITHUB_PROJECT_URL}}` → GitHub Projects link ili ukloni GitHub Projects sekciju iz CLAUDE.md ako ne koristi

3. **Auto-detect agenata iz strukture projekta:**

   Pre nego što pitaš korisnika za agente, pročitaj strukturu projekta sa `ls` i predloži agente:

   | Detektovan direktorijum | Predloženi agent | Scope |
   |------------------------|-----------------|-------|
   | `src/` ili `server/` ili `backend/` ili `api/` | backend-builder | detektovan dir |
   | `client/` ili `frontend/` ili `web/` ili `apps/frontend/` | frontend-builder | detektovan dir |
   | `mobile/` ili `apps/mobile/` ili `app/` (sa mobile config) | mobile-builder | detektovan dir |
   | `tests/` ili `__tests__/` ili `test/` ili `src/test/` | testing | detektovan dir |
   | `docker/` ili `.github/` ili `deploy/` ili `infra/` | devops | detektovani dirovi |
   | `src/Commands/` + `src/Queries/` (ili slično) | CQRS agenti (command, query, event) | po odgovornosti |

   **Procedura:**
   1. Pokreni `ls -d */` u root-u projekta
   2. Mapiraj direktorijume na agente po gornjoj tabeli
   3. Prikaži predlog korisniku u tabeli:
      ```
      Detektovana struktura — predloženi agenti:
      
      | Agent | Scope | Izvor |
      |-------|-------|-------|
      | backend-builder | server/ | detektovan server/ dir |
      | frontend-builder | client/ | detektovan client/ dir |
      | testing | server/tests/ client/tests/ | detektovani test dirovi |
      | devops | docker/ .github/ | detektovani infra dirovi |
      
      Odobri, koriguj ili dodaj agente:
      ```
   4. Korisnik odobri ili koriguje (dodaj/ukloni/promeni scope)
   5. Tek posle odobrenja — kreiraj agente

4. **Kreiraj agente iz TEMPLATE.md:**
   - Po jednog za svaki odobreni agent iz koraka 3
   - Zameni `{{agent-name}}`, `{{SCOPE_PATHS}}`, `{{PROJECT_PATH}}`
   - Postavi model: `sonnet` za Builder-e, `opus` za Guardian-e
   - Postavi effort: `high` za Builder-e, `max` za Reviewer/Verifier

5. **Konfiguriši verify-all.sh:**
   - Otkomentiraj relevantne sekcije za stack koji korisnik koristi
   - Postavi build komande

6. **Konfiguriši .mcp.json:**
   - Kopiraj iz `.mcp.json.example`
   - Zameni DB credentials
   - Ako korisnik ima Miro board → dodaj Miro MCP: `claude mcp add --transport http miro https://mcp.miro.com`
   - Napomeni korisniku: za real-time push notifikacije sa boarda pokretati sa `claude --channels miro`

7. **Učini skripte executable:**
   ```bash
   chmod +x .claude/scripts/*.sh
   ```

8. **Verifikuj setup:**
   ```bash
   bash .claude/scripts/pipeline-advance.sh status
   bash .claude/scripts/session-start.sh
   ```

## Primer interakcije

```
Korisnik: /apd-init
Claude: Kako se zove projekat?
Korisnik: MyCRM
Claude: Koji je stack? (backend, frontend, baza)
Korisnik: Node.js + Express, React + Vite, PostgreSQL
Claude: Portovi?
Korisnik: 3000 API, 5433 PG, 6380 Redis, 5173 Frontend
Claude: Imate li Figma dizajn?
Korisnik: Da, https://www.figma.com/design/abc123/MyCRM
Claude: Imate li Miro board za specifikacije/arhitekturu?
Korisnik: Da, https://miro.com/app/board/xyz789
Claude: Koristite li GitHub Projects za tracking?
Korisnik: Da, https://github.com/users/alex/projects/3
Claude: Čitam strukturu projekta...

  Detektovana struktura — predloženi agenti:
  | Agent             | Scope          | Izvor                  |
  | backend-builder   | server/        | detektovan server/ dir |
  | frontend-builder  | client/        | detektovan client/ dir |
  | testing           | tests/         | detektovan tests/ dir  |
  | devops            | docker/ .github/ | detektovani infra dirovi |

  Odobri, koriguj ili dodaj agente:
Korisnik: Ok, dodaj i mobile-builder za mobile/
Claude: [generiše sve fajlove, kreira 5 agenata, podešava hooks, konfiguriše Figma i Miro]
```

## Posle init-a

- Pokreni `session-start.sh` da verifikuješ da kontekst radi
- Napravi prvi test commit da verifikuješ pipeline
- Dodaj projektno-specifične rules u `.claude/rules/`
- Dodaj skill-ove za konvencije u `.claude/skills/`
