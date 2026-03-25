#!/bin/bash
# APD Bash Scope Guard — detektuje file-write operacije van dozvoljenog scope-a
# Korišćenje: bash guard-bash-scope.sh <dozvoljena_putanja_1> <dozvoljena_putanja_2> ...
# Primer:    bash guard-bash-scope.sh src/ tests/
#
# OGRANIČENJA: Hvata >, >>, tee redirekcije i cp/mv komande.
# NE HVATA: eval, bash -c, python -c, heredoc sa varijablama, &> (combined redirect).
# Ovi slučajevi ostaju pokriveni kognitivnim slojem (agent instrukcije).

ALLOWED_PATHS=("$@")

if [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "GREŠKA: jq nije instaliran. Potreban za guard-bash-scope.sh." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Funkcija: proveri da li je putanja u dozvoljenom scope-u
check_path() {
  local target="$1"

  # Ignoriši prazne putanje
  [ -z "$target" ] && return 0

  # Skini vodeći whitespace i navodnike
  target=$(echo "$target" | sed -E "s/^[[:space:]]*['\"]?//;s/['\"]?[[:space:]]*$//")

  # Konvertuj apsolutnu u relativnu
  if [[ "$target" == /* ]]; then
    local rel="${target#$PROJECT_DIR/}"
    # Ako je i dalje apsolutna — van projekta
    if [[ "$rel" == /* ]]; then
      echo "BLOKIRANO: Bash write operacija na $target — van projektnog direktorijuma." >&2
      echo "Dozvoljene putanje: ${ALLOWED_PATHS[*]}" >&2
      exit 2
    fi
    target="$rel"
  fi

  # Proveri scope
  for allowed in "${ALLOWED_PATHS[@]}"; do
    allowed="${allowed%/}/"
    if [[ "$target" == "$allowed"* ]]; then
      return 0
    fi
  done

  echo "BLOKIRANO: Bash write operacija na $target — van dozvoljenog scope-a." >&2
  echo "Dozvoljene putanje: ${ALLOWED_PATHS[*]}" >&2
  exit 2
}

# Detektuj redirekcije: > i >> (ali ne 2> ili &> koji su stderr/combined)
# Izvuci target fajl posle > ili >>
REDIRECT_TARGETS=$(echo "$COMMAND" | grep -oE '([^2&]|^)(>>?)[[:space:]]*[^ ;|&]+' | sed -E 's/^.*(>>?)[[:space:]]*//')

for target in $REDIRECT_TARGETS; do
  check_path "$target"
done

# Detektuj tee komande: tee [-a] <fajl>
TEE_TARGETS=$(echo "$COMMAND" | grep -oE 'tee[[:space:]]+(-a[[:space:]]+)?[^ ;|&]+' | sed -E 's/tee[[:space:]]+(-a[[:space:]]+)?//')

for target in $TEE_TARGETS; do
  check_path "$target"
done

# Detektuj cp/mv sa destinacijom
# cp source dest — destinacija je poslednji argument
# Ovo je pojednostavljeno — ne pokriva sve cp/mv varijante
CP_MV_MATCH=$(echo "$COMMAND" | grep -oE '(cp|mv)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*[^ ;|&]+[[:space:]]+[^ ;|&]+' | tail -1)
if [ -n "$CP_MV_MATCH" ]; then
  CP_MV_DEST=$(echo "$CP_MV_MATCH" | awk '{print $NF}')
  check_path "$CP_MV_DEST"
fi

exit 0
