# Agent Pipeline Development (APD) Template

Softverski razvoj kroz specijalizovane agente u definisanom pipeline-u sa verifikacijama i human gate-ovima.

## Šta je APD?

APD je workflow za AI-asistiran razvoj softvera gde:
- **Agent** — rad dele specijalizovani agenti sa jasnim domenima, ne jedan generički AI
- **Pipeline** — definisan tok sa fazama, verifikacijama i gate-ovima koji se ne preskaču
- **Development** — softverski razvoj kao krajnji cilj

## Pipeline

```
Spec kartica → Builder → Reviewer → Verifier → Commit → [Human gate] → Push
```

## Kako koristiti

1. Kopiraj `.claude/` direktorijum i `CLAUDE.md` u svoj projekat
2. Pokreni setup: `bash .claude/scripts/setup.sh`
3. Prilagodi `CLAUDE.md` za svoj projekat (stack, konvencije, struktura)
4. Prilagodi agente u `.claude/agents/` za svoje domene
5. Prilagodi `verify-all.sh` za svoj build/test sistem
6. Dodaj `.claude/` u `.gitignore`

## Struktura

```
.claude/
├── agents/              # Builder agenti — jedan per domen
│   └── TEMPLATE.md      # Šablon za novog agenta
├── rules/
│   ├── workflow.md      # APD workflow definicija (UNIVERZALNO)
│   └── principles.md   # Projektna pravila (PRILAGODITI)
├── skills/              # Convention snippet-ovi za agente
├── scripts/
│   ├── guard-git.sh     # Blokira neovlašćene git operacije (UNIVERZALNO)
│   ├── verify-all.sh    # Build + test verifikacija (PRILAGODITI)
│   ├── setup.sh         # Inicijalni setup — zamena placeholder-a
│   └── session-start.sh # Učitava kontekst na početku sesije
└── memory/
    └── MEMORY.md        # Indeks memorije — akumulira se tokom rada

CLAUDE.md                # Projektne instrukcije za Claude Code (PRILAGODITI)
```

## Principi

1. **Spec pre koda** — svaki task počinje mini-spec karticom koju korisnik odobri
2. **Tri role** — Builder (implementira) → Reviewer (nalazi bagove) → Verifier (potvrđuje)
3. **Mikro-zadaci** — max 3-4 edit operacije po agentu, jasno vlasništvo nad fajlovima
4. **Human gate** — čovek odobrava API promene, migracije, auth logiku, deploy
5. **Cross-layer verifikacija** — frontend/mobile tipovi moraju biti 1:1 sa backend DTO-ovima
6. **Greškom-vođeni guardrail-i** — svaka greška postaje novo pravilo u memoriji
7. **Session memory** — posle svakog taska: šta je urađeno, šta je pošlo po zlu, nova pravila
