# [PROJECT_NAME]

## O projektu

[Kratak opis projekta — jedna rečenica.]
[Ciljna baza korisnika. Rok lansiranja.]

## Faza projekta

[Trenutna faza i šta je sledeće.]

## Tehnički stack

### Backend
[Jezik, framework, baza, keš, messaging...]

### Frontend
[Framework, UI biblioteka, state management...]

### Mobile (ako postoji)
[Framework, arhitektura...]

### Infrastruktura
[Hosting, CI/CD, Docker...]

## Pravila

### Jezik i dokumentacija
- [Jezik dokumentacije]
- Stručni termini na engleskom
- Ton: profesionalan, konkretan
- Minimalni komentari — kod je samoobjašnjiv

### Git
- Grane: `develop` → `staging` → `main` (+ `feature/*`)
- **Nema AI potpisa u commitima**
- `.claude/` direktorijum **je deo repozitorijuma** (deljeni workflow)

### Agent Pipeline Development (APD) — `.claude/rules/workflow.md` (izvor istine)
- **Spec kartica** pre svakog taska — cilj, scope, acceptance kriterijumi, rizici, human gate
- **3 role:** Builder (implementira) → Reviewer (nalazi bagove) → Verifier (build/test/contract)
- **Orkestrator** jedini commituje, push-uje, komunicira sa korisnikom
- **Mikro-zadaci:** max 3-4 edita po agentu, jasno vlasništvo nad fajlovima
- **Human gate:** API promene, migracije, auth logika, deploy — korisnik mora odobriti
- **Verifikacija:** build + test + cross-layer contract + smoke test pre svakog commit-a
- **Session memory:** posle svakog taska zapisati šta je pošlo po zlu i nova pravila

### Plugini i alati

**Pre implementacije:**

- `superpowers:brainstorming` — pre kreativnog rada (istražuje nameru, zahteve, dizajn)
- `superpowers:writing-plans` — kada imaš spec (kreira implementacioni plan)
- `superpowers:using-git-worktrees` — izolovan workspace za feature rad

**Builder faza:**

- `superpowers:executing-plans` — izvršava plan task po task
- `superpowers:subagent-driven-development` — paralelni agenti za nezavisne taskove
- `superpowers:dispatching-parallel-agents` — 2+ nezavisna taska paralelno
- `superpowers:test-driven-development` — TDD workflow (test pre implementacije)
- `superpowers:systematic-debugging` — sistematski debugging pre predlaganja fix-a
- `feature-dev:feature-dev` — vođeni feature development sa razumevanjem codebase-a
- `frontend-design:frontend-design` — production-grade frontend interfejsi

**Reviewer faza:**

- `superpowers:requesting-code-review` — traži review po završetku implementacije
- `superpowers:receiving-code-review` — primanje i obrada review feedback-a
- `code-review:code-review` — review pull request-a
- `simplify` — review koda za kvalitet, reuse i efikasnost

**Verifier faza:**

- `verify-all.sh` — build + test
- `superpowers:verification-before-completion` — verifikacija pre tvrdnje da je gotovo
- Cross-layer contract check

**Post-commit:**

- `superpowers:finishing-a-development-branch` — merge, PR, cleanup opcije
- `claude-md-management:revise-claude-md` — ažuriranje CLAUDE.md sa lekcijama iz sesije

**Figma integracija (ako projekat koristi Figma):**

- `figma:implement-design` — Figma dizajn → kod
- `figma:code-connect-components` — povezivanje Figma komponenti sa kodom
- `figma:create-design-system-rules` — design system pravila za projekat

**Alati:**

- Context7 — up-to-date dokumentacija biblioteka
- LSP — automatski type checking
- `claude-code-setup:claude-automation-recommender` — preporuka automatizacija za projekat
- `claude-md-management:claude-md-improver` — audit i poboljšanje CLAUDE.md fajlova

## Struktura projekta

```
├── CLAUDE.md                        # Projektne instrukcije
├── src/                             # [Backend kod]
├── tests/                           # [Testovi]
├── apps/                            # [Frontend/mobile]
├── docs/                            # [Dokumentacija]
└── .claude/                         # Claude Code okruženje (gitignored)
    ├── agents/                      # Custom agenti
    ├── skills/                      # Convention snippet-ovi
    ├── rules/                       # Pravila (workflow, konvencije)
    ├── scripts/                     # Hook skripte
    └── memory/                      # Perzistentna memorija
```
