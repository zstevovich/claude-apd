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

# Sačuvaj raw komandu pre normalizacije (za --no-verify detekciju)
RAW_COMMAND="$COMMAND"

# Normalizuj: kolapsiraj razmake, skini vodeći whitespace
COMMAND=$(echo "$COMMAND" | tr -s ' ' | sed 's/^ //')

# Stripuj env var prefix-e (VAR=value VAR2=value ... komanda)
STRIPPED_CMD=$(echo "$COMMAND" | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*//')

# Normalizuj git opcije: ukloni -C path, --git-dir=path itd.
NORMALIZED_GIT=$(echo "$STRIPPED_CMD" | sed -E 's/git[[:space:]]+(-[A-Za-z][[:space:]]+[^ ]+[[:space:]]+)*/git /g')

# APD_ORCHESTRATOR_COMMIT=1 je duži token koji je manje verovatan da ga
# subagent hallucinate. Samo orkestrator sme koristiti ovaj prefix.
# Ovo je "soft" guardrail — dovoljno robustan za praktičnu upotrebu.

# Blokiraj --no-verify kao standalone flag (ne u commit poruci)
# Matchuje --no-verify okružen razmakom ili na kraju stringa
if echo "$RAW_COMMAND" | grep -qE '(^| )--no-verify( |$)'; then
  echo "BLOKIRANO: --no-verify nije dozvoljen. Hook-ovi moraju proći." >&2
  exit 2
fi

# Blokiraj masovni staging — forsira eksplicitno dodavanje fajlova po imenu
# Regex koristi word boundary (razmak ili kraj stringa) da ne blokira fajlove kao .gitignore
if echo "$NORMALIZED_GIT" | grep -qE "git add[[:space:]]+(\.([[:space:]]|$)|-[AuU]([[:space:]]|$)|--all([[:space:]]|$)|\*)"; then
  echo "BLOKIRANO: git add . / git add -A / git add --all / git add -u / git add * nije dozvoljen." >&2
  echo "Koristi: git add <fajl1> <fajl2> ..." >&2
  exit 2
fi

# --- git commit ---
if echo "$NORMALIZED_GIT" | grep -qiE "git commit"; then
  if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 "; then
    # Blokiraj commit -a čak i sa prefixom — forsira eksplicitno staging
    # Napomena: ovo je strožije od spec-a (koji traži blokadu samo bez prefiksa),
    # ali je ispravno ponašanje — staging mora uvek biti eksplicitan
    if echo "$NORMALIZED_GIT" | grep -qE "git commit[[:space:]]+.*(-a([[:space:]]|$)|--all([[:space:]]|$))"; then
      echo "BLOKIRANO: git commit -a / --all nije dozvoljen. Stage-uj fajlove eksplicitno pre commit-a." >&2
      exit 2
    fi
    # Autorizovani commit — pokreni verifikaciju pre propuštanja
    # VAŽNO: zadrži CELU postojeću logiku ispod (verify-all.sh poziv itd.)
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [ -x "$SCRIPT_DIR/verify-all.sh" ]; then
      echo "→ Pokretanje verifikacije pre commit-a..." >&2
      if ! bash "$SCRIPT_DIR/verify-all.sh" >&2; then
        echo "BLOKIRANO: Verifikacija nije prošla. Commit odbijen." >&2
        exit 2
      fi
    fi
    # Podsetnik za pipeline disciplinu
    echo "⚠ PODSETNIK: Da li je Reviewer korak završen pre commit-a?" >&2
    echo "  Pipeline: Spec → Builder → Reviewer → Verifier → Commit" >&2
    # Verifikacija prošla — dozvoli commit
    exit 0
  else
    echo "BLOKIRANO: git commit dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
    echo "Koristi: APD_ORCHESTRATOR_COMMIT=1 git commit -m \"opis promene\"" >&2
    exit 2
  fi
fi

# --- git push ---
if echo "$NORMALIZED_GIT" | grep -qiE "git push"; then
  # Blokiraj force push — čak i sa prefiksom
  if echo "$NORMALIZED_GIT" | grep -qE "git push.*(-f([[:space:]]|$)|--force([[:space:]]|$)|--force-with-lease([[:space:]]|$))"; then
    echo "BLOKIRANO: git push --force nije dozvoljen. Koristi regularni push." >&2
    echo "Ako zaista treba force push, uradi to ručno van Claude-a." >&2
    exit 2
  fi
  if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 "; then
    exit 0
  else
    echo "BLOKIRANO: git push dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
    echo "Koristi: APD_ORCHESTRATOR_COMMIT=1 git push origin <branch>" >&2
    exit 2
  fi
fi

# Blokiraj AI potpise
if echo "$NORMALIZED_GIT" | grep -qi "co-authored-by"; then
  echo "BLOKIRANO: AI potpis (Co-Authored-By) nije dozvoljen." >&2
  exit 2
fi

# .claude/ — samo orkestrator sme commitovati promene u workflow fajlovima
if echo "$NORMALIZED_GIT" | grep -qiE "git add.*\.claude"; then
  if echo "$COMMAND" | grep -qE "^APD_ORCHESTRATOR_COMMIT=1 "; then
    exit 0
  else
    echo "BLOKIRANO: git add .claude/ dozvoljen samo sa APD_ORCHESTRATOR_COMMIT=1 prefixom." >&2
    exit 2
  fi
fi

# Blokiraj destruktivne git operacije (case-insensitive za većinu)
if echo "$NORMALIZED_GIT" | grep -qiE "git (reset[[:space:]]+--hard|clean[[:space:]]+-[fdx]|checkout[[:space:]]+--[[:space:]]|checkout[[:space:]]+\.([[:space:]]|$)|restore[[:space:]]|stash[[:space:]]+drop|tag[[:space:]]+-d([[:space:]]|$))"; then
  echo "BLOKIRANO: Destruktivna git operacija nije dozvoljena." >&2
  exit 2
fi

# branch -D (force delete) — MORA biti case-sensitive jer -d (safe) treba da prođe
if echo "$NORMALIZED_GIT" | grep -qE "git branch[[:space:]]+-D([[:space:]]|$)"; then
  echo "BLOKIRANO: git branch -D (force delete) nije dozvoljen. Koristi -d za safe delete." >&2
  exit 2
fi

exit 0
