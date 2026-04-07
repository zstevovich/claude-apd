# Agent Pipeline Development (APD) — Workflow

## HARD GATE — TEHNIČKI ZAŠTIĆENO

**Svaka implementacija MORA proći sve korake: Spec → Builder → Reviewer → Verifier → tek onda commit.**

Ovo nije samo dokumentovano pravilo — **hook-ovi tehnički blokiraju commit** ako koraci nisu završeni.

### Mehanizam: Pipeline Flag System

```
.claude/.pipeline/
├── spec.done        # Orkestrator kreira posle odobrenog spec-a
├── builder.done     # Orkestrator kreira posle Builder-a
├── reviewer.done    # Orkestrator kreira posle Review-a
└── verifier.done    # Orkestrator kreira posle Verifier-a
```

- `guard-git.sh` → poziva `pipeline-gate.sh` → proverava da SVA 4 fajla postoje
- Ako bilo koji fali → **commit je BLOKIRAN**
- Posle commita → `pipeline-advance.sh reset` automatski briše flag-ove

### Komande

```bash
bash .claude/scripts/pipeline-advance.sh spec "Naziv taska"
bash .claude/scripts/pipeline-advance.sh builder
bash .claude/scripts/pipeline-advance.sh reviewer
bash .claude/scripts/pipeline-advance.sh verifier
bash .claude/scripts/pipeline-advance.sh status
bash .claude/scripts/pipeline-advance.sh reset
bash .claude/scripts/pipeline-advance.sh rollback           # Vrati jedan korak nazad
bash .claude/scripts/pipeline-advance.sh stats
bash .claude/scripts/pipeline-advance.sh skip "Razlog"  # Samo za hitne hotfix-ove
```

### Hard rules
- NIKADA ne preskakati Reviewer korak
- NIKADA ne grupisati više faza bez review-a između svake
- Brzina NIJE izgovor za preskakanje koraka
- Ovo pravilo je APSOLUTNO i neprekršivo

## 1. Spec kartica pre koda

Pre SVAKOG taska kreirati mini-spec:

```
## [Naziv taska]
**Cilj:** Jedna rečenica.
**Effort:** max | high
**Van scope-a:** Šta NE radimo.
**Acceptance kriterijumi:** Lista uslova za "gotovo".
**Pogođeni moduli:** Fajlovi/slojevi koji se menjaju.
**Rizici:** Šta može poći po zlu.
**Rollback:** Kako vratiti ako pukne.
**Human gate:** Da li zahteva odobrenje (API promene, migracije, auth, deploy).
```

Spec se deli sa korisnikom PRE implementacije.

## 2. Tri role agenata

### Builder
- Implementira kod prema spec-u
- Custom agenti u `.claude/agents/`
- Max 3-4 edit operacije po dispatch-u
- Jasno vlasništvo nad fajlovima

### Reviewer
- Samo nalazi rizike, bagove, propuste
- NE predlaže stilske promene van scope-a
- Pokreće se AUTOMATSKI posle svakog Builder-a

### Verifier
- Build + test + contract check
- Pokreće se POSLE Reviewer-a, PRE commit-a

### Orkestrator
- Kreira spec karticu
- Dispatchuje Builder-e (paralelno gde je moguće)
- Pokreće Reviewer-a i Verifier-a
- Jedini commituje i push-uje
- Jedini komunicira sa korisnikom

## 3. Mikro-zadaci

- Svaki task: jedna funkcionalna promena
- Max 3-4 edit operacije po agentu
- Jedan agent = jasno vlasništvo nad fajlovima
- Ako task zahteva >5 fajlova, razbiti na 2+ agenta

## 4. Verifikacija pre "gotovo"

Pre SVAKOG commit-a:
- [ ] Build prolazi (0 errors)
- [ ] Testovi prolaze (0 failures)
- [ ] Frontend type check prolazi (ako ima frontend promene)
- [ ] Cross-layer contract check (ako task uključuje >1 sloj)
- [ ] Review nalaze primenjene

Pre SVAKOG push-a na staging/production:
- [ ] Sve gore
- [ ] Korisnik eksplicitno odobrio push

## 5. Human gate

Korisnik MORA odobriti pre:
- API promene (novi endpointi, promena potpisa)
- Migracije baze
- Auth/role logika
- Deploy na staging/produkciju

## 6. Session memory update

Posle SVAKOG završenog taska, append u `.claude/memory/session-log.md`:

```markdown
## [YYYY-MM-DD] [Naziv taska]
**Status:** Završen | Delimičan | Blokiran
**Šta je urađeno:** [1-2 rečenice]
**Problemi:** [Šta je pošlo po zlu, ili "Bez problema"]
**Guardrail koji je pomogao:** [Koji mehanizam je uhvatio problem, ili "N/A"]
**Novo pravilo:** [Šta dodajemo u workflow, ili "Nema"]
```

- **Rotacija:** `rotate-session-log.sh` automatski arhivira starije od 10 entry-ja

## 7. Cross-layer verifikacija

Kad task uključuje backend + frontend/mobile:
1. Backend DTO/response model je **izvor istine**
2. Za svako polje mapirati tip na frontend ekvivalent
3. Nullable polja moraju biti nullable na svim slojevima
4. NIKADA ne kreirati frontend tip iz specifikacije — uvek čitaj backend DTO

## 8. Reasoning effort

| Effort | Kada | Primeri |
|--------|------|---------|
| **max** | Odluke koje je skupo ispraviti | Planiranje, arhitektura, review, spec, security |
| **high** | Implementacija po jasnom spec-u | Builder kodiranje, testovi, refactoring |

- Orkestrator uvek radi na **max**
- Builder agenti na **high**
- Reviewer i Verifier na **max**
