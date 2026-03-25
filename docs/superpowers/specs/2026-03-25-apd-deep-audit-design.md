# APD Template Deep Audit — Nalaze i Preporuke

## Spec kartica

```
## APD Deep Audit
Cilj: Identifikovati propuste u APD template-u pre prve produkcijske upotrebe.
Effort: max
Van scope-a: Implementacija fix-ova (to je sledeći korak — plan).
Acceptance kriterijumi:
  - Svi mehanički guardovi testirani adversarial metodom
  - Svaki propust kategorizovan (KRITIČAN / VISOK / SREDNJI)
  - Svaki propust ima predlog fix-a sa effort procenom
  - Snage dokumentovane za referentno poređenje
Pogođeni moduli: .claude/scripts/, .claude/rules/, .claude/settings.json, CLAUDE.md
Rizici: Lažno osećanje sigurnosti ako audit nije dovoljno temeljit.
Rollback: N/A (audit je read-only, ne menja kod).
Human gate: N/A
ADR: N/A
```

## Kontekst

APD template je AI coding workflow za Claude Code okruženje. Template pruža:
- Tri-slojni defense-in-depth (kognitivni, mehanički, verifikacioni)
- Pipeline: Spec → Builder → Reviewer → Verifier → Commit
- Agent izolacija putem scope guard-a
- Session memory za akumulaciju znanja

Audit je rađen pre prve produkcijske upotrebe. Cilj: uhvatiti propuste pre nego što postanu problemi na pravom projektu.

## Metodologija

1. **Eksploracija** — kompletna analiza svih 25 fajlova u template-u (paralelni agenti)
2. **Adversarial testovi** — 22 testa na guard-git.sh i guard-scope.sh sa edge case-ovima
3. **Arhitekturna analiza** — provera tri sloja zaštite i pipeline enforce-menta

---

## KRITIČNI propusti

### K1. Bash bypass za file scope — agent može pisati van svog domena

**Opis:** Guard-scope.sh hvata samo `Write` i `Edit` tool-ove (matcher: `"Write|Edit"`). Builder agent može koristiti Bash tool da piše fajlove van scope-a:

```bash
echo "malicious code" > apps/web/App.tsx     # PROLAZI — guard-git ne proverava scope
cat > apps/web/hack.ts << 'EOF'              # PROLAZI
content
EOF
```

**Dokaz:** Adversarial test — `echo "content" > file_outside_scope` → EXIT 0.

**Uticaj:** Ceo scope isolation sistem za agente je zaobiđen jednom echo komandom. Agent koji hallucinira može pisati bilo gde u projektu.

**Predlog fix-a:** Registrovati guard-scope.sh i na `Bash` matcher u agent TEMPLATE.md hookovima. Guard-scope.sh treba proširiti da parsira Bash komande i detektuje redirekcije (`>`, `>>`, `tee`) na putanje van scope-a.

**Effort:** Srednji — zahteva proširenje guard-scope.sh sa Bash parsing logikom.

**Alternativni fix (lakši):** U agent TEMPLATE.md dodati eksplicitan Bash guard koji blokira write redirekcije. Novi guard-bash-scope.sh koji iz tool_input.command izvlači redirekcione target-e.

---

### K2. Verify-all.sh je prazan — Verifier faza je dekoracija

**Opis:** Sve build/test komande su zakomentarisane. Guard-git.sh poziva verify-all.sh pre svakog autorizovanog commita, ali skripta uvek vraća exit 0.

**Dokaz:**
```
→ Pokretanje verifikacije pre commit-a...
→ Backend promene detektovane...
  (KONFIGURIŠI build/test komande u verify-all.sh)
Verifikacija prošla       ← UVEK prođe
```

**Uticaj:** Pipeline kaže Spec → Builder → Reviewer → Verifier → Commit, ali Verifier ne verifikuje ništa. Iluzija sigurnosti bez upozorenja.

**Predlog fix-a:** Dodati failsafe na kraj verify-all.sh — detektovati da nijedna komanda nije otkomentarisana i ispisati glasno upozorenje:

```bash
# Na početku skripte, flag koji se setuje kad se izvrši bar jedna provera
CHECKS_RAN=0

# Svaka otkomentarisana komanda setuje: CHECKS_RAN=1

# Na kraju:
if [ "$CHECKS_RAN" -eq 0 ]; then
    echo "⚠ UPOZORENJE: verify-all.sh nema konfiguriranih provera!" >&2
    echo "  Konfiguriši build/test komande pre produkcijskog rada." >&2
    # NE blokiraj (exit 0) — ali upozorenje je vidljivo u outputu
fi
```

**Effort:** Nizak — 10 linija koda.

---

### K3. `git push --force` prolazi sa prefiksom

**Opis:** Guard-git.sh proverava samo da li push ima APD_ORCHESTRATOR_COMMIT=1 prefiks. `--force` / `-f` flag nije posebno tretiran.

**Dokaz:**
```bash
echo '{"tool_input":{"command":"APD_ORCHESTRATOR_COMMIT=1 git push --force origin main"}}' | bash guard-git.sh
# EXIT 0 — PROŠLO
```

**Uticaj:** Force push prepisuje remote istoriju. Nema rollback-a bez server-side reflog-a.

**Predlog fix-a:** U git push sekciju guard-git.sh dodati:

```bash
if echo "$NORMALIZED_GIT" | grep -qE "git push.*(-f([[:space:]]|$)|--force([[:space:]]|$)|--force-with-lease([[:space:]]|$))"; then
    echo "BLOKIRANO: git push --force nije dozvoljen. Koristi regularni push." >&2
    exit 2
fi
```

**Effort:** Nizak — 4 linije koda.

---

### K4. Reviewer korak nema mehaničku zaštitu

**Opis:** Workflow.md kaže: *"NIKADA ne preskakati Reviewer korak"*. Ali ovo je samo kognitivno pravilo. Nema hook-a koji sprečava commit ako Reviewer nije pokrenut.

**Uticaj:** Pod pritiskom (dugi kontekst, složen task), orkestrator može "zaboraviti" Reviewer korak. Ovo je upravo scenario koji APD treba da spreči.

**Predlog fix-a (pragmatičan):** Dodati u guard-git.sh upozorenje pre svakog autorizovanog commita:

```bash
echo "⚠ PODSETNIK: Da li je Reviewer korak završen?" >&2
echo "  Pipeline: Spec → Builder → Reviewer → Verifier → Commit" >&2
```

Ovo ne blokira (orkestrator odlučuje), ali primorava na svesnu odluku.

**Predlog fix-a (strožiji):** Checkpoint fajl sistem:
- Reviewer piše `.claude/memory/.last-review-timestamp`
- Guard-git.sh proverava da je timestamp noviji od poslednje Builder promene
- Ako nije → BLOKADA sa porukom "Reviewer nije pokrenut posle poslednje promene"

**Effort:** Pragmatičan = Nizak (2 linije). Strožiji = Visok (novi mehanizam).

---

## VISOKI propusti

### V1. `git branch -d` je lažni pozitiv

**Opis:** Regex `branch[[:space:]]+-[Dd]` hvata i `-d` (safe delete, briše samo merged grane) i `-D` (force delete).

**Dokaz:** `git branch -d feature/test` → BLOKIRANO.

**Uticaj:** Orkestrator ne može obrisati merged feature grane posle merge-a.

**Fix:** Promeniti regex sa `-[Dd]` na samo `-D`:

```bash
# Trenutno (linija 106):
branch[[:space:]]+-[Dd]
# Novo:
branch[[:space:]]+-D
```

**Effort:** Nizak — promena jednog karaktera.

---

### V2. `git checkout -- file` prolazi

**Opis:** Guard hvata `git checkout .` i `git checkout *` ali ne specifične fajlove sa `--` flagom.

**Dokaz:** `git checkout -- src/index.ts` → EXIT 0.

**Uticaj:** Agent može odbaciti uncommitted promene na pojedinačnim fajlovima.

**Fix:** Proširiti regex da blokira `checkout` sa `--` flagom:

```bash
checkout[[:space:]]+(--[[:space:]]+)
```

**Napomena:** `git checkout branch-name` (switch) mora ostati dozvoljen. Fix treba da cilja samo `--` pattern.

**Effort:** Nizak.

---

### V3. `git tag -d` nije pokriveno

**Opis:** Brisanje tagova nije u listi destruktivnih operacija.

**Dokaz:** `git tag -d v1.0` → EXIT 0.

**Fix:** Dodati `tag[[:space:]]+-d` u destruktivni regex na liniji 106.

**Effort:** Nizak.

---

### V4. Nerazrešeni placeholder-i — tihi kvar hook-ova

**Opis:** settings.json sadrži `[APSOLUTNA_PUTANJA]` i `[PROJECT_NAME]`. Ako setup.sh nije pokrenut, svi hook-ovi pucaju jer Bash pokušava pokrenuti nepostojeću putanju — i tiho pada.

**Dokaz:** `bash [APSOLUTNA_PUTANJA]/.claude/scripts/guard-git.sh` → bash error, ali hook sistem tretira to kao "prošao" (ne blokira).

**Uticaj:** Misliš da su guardovi aktivni, ali ništa ne radi. Nulta zaštita bez indikacije.

**Fix:** session-start.sh na startu proverava placeholder-e:

```bash
if grep -q '\[APSOLUTNA_PUTANJA\]' "$PROJECT_DIR/.claude/settings.json" 2>/dev/null; then
    echo "⚠ KRITIČNO: settings.json sadrži nerazrešene placeholder-e!" >&2
    echo "  Pokreni: bash .claude/scripts/setup.sh" >&2
fi
```

**Effort:** Nizak — 4 linije.

---

### V5. Nema zaštite od čitanja osetljivih fajlova

**Opis:** Nijedan guard ne sprečava agenta da čita `.env`, `credentials.json`, `*.pem`, `*.key` fajlove.

**Dokaz:** `cat .env` → EXIT 0.

**Uticaj:** Agent može pročitati secrets i uključiti ih u output. Ako output završi u log-u ili commit poruci — leak.

**Fix:** Novi guard-secrets.sh koji blokira čitanje osetljivih pattern-a:

```bash
SENSITIVE_PATTERNS='(\.(env|pem|key|p12|pfx)$|credential|secret|password|\.ssh/)'
```

Registrovati na `Bash` matcher u agent hookovima (ne globalno — orkestrator treba da može).

**Effort:** Srednji — nova skripta + registracija u agent template.

---

## SREDNJI propusti

### S1. `git rebase --abort` i `git merge --abort` prolaze

Dozvoljeni su. Uglavnom korisni, ali agent ih može zloupotrebiti. Niskoprioritetno.

### S2. Nema primera popunjene spec kartice

`docs/plans/TEMPLATE.md` postoji, ali nema `SPEC-EXAMPLE.md` sa popunjenim primerom. Dodati primer bi skratio vreme prvog korišćenja.

### S3. Cross-layer tabela tipova je prazna

Workflow.md sekcija 7 ima praznu tabelu. Bez nje cross-layer verifikacija nema šta da proveri.

### S4. Session-log.md nema primer zapisa

Prazan fajl sa komentarom. Jedan primer zapis bi pomogao orkestratoru da isprati format.

### S5. apd-init.md je 580 linija — kognitivno opterećenje

Skill je prevelik za jednu sesiju. Razbijanje na 2-3 manja skill-a bi pomoglo.

---

## Snage template-a

| Komponenta | Ocena | Komentar |
|------------|-------|----------|
| guard-git.sh normalizacija | ★★★★★ | Env var stripping, git opcije, JSON parsing — robustan |
| guard-scope.sh izolacija | ★★★★★ | Trailing slash, prefix kolizija, van-projekta detekcija |
| APD Hard Rules u CLAUDE.md | ★★★★★ | `##` nivo otporan na kompresiju — pametan dizajn |
| ADR framework | ★★★★★ | Template, indeks, integracija u workflow — kompletno |
| Attribution `""` u settings | ★★★★★ | Elegantan način za sprečavanje Co-Authored-By |
| Tri režima apd-init | ★★★★ | Fresh/Merge/Update pokrivaju sve scenarije |
| Session memory arhitektura | ★★★★ | Dva sistema jasno razgraničena |
| README dokumentacija | ★★★★★ | 380 linija, detaljan, sa tabelama i primerima |
| Tri-slojni defense-in-depth | ★★★★ | Koncept odličan, implementacija ima rupe (K1-K4) |

---

## Rezime adversarial testova

**guard-git.sh:** 18 testova — 14 prolazi, 3 propusta (K1, K3, V2), 1 lažni pozitiv (V1)
**guard-scope.sh:** 4 testa — 4/4 savršen

## Preporučeni redosled fix-ova

| Red | Fix | Effort | Razlog prioriteta |
|-----|-----|--------|-------------------|
| 1 | K3: Blokada force push | Nizak | 4 linije, sprečava katastrofalni gubitak |
| 2 | K2: Verify-all.sh failsafe | Nizak | 10 linija, uklanja iluziju sigurnosti |
| 3 | V1: branch -d lažni pozitiv | Nizak | 1 karakter, deblokira normalan workflow |
| 4 | V4: Placeholder detekcija | Nizak | 4 linije, sprečava tihi kvar hook-ova |
| 5 | V3: tag -d blokada | Nizak | 1 regex dodatak |
| 6 | V2: checkout -- blokada | Nizak | Regex proširenje |
| 7 | K4: Reviewer podsetnik | Nizak | 2 linije upozorenja pre commita |
| 8 | K1: Bash scope bypass | Srednji | Nova logika u guard-scope.sh |
| 9 | V5: guard-secrets.sh | Srednji | Nova skripta |

**Ukupni effort za fix-ove 1-7:** ~30 linija koda.
**Ukupni effort za fix-ove 8-9:** Nova skripta logika + testiranje.

---

## Napomene iz spec review-a (advisory)

1. **K1 — prihvaćeni rizik:** Bash parsing za redirekcije je inherentno fragilno (subshell-ovi, eval, heredoc-ovi). Ni jedan pristup ne može biti sveobuhvatan. Plan treba eksplicitno dokumentovati koji bypass vektori ostaju kao prihvaćeni rizik.

2. **V2 — regex preciznost:** Predloženi fix za `checkout --` treba anchor na kraju da ne hvata lažne pozitive. Plan treba specificirati tačne test case-ove za regex.

3. **Prioritizacija K1 vs K3:** K1 (Bash scope bypass) je najteži propust iako je osmi po redosledu fix-a. Razlog: K3 (force push) se fixa sa 4 linije, a K1 zahteva novu logiku. Ali plan treba jasno naznačiti da je K1 najširi threat — halluciniraući agent može pisati bilo gde.
