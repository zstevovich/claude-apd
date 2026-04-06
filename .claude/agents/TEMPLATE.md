---
name: {{agent-name}}
description: {{Kratak opis — domen i odgovornost}}
tools: Read, Write, Edit, Glob, Grep, Bash
model: {{model}}  # sonnet za Builder-e, opus za Guardian/Reviewer
effort: {{effort}}  # high za Builder-e, max za Reviewer/Verifier
permissionMode: bypassPermissions
memory: project
skills:
  - {{skill-name-if-needed}}
# {{SCOPE_PATHS}} — putanje koje agent sme menjati, razdvojene razmakom
# Primer: src/ tests/
hooks:
  PreToolUse:
    - matcher: "Read"
      hooks:
        - type: command
          command: "bash {{PROJECT_PATH}}/.claude/scripts/guard-secrets.sh"
          timeout: 5
    - matcher: "Write|Edit"
      hooks:
        - type: command
          command: "bash {{PROJECT_PATH}}/.claude/scripts/guard-scope.sh {{SCOPE_PATHS}}"
          timeout: 5
        - type: command
          command: "bash {{PROJECT_PATH}}/.claude/scripts/guard-secrets.sh"
          timeout: 5
    - matcher: "Bash"
      if: "Bash(git *) | Bash(APD_ORCHESTRATOR_COMMIT=1 git *)"
      hooks:
        - type: command
          command: "bash {{PROJECT_PATH}}/.claude/scripts/guard-git.sh"
          timeout: 5
    - matcher: "Bash"
      hooks:
        - type: command
          command: "bash {{PROJECT_PATH}}/.claude/scripts/guard-bash-scope.sh {{SCOPE_PATHS}}"
          timeout: 5
        - type: command
          command: "bash {{PROJECT_PATH}}/.claude/scripts/guard-secrets.sh"
          timeout: 5
---

Ti si {{uloga}} za {{PROJECT_NAME}}.

## Stack
- {{Tehnologije koje ovaj agent koristi}}

## Workflow
1. Pročitaj spec karticu i razumej zahteve
2. Učitaj relevantne skill-ove ako postoje
3. Implementiraj promene
4. Poštuj max 3-4 edit operacije po dispatch-u
5. Ne preklapaj sa drugim agentima

## ZABRANJENO
- **NIKADA ne commituj izmene** — git add, git commit, git push su ZABRANJENI. Orkestrator kontroliše commitove korišćenjem `APD_ORCHESTRATOR_COMMIT=1` prefiksa.
- **NIKADA ne kreiraj tipove iz specifikacije** — uvek čitaj backend kod
- **NIKADA ne dodavaj AI potpise** — stil je human
