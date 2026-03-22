#!/bin/bash
# APD Guard — blokira neovlašćene git operacije
# Subagenti ne smeju commitovati, push-ovati niti raditi destruktivne operacije

if ! command -v jq &>/dev/null; then
  echo "GREŠKA: jq nije instaliran. Potreban za guard-git.sh." >&2
  echo "Instaliraj sa: brew install jq" >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Normalizuj: kolapsiraj razmake, skini vodeći whitespace
COMMAND=$(echo "$COMMAND" | tr -s ' ' | sed 's/^ //')

# Stripuj env var prefix-e (VAR=value VAR2=value ... komanda)
STRIPPED_CMD=$(echo "$COMMAND" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*//')

# Normalizuj git opcije: ukloni -C path, --git-dir=path itd.
NORMALIZED_GIT=$(echo "$STRIPPED_CMD" | sed -E 's/git[[:space:]]+(-[A-Za-z][[:space:]]+[^ ]+[[:space:]]+)*/git /g')

# APD_ORCHESTRATOR_COMMIT=1 je duži token koji je manje verovatan da ga
# subagent hallucinate. Samo orkestrator sme koristiti ovaj prefix.
# Ovo je "soft" guardrail — dovoljno robustan za praktičnu upotrebu.

# --- git commit ---
if echo "$NORMALIZED_GIT" | grep -qiE "git commit"; then
  if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 "; then
    # Autorizovani commit — pokreni verifikaciju pre propuštanja
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [ -x "$SCRIPT_DIR/verify-all.sh" ]; then
      echo "→ Pokretanje verifikacije pre commit-a..." >&2
      if ! bash "$SCRIPT_DIR/verify-all.sh" >&2; then
        echo "BLOKIRANO: Verifikacija nije prošla. Commit odbijen." >&2
        exit 2
      fi
    fi
    # Verifikacija prošla — dozvoli commit
    exit 0
  else
    echo "BLOKIRANO: git commit dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
    exit 2
  fi
fi

# --- git push ---
if echo "$NORMALIZED_GIT" | grep -qiE "git push"; then
  if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 "; then
    exit 0
  else
    echo "BLOKIRANO: git push dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
    exit 2
  fi
fi

# Blokiraj AI potpise
if echo "$NORMALIZED_GIT" | grep -qi "co-authored-by"; then
  echo "BLOKIRANO: AI potpis (Co-Authored-By) nije dozvoljen." >&2
  exit 2
fi

# Blokiraj git add .claude/
if echo "$NORMALIZED_GIT" | grep -qiE "git add.*\.claude"; then
  echo "BLOKIRANO: .claude/ direktorijum ne sme ici na git." >&2
  exit 2
fi

# Blokiraj destruktivne git operacije
if echo "$NORMALIZED_GIT" | grep -qiE "git (reset[[:space:]]+--hard|clean[[:space:]]+-[fdx]|checkout[[:space:]]+(--[[:space:]]+)?[.*]|restore[[:space:]]|branch[[:space:]]+-[Dd]|stash[[:space:]]+drop)"; then
  echo "BLOKIRANO: Destruktivna git operacija nije dozvoljena." >&2
  exit 2
fi

exit 0
