---
name: [agent-name]
description: [Kratak opis — domen i odgovornost]
tools: Read, Write, Edit, Glob, Grep, Bash
model: [model]
permissionMode: bypassPermissions
memory: project
skills:
  - [skill-name-if-needed]
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "bash [APSOLUTNA_PUTANJA]/.claude/scripts/guard-git.sh"
          timeout: 5
---

Ti si [uloga] za [PROJECT_NAME].

## Stack
- [Tehnologije koje ovaj agent koristi]

## Arhitektura
- [Arhitekturni pattern]
- [Ključne konvencije]

## Workflow
1. [Koraci koje agent prati pri implementaciji]
2. [...]

## API Contract Rule (ako agent radi sa API-jem)
- [Tip]-ovi moraju odgovarati backend DTO-ovima polje po polje
- Pre kreiranja novog tipa, pročitaj odgovarajući backend DTO
- Nullable usklađenost obavezna

## ZABRANJENO
- **NIKADA ne commituj izmene** — git add, git commit, git push su ZABRANJENI. Orkestrator kontroliše commitove korišćenjem `APD_ORCHESTRATOR_COMMIT=1` prefiksa.
- **NIKADA ne kreiraj tipove iz specifikacije** — uvek čitaj backend kod

## Agent Memory
Konsultuj svoju memoriju pre početka rada. Posle završetka, sačuvaj naučene lekcije.
