---
name: github-projects
description: Upravljaj APD pipeline taskovima kroz GitHub Projects — kreiraj issue za spec, pomeraj kartice kroz kolone, zatvori po završetku
---

# GitHub Projects — APD Pipeline Tracking

Mapira APD pipeline faze na GitHub Projects v2 kolone. Svaki task postaje issue sa spec karticom, a pipeline napredak se reflektuje na boardu.

## Preduslov

- GitHub MCP server konfigurisan u `.mcp.json`
- GitHub Projects v2 kreiran sa kolonama: **Spec**, **In Progress**, **Review**, **Testing**, **Done**
- `gh` CLI autentifikovan (`gh auth login`)

## Mapiranje pipeline → kolone

| APD korak | GitHub Projects kolona | Akcija |
|-----------|----------------------|--------|
| `pipeline-advance.sh spec "Task"` | **Spec** | Kreiraj issue sa spec karticom, dodaj na board |
| `pipeline-advance.sh builder` | **In Progress** | Pomeri issue u In Progress |
| `pipeline-advance.sh reviewer` | **Review** | Pomeri issue u Review |
| `pipeline-advance.sh verifier` | **Testing** | Pomeri issue u Testing |
| Commit (uspešan) | **Done** | Zatvori issue, linkuj commit, pomeri u Done |
| `pipeline-advance.sh skip` | **Done** | Zatvori issue sa `skip` labelom |

## Procedura

### 1. Kreiranje issue-a za novi task (Spec faza)

Kad orkestrator kreira spec karticu, kreiraj i GitHub issue:

```bash
gh issue create \
  --title "[APD] Naziv taska" \
  --body "$(cat <<'EOF'
## Spec kartica

**Cilj:** Jedna rečenica.
**Effort:** max | high
**Van scope-a:** Šta NE radimo.
**Acceptance kriterijumi:**
- [ ] Kriterijum 1
- [ ] Kriterijum 2
**Pogođeni moduli:** fajlovi/slojevi
**Rizici:** šta može poći po zlu
**Rollback:** kako vratiti

---
_APD Pipeline Task — ne zatvaraj ručno_
EOF
)" \
  --label "apd-pipeline" \
  --project "PROJECT_NAME"
```

### 2. Pomeranje kartice kroz kolone

Koristi GitHub MCP server za pomeranje item-a na boardu:

```
Orkestrator: Pomeri issue #42 u kolonu "In Progress" na GitHub Projects boardu.
```

GitHub MCP server podržava `update_project_item` za promenu statusa.

### 3. Zatvaranje issue-a po završetku

Posle uspešnog commita:

```bash
gh issue close ISSUE_NUMBER --comment "Završen kroz APD pipeline. Commit: COMMIT_HASH"
```

### 4. Skip label

Ako je pipeline preskočen (hotfix):

```bash
gh issue close ISSUE_NUMBER --comment "Pipeline preskočen (hotfix): RAZLOG" 
gh issue edit ISSUE_NUMBER --add-label "apd-skip"
```

## Automatizacija

Orkestrator može automatizovati ceo flow:

1. **Na spec** → kreiraj issue + dodaj na board u Spec kolonu
2. **Na svaki `pipeline-advance.sh` korak** → pomeri issue u odgovarajuću kolonu
3. **Na commit** → zatvori issue sa commit referencom
4. **Na skip** → zatvori sa skip labelom

### Primer toka

```
Korisnik: Implementiraj user login
Orkestrator:
  1. Kreira spec karticu
  2. → gh issue create --title "[APD] User login" --project "MyProject"
  3. → pipeline-advance.sh spec "User login"
  4. Dispatches backend-builder
  5. → pomeri issue #42 u "In Progress"
  6. → pipeline-advance.sh builder
  7. Pokreće reviewer
  8. → pomeri issue #42 u "Review"
  9. → pipeline-advance.sh reviewer
  10. Pokreće verifier
  11. → pomeri issue #42 u "Testing"
  12. → pipeline-advance.sh verifier
  13. Commituje
  14. → gh issue close 42 --comment "Commit: abc1234"
  15. → issue se pomera u "Done"
```

## Metrike iz GitHub Projects

GitHub Projects čuva istoriju pomeranja kartica. Ovo omogućava:
- **Cycle time** — koliko dugo issue provede od Spec do Done
- **Bottleneck detekcija** — koja kolona najviše zadržava kartice
- **Throughput** — koliko issue-a se zatvori po danu/nedelji

Ovi podaci su komplementarni sa `pipeline-advance.sh metrics` — GitHub daje board-level pogled, pipeline daje per-step timing.

## Board setup preporuka

Kreiraj GitHub Projects v2 board sa sledećim kolonama:

| Kolona | Opis |
|--------|------|
| **Backlog** | Planirani taskovi (nije u pipeline-u) |
| **Spec** | Spec kartica kreirana, čeka odobrenje |
| **In Progress** | Builder radi |
| **Review** | Reviewer pregleda |
| **Testing** | Verifier testira |
| **Done** | Commitovano i push-ovano |

Labele:
- `apd-pipeline` — svi APD taskovi
- `apd-skip` — taskovi sa preskočenim pipeline-om
- `human-gate` — taskovi koji zahtevaju odobrenje
