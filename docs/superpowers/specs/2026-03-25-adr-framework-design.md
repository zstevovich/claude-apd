# ADR Framework za APD Template — Design Spec

**Cilj:** Uvesti Architecture Decision Records (ADR) framework u APD template tako da arhitekturne odluke budu dokumentovane sa punim kontekstom (zašto, koje alternative, posledice), integrisane u APD workflow, i povezane sa principles.md.
**Effort:** high
**Van scope-a:** Automatska detekcija arhitekturnih odluka (orkestrator predlaže, ne forsira). Migracija postojećih pravila iz principles.md u ADR format (to je zadatak korisnika per-projekat).
**Pogođeni moduli:** `docs/adr/`, `.claude/rules/workflow.md`, `.claude/rules/principles.md`, `CLAUDE.md`, `README.md`
**Human gate:** Ne (template fajlovi, nema API/migracija/auth promena)
**Rollback:** `git revert` poslednjeg commit-a. Sve promene su u template fajlovima.

**Pristup:** Hibrid — ADR kao standalone dokumenti u `docs/adr/` + integracija u APD workflow kroz opciono `ADR:` polje u spec kartici.

---

## Problem

Trenutno `principles.md` sadrži statička pravila (**šta**), ali ne dokumentuje:
- **Zašto** je odluka doneta
- Koje **alternative** su razmatrane
- U kom **kontekstu** je odluka validna
- Šta se menja ako se kontekst promeni

Bez ovog konteksta, pravila postaju dogme koje niko ne sme dovesti u pitanje jer niko ne zna zašto postoje. ADR rešava ovaj problem dajući svakoj arhitekturnoj odluci potpun zapis.

## Rešenja

### 1. ADR Template i struktura

**Lokacija:** `docs/adr/` direktorijum

**Imenovanje:** Numerisani fajlovi: `NNNN-kratak-opis.md` (npr. `0001-izbor-baze-podataka.md`). Numeracija počinje od 0001, uvek 4 cifre sa vodećim nulama.

**Template format:**

```markdown
# ADR-NNNN: [Naslov odluke]

**Status:** Predložen | Prihvaćen | Zamenjen | Povučen
**Datum:** YYYY-MM-DD
**Zamenjuje:** ADR-XXXX (ako postoji)
**Zamenjen sa:** ADR-YYYY (dodaje se naknadno)

## Kontekst

[Zašto se ova odluka donosi? Koji problem rešavamo? Koja su ograničenja?]

## Razmatrane opcije

### Opcija A: [Naziv]
- **Pro:** [...]
- **Con:** [...]

### Opcija B: [Naziv]
- **Pro:** [...]
- **Con:** [...]

## Odluka

[Šta smo odlučili i zašto.]

## Posledice

- **Pozitivne:** [Šta dobijamo]
- **Negativne:** [Šta gubimo, trade-off-ovi]
- **Rizici:** [Šta može poći po zlu]
```

**Životni ciklus:**

```
Predložen → Prihvaćen (korisnik odobri) → [opciono] Zamenjen (novi ADR supersede-uje)
                                         → [opciono] Povučen (odluka više nije relevantna)
```

- `Predložen` ADR se može menjati dok nije prihvaćen
- Odbijen ADR dobija status `Povučen`
- `Prihvaćen` ADR je **immutable** — ako se odluka promeni, kreira se novi ADR koji zamenjuje stari (stari dobija `Zamenjen sa:` link)

**Ključne osobine:**
- **Immutable posle prihvatanja** — ne menja se, novi ADR zamenjuje starog
- **Numerisan** — sekvencijalni brojevi daju hronološki pregled odluka
- **Kompaktan** — max 1 stranica; kontekst i odluka su najbitniji

**Pogođeni fajlovi:** `docs/adr/TEMPLATE.md` (novi), `docs/adr/README.md` (novi — ADR indeks)

---

### 2. Integracija u APD workflow

**Spec kartica** dobija opciono polje `ADR:`:

```markdown
## [Naziv taska]
**Cilj:** ...
**ADR:** ADR-0003
```

Moguće vrednosti za `ADR:` polje:

- `ADR-NNNN` — referencira postojeći ADR (npr. `ADR-0003`)
- `Potreban` — orkestrator predlaže kreiranje novog ADR-a pre implementacije
- `N/A` — task nema arhitekturnu težinu (default za većinu taskova)

**Kada orkestrator predlaže ADR:**
- Uvođenje nove tehnologije ili biblioteke
- Promena API dizajna ili komunikacionog paterna
- Izbor između dva validna arhitekturna pristupa
- Promena auth/security strategije
- Migracija podataka ili promena šeme

**Kada ADR NIJE potreban:**
- Bug fix-ovi
- Dodavanje endpointa po postojećem patternu
- Refactoring bez promene interfejsa
- UI promene unutar postojećeg design sistema

**Tok:**
1. Orkestrator kreira spec karticu
2. Ako prepozna arhitekturnu odluku → predlaže korisniku: "Ovo uvodi arhitekturnu odluku. Kreiram ADR?"
3. Korisnik odobri → orkestrator kreira ADR pre nego što dispatch-uje Builder-a
4. ADR se commituje zajedno sa spec-om
5. Builder vidi ADR referencu u spec kartici i može ga pročitati za kontekst

**Ovo se ne forsira** — orkestrator predlaže, korisnik odlučuje. Nema automatskog blokiranja ako ADR ne postoji.

**Pogođeni fajlovi:** `.claude/rules/workflow.md` (dodati ADR polje u spec karticu i objašnjenje)

---

### 3. ADR indeks i veza sa principles.md

**ADR indeks** — `docs/adr/README.md`:

```markdown
# Architecture Decision Records

| # | Naslov | Status | Datum |
|---|--------|--------|-------|
```

Orkestrator ažurira indeks kad kreira novi ADR.

**Veza sa principles.md** — pravila koja proizilaze iz ADR odluka dobijaju referencu:

```markdown
## Kod
- Error handling: Result pattern (vidi ADR-0004)
- Arhitekturni pattern: Vertical Slice (vidi ADR-0001)
```

Ovo rešava ključni problem: `principles.md` kaže **šta**, ADR kaže **zašto**.

**CLAUDE.md** — dodaje se kratak blok:

```markdown
### ADR (Architecture Decision Records)
- Arhitekturne odluke se dokumentuju u `docs/adr/`
- Immutable: kad se odluka promeni, novi ADR zamenjuje stari
- Spec kartica referencira ADR ako task uključuje arhitekturnu odluku
```

**Pogođeni fajlovi:** `CLAUDE.md` (dodati ADR sekciju), `.claude/rules/principles.md` (dodati primer ADR referenci), `docs/adr/README.md` (novi)

---

## Agent dekompozicija

Spec utiče na 6 fajlova (>5 prag iz workflow.md), pa se deli na 2 taska:

- **Task 1 (Effort: high):** `docs/adr/TEMPLATE.md`, `docs/adr/README.md` (kreiranje novih fajlova)
- **Task 2 (Effort: high):** `.claude/rules/workflow.md`, `.claude/rules/principles.md`, `CLAUDE.md`, `README.md` (modifikacije postojećih)

---

## Kompletna lista pogođenih fajlova

| Fajl | Akcija |
|------|--------|
| `docs/adr/TEMPLATE.md` | Create — ADR template |
| `docs/adr/README.md` | Create — ADR indeks |
| `.claude/rules/workflow.md` | Modify — dodati ADR polje u spec karticu |
| `.claude/rules/principles.md` | Modify — dodati primer ADR referenci |
| `CLAUDE.md` | Modify — dodati ADR sekciju |
| `README.md` | Modify — dodati ADR u strukturu projekta |

## Rizici

| Rizik | Mitigacija |
|-------|-----------|
| Overhead — korisnici ne pišu ADR jer je previše posla | Template je kratak (max 1 stranica), orkestrator pomaže u kreiranju |
| ADR zastareva a niko ne ažurira | Immutable dizajn — ne ažurira se, nego se kreira novi koji zamenjuje stari |
| Orkestrator ne prepoznaje kad treba ADR | Lista triggera u workflow.md daje jasne smernice; korisnik uvek može ručno tražiti ADR |

## Acceptance kriterijumi

- [ ] ADR template postoji u `docs/adr/TEMPLATE.md` sa svim sekcijama (Kontekst, Opcije, Odluka, Posledice)
  - **Verifikacija:** Pročitaj fajl i proveri sve sekcije
- [ ] ADR indeks postoji u `docs/adr/README.md` sa praznom tabelom
  - **Verifikacija:** Pročitaj fajl
- [ ] Spec kartica u workflow.md ima opciono `ADR:` polje
  - **Verifikacija:** `grep "ADR:" .claude/rules/workflow.md`
- [ ] workflow.md sadrži listu kada orkestrator predlaže ADR
  - **Verifikacija:** `grep -c "Uvođenje nove tehnologije" .claude/rules/workflow.md`
- [ ] principles.md ima primer ADR referenci
  - **Verifikacija:** `grep "ADR-" .claude/rules/principles.md`
- [ ] CLAUDE.md sadrži ADR sekciju
  - **Verifikacija:** `grep "Architecture Decision Records" CLAUDE.md`
- [ ] README.md sadrži `docs/adr/` u strukturi projekta
  - **Verifikacija:** `grep "adr" README.md`
