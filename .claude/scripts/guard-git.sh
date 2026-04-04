#!/bin/bash
# APD Guard — blokira neovlašćene git operacije
# Subagenti ne smeju commitovati, push-ovati niti raditi destruktivne operacije

if ! command -v jq &>/dev/null; then
  echo "GREŠKA: jq nije instaliran. Potreban za guard-git.sh." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

RAW_COMMAND="$COMMAND"
COMMAND=$(echo "$COMMAND" | tr -s ' ' | sed 's/^ //')
STRIPPED_CMD=$(echo "$COMMAND" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*//')
NORMALIZED_GIT=$(echo "$STRIPPED_CMD" | sed -E 's/git[[:space:]]+(-[A-Za-z][[:space:]]+[^ ]+[[:space:]]+)*/git /g')

# Blokiraj --no-verify
if echo "$RAW_COMMAND" | grep -qE '(^| )--no-verify( |$)'; then
  echo "BLOKIRANO: --no-verify nije dozvoljen. Hook-ovi moraju proći." >&2
  exit 2
fi

# Blokiraj masovni staging
if echo "$NORMALIZED_GIT" | grep -qE "git add[[:space:]]+(\.([[:space:]]|$)|-[AuU]([[:space:]]|$)|--all([[:space:]]|$)|\*)"; then
  echo "BLOKIRANO: git add . / git add -A / git add --all nije dozvoljen." >&2
  echo "Koristi: git add <fajl1> <fajl2> ..." >&2
  exit 2
fi

# --- git commit ---
if echo "$NORMALIZED_GIT" | grep -qiE "git commit"; then
  if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 "; then
    # Blokiraj commit -a čak i sa prefixom
    if echo "$NORMALIZED_GIT" | grep -qE "git commit[[:space:]]+.*(-a([[:space:]]|$)|--all([[:space:]]|$))"; then
      echo "BLOKIRANO: git commit -a / --all nije dozvoljen. Stage-uj fajlove eksplicitno." >&2
      exit 2
    fi

    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

    # 1. Pipeline gate
    if [ -x "$SCRIPT_DIR/pipeline-gate.sh" ]; then
      if ! bash "$SCRIPT_DIR/pipeline-gate.sh" >&2; then
        echo "" >&2
        echo "BLOKIRANO: Pipeline koraci nisu završeni. Commit odbijen." >&2
        exit 2
      fi
    fi

    # 2. Verifikacija (build + lint + test)
    if [ -x "$SCRIPT_DIR/verify-all.sh" ]; then
      echo "→ Pokretanje verifikacije pre commit-a..." >&2
      if ! bash "$SCRIPT_DIR/verify-all.sh" >&2; then
        echo "BLOKIRANO: Verifikacija nije prošla. Commit odbijen." >&2
        exit 2
      fi
    fi

    # 3. Auto-reset pipeline
    (bash "$SCRIPT_DIR/pipeline-advance.sh" reset >/dev/null 2>&1 &)
    echo "Pipeline + Verifikacija prošli — commit dozvoljen." >&2
    exit 0
  else
    echo "BLOKIRANO: git commit dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
    exit 2
  fi
fi

# --- git push ---
if echo "$NORMALIZED_GIT" | grep -qiE "git push"; then
  if echo "$NORMALIZED_GIT" | grep -qE "git push.*(-f([[:space:]]|$)|--force([[:space:]]|$)|--force-with-lease([[:space:]]|$))"; then
    echo "BLOKIRANO: git push --force nije dozvoljen." >&2
    exit 2
  fi
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

# .claude/ zaštita
if echo "$NORMALIZED_GIT" | grep -qiE "git add.*\.claude"; then
  if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 "; then
    exit 0
  else
    echo "BLOKIRANO: git add .claude/ dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
    exit 2
  fi
fi

# Blokiraj destruktivne git operacije
if echo "$NORMALIZED_GIT" | grep -qiE "git (reset[[:space:]]+--hard|clean[[:space:]]+-[fdx]|checkout[[:space:]]+--[[:space:]]|checkout[[:space:]]+\.([[:space:]]|$)|restore[[:space:]]|stash[[:space:]]+drop|tag[[:space:]]+-d([[:space:]]|$))"; then
  echo "BLOKIRANO: Destruktivna git operacija nije dozvoljena." >&2
  exit 2
fi

# branch -D (force delete)
if echo "$NORMALIZED_GIT" | grep -qE "git branch[[:space:]]+-D([[:space:]]|$)"; then
  echo "BLOKIRANO: git branch -D (force delete) nije dozvoljen. Koristi -d za safe delete." >&2
  exit 2
fi

exit 0
