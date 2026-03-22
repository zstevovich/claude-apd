# Agent Pipeline Development (APD) — Workflow

## HARD GATE — BEZ IZUZETAKA

**Svaka implementacija MORA proći sve tri role: Builder → Reviewer → Verifier → tek onda commit.**

- NIKADA ne preskakati Reviewer korak, bez obzira na veličinu ili "jednostavnost" promene
- NIKADA ne grupisati više faza bez review-a između svake
- Brzina NIJE izgovor za preskakanje koraka — preskočen review znači propušteni bagovi koji se vraćaju kao skuplji audit
- Ovo pravilo je APSOLUTNO i neprekršivo

## Napomena: Rules vs Skills

- **Rules** (`.claude/rules/`) — globalna pravila, učitavaju se UVEK za sve agente
- **Skills** (`.claude/skills/`) — snippet-ovi i procedure, učitavaju se EKSPLICITNO kad agent treba konvencije

## 1. Spec kartica pre koda (5-10 min)

Pre SVAKOG taska (bez obzira na veličinu) kreirati mini-spec:

```
## [Naziv taska]
**Cilj:** Jedna rečenica.
**Effort:** max | high (pogledaj sekciju 8)
**Van scope-a:** Šta NE radimo.
**Acceptance kriterijumi:** Lista uslova za "gotovo".
**Pogođeni moduli:** Fajlovi/slojevi koji se menjaju.
**Rizici:** Šta može poći po zlu.
**Rollback:** Kako vratiti ako pukne.
**Human gate:** Da li zahteva odobrenje (API promene, migracije, auth, prod data).
```

Spec se deli sa korisnikom PRE implementacije. Korisnik odobrava ili koriguje.

## 2. Tri role agenata

### Builder
- Implementira kod prema spec-u
- Custom agenti u `.claude/agents/` — jedan per domen
- Max 3-4 edit operacije po dispatch-u
- Jasno vlasništvo nad fajlovima — bez preklapanja između agenata

### Reviewer
- Samo nalazi rizike, bagove, propuste
- NE predlaže stilske promene ili refactoring van scope-a
- Eksplicitno traži: regresije, edge case-ove, security rupe, cross-layer mismatch
- Pokreće se AUTOMATSKI posle svakog Builder-a

### Verifier
- Build + test + contract check
- Pokreće se POSLE Reviewer-a, PRE commit-a
- Koristi `verify-all.sh` skriptu

### Orkestrator (Claude)
- Kreira spec karticu i deli sa korisnikom
- Dispatchuje Builder-e (paralelno gde je moguće)
- Pokreće Reviewer-a posle svake implementacije
- Pokreće Verifier-a pre commitovanja
- Jedini commituje i push-uje
- Jedini komunicira sa korisnikom

## 3. Mikro-zadaci

- Svaki task: jedna funkcionalna promena
- Max 3-4 edit operacije po agentu
- Jedan agent = jasno vlasništvo nad fajlovima (bez preklapanja)
- Ako task zahteva >5 fajlova, razbiti na 2+ agenta

## 4. Verifikacija pre "gotovo"

Minimum pre SVAKOG commit-a:
- [ ] Build prolazi (0 errors)
- [ ] Testovi prolaze (0 failures)
- [ ] Frontend type check prolazi (ako ima frontend promene)
- [ ] Cross-layer contract check (ako task uključuje >1 sloj)
- [ ] Review nalaze primenjene i verifikovane

Minimum pre SVAKOG push-a na staging/production:
- [ ] Sve gore
- [ ] Smoke test na ključnim endpoint-ima
- [ ] Proveriti da svi secrets/env vars postoje u deploy workflow-u
- [ ] Korisnik eksplicitno odobrio push

## 5. Human gate

Korisnik MORA odobriti pre:
- API promene (novi endpointi, promena potpisa)
- Migracije baze (nove tabele, promene kolona)
- Auth/role logika (promene u autorizaciji)
- Deploy na staging/produkciju
- Bilo šta što utiče na produkcijske podatke

Format: orkestrator prikaže diff summary → korisnik kaže "ok" → tek onda akcija.

## 6. Session memory update

Posle SVAKOG završenog taska, orkestrator upisuje zapis u `.claude/memory/session-log.md`.

### Format zapisa

```markdown
## [YYYY-MM-DD] [Naziv taska]
**Status:** Završen | Delimičan | Blokiran
**Šta je urađeno:** [1-2 rečenice — konkretan rezultat]
**Problemi:** [Šta je pošlo po zlu, ili "Bez problema"]
**Guardrail koji je pomogao:** [Koji mehanizam je uhvatio problem, ili "N/A"]
**Novo pravilo:** [Šta dodajemo u workflow, ili "Nema"]
```

### Pravila
- Svaki zapis je **append** na kraj fajla — nikada ne brisati stare zapise
- Maksimum 3 rečenice po polju — kratkost je ključna
- Ako je novo pravilo identifikovano, orkestrator ga ODMAH dodaje u relevantni rules fajl
- Session log se čita na početku sesije (session-start.sh prikazuje poslednjih 20 linija)

## 7. Cross-layer verifikacija

Kad task uključuje backend + frontend/mobile:

| Backend | Frontend (TS) | Mobile (Kotlin) |
|---------|--------------|----------------|
| `string` | `string` | `String` |
| `string?` | `string \| null` | `String?` |
| `Guid` | `string` | `String` |
| `DateTimeOffset` | `string` | `String` (ISO 8601) |
| `int` | `number` | `Int` |
| `bool` | `boolean` | `Boolean` |
| `enum` | union literal | `String` |

Pravilo: NIKADA ne kreirati frontend/mobile tip iz specifikacije — uvek čitaj backend DTO.

## 8. Reasoning effort

Dva nivoa effort-a za agente:

| Effort | Kada | Primeri |
|--------|------|---------|
| **max** | Odluke koje je skupo ispraviti | Planiranje, arhitektura, review, spec kartica, security analiza, API dizajn |
| **high** | Implementacija po jasnom spec-u | Builder kodiranje, testovi, refactoring, bug fix |

### Pravila
- Orkestrator **uvek radi na max** — planira, delegira, reviewuje
- Builder agenti rade na **high** — spec je već definisan, treba ga ispratiti
- Reviewer i Verifier rade na **max** — traže greške koje Builder može propustiti
- Effort se definiše u spec kartici i prosleđuje agentu pri dispatch-u
