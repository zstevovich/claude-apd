---
name: miro-dashboard
description: Vizualizuj APD pipeline status i metrike na Miro boardu — ažurira board sa trenutnim stanjem pipeline-a, završenim taskovima i metrikama
---

# Miro Pipeline Dashboard

Kreira ili ažurira pipeline dashboard na Miro boardu sa:
- Trenutni pipeline status (koji korak je aktivan)
- Poslednji završeni taskovi sa trajanjima
- Pipeline metrike (proseci, skip rate)

## Preduslov

- Miro MCP konfigurisan: `claude mcp add --transport http miro https://mcp.miro.com`
- Autentifikacija: `/mcp auth`
- Board URL definisan u CLAUDE.md (`{{MIRO_BOARD_URL}}`)

## Kada koristiti

- Na početku sesije — prikaz stanja pipeline-a na boardu
- Posle završenog taska — ažuriraj board sa novim rezultatom
- Na zahtev korisnika — "ažuriraj Miro dashboard"
- Periodično — za pregled performansi tima

## Procedura

### 1. Prikupi podatke

Pokreni sledeće komande i sačuvaj output:

```bash
# Pipeline status
bash .claude/scripts/pipeline-advance.sh status

# Metrike (ako postoje)
bash .claude/scripts/pipeline-advance.sh metrics

# Skip statistika
bash .claude/scripts/pipeline-advance.sh stats
```

### 2. Kreiraj dashboard tabelu na boardu

Koristi Miro MCP `create_table` da kreiraš tabelu sa sledećim sadržajem:

**Tabela 1: Pipeline Status**

| Korak | Status | Vreme |
|-------|--------|-------|
| Spec | ✅ / ⏳ / — | timestamp |
| Builder | ✅ / ⏳ / — | timestamp |
| Reviewer | ✅ / ⏳ / — | timestamp |
| Verifier | ✅ / ⏳ / — | timestamp |

- ✅ = završen (zeleni sticky note)
- ⏳ = u toku (žuti sticky note)
- — = nije započet (sivi sticky note)

### 3. Kreiraj metrike sekciju

Koristi Miro MCP `create_document` za markdown dokument:

```markdown
# APD Pipeline Metrike

**Ukupno taskova:** {broj}
**Prosečno trajanje:** {vreme}
**Najbrži task:** {vreme}
**Najsporiji task:** {vreme}
**Skip rate:** {procenat}

## Prosek po koraku
- spec→builder: {vreme}
- builder→reviewer: {vreme}
- reviewer→verifier: {vreme}
```

### 4. Kreiraj poslednje taskove

Koristi Miro MCP `create_table` za tabelu poslednjih 5 taskova:

| Task | Trajanje | Status |
|------|----------|--------|
| {naziv} | {vreme} | ✅ / ⚠️ skip / … partial |

### 5. Organizuj na boardu

Pozicioniraj elemente u frame pod nazivom **"APD Pipeline Dashboard"**:
- Pipeline Status tabela — gore levo
- Metrike dokument — gore desno
- Poslednji taskovi — dole

### 6. Ažuriranje postojećeg dashboarda

Ako frame "APD Pipeline Dashboard" već postoji na boardu:
1. Obriši postojeće elemente u frame-u
2. Kreiraj nove sa ažuriranim podacima
3. NE kreiraj novi frame — koristi postojeći

## Primer korišćenja

```
Korisnik: Ažuriraj Miro dashboard
Claude: Čitam pipeline status i metrike...

  Pipeline: CreateOrder task
    [DONE] spec
    [DONE] builder
    [----] reviewer ← sledeći
    [----] verifier

  Metrike: 12 taskova, prosek 8m 30s, skip rate 4%

  Ažuriram Miro board...
  ✓ Pipeline Status tabela ažurirana
  ✓ Metrike dokument ažuriran
  ✓ Poslednji taskovi tabela ažurirana

Dashboard ažuriran: https://miro.com/app/board/...
```

## Automatsko ažuriranje

Orkestrator može pozvati ovaj skill automatski na dva načina:

1. **Na kraju pipeline-a** — posle `pipeline-advance.sh verifier`, pre commita
2. **Na session start** — ako Miro board postoji u konfiguraciji

Za automatsko ažuriranje pri svakom koraku, dodaj u workflow orkestratora:
```
Posle svakog pipeline-advance.sh koraka → pozovi /miro-dashboard
```
