---
name: apd-init
description: Inicijalizuj APD okruženje za novi projekat — zameni placeholder-e, kreiraj agente, podesi settings
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

3. **Kreiraj agente iz TEMPLATE.md:**
   - Po jednog za svaki sloj koji korisnik navede
   - Zameni `{{agent-name}}`, `{{SCOPE_PATHS}}`, `{{PROJECT_PATH}}`
   - Postavi model: `sonnet` za Builder-e, `opus` za Guardian-e

4. **Konfiguriši verify-all.sh:**
   - Otkomentiraj relevantne sekcije za stack koji korisnik koristi
   - Postavi build komande

5. **Konfiguriši .mcp.json:**
   - Kopiraj iz `.mcp.json.example`
   - Zameni DB credentials

6. **Učini skripte executable:**
   ```bash
   chmod +x .claude/scripts/*.sh
   ```

7. **Verifikuj setup:**
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
Claude: Koje su putanje? (backend dir, frontend dir)
Korisnik: server/, client/
Claude: Portovi?
Korisnik: 3000 API, 5433 PG, 6380 Redis, 5173 Frontend
Claude: [generiše sve fajlove, kreira agente, podešava hooks]
```

## Posle init-a

- Pokreni `session-start.sh` da verifikuješ da kontekst radi
- Napravi prvi test commit da verifikuješ pipeline
- Dodaj projektno-specifične rules u `.claude/rules/`
- Dodaj skill-ove za konvencije u `.claude/skills/`
