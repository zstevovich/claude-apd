# Orkestrator memorija

## Dva sistema memorije — ne mešati

| | APD memorija (`.claude/memory/`) | Claude auto memorija (`~/.claude/projects/`) |
|---|---|---|
| **Šta čuva** | Projektno znanje — status, session log, naučene lekcije | Lične preference korisnika, feedback, kontekst |
| **Ko koristi** | Svi na projektu (orkestrator + agenti) | Samo taj korisnik na toj mašini |
| **Gde živi** | U repozitorijumu — commituje se | Lokalno — NE commituje se |
| **Ko piše** | Orkestrator (posle svakog taska) | Claude automatski |
| **Primer** | "Auth middleware mora koristiti Redis sessione" | "Korisnik preferira kratke odgovore bez emoji-ja" |

**Pravilo:** Projektne odluke, arhitekturna pravila i naučene lekcije idu u APD memoriju. Lične preference i stil komunikacije ostaviti Claude auto memoriji.

## Projekat

- **Naziv:** [PROJECT_NAME]
- **Faza:** [Trenutna faza]
- **Rok:** [Datum]

## Roadmap

1. [Task 1]
2. [Task 2]

## Naučene lekcije

- (Akumulira se tokom rada — pogledaj session-log.md za detalje)
