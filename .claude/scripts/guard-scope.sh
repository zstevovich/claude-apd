#!/bin/bash
# APD Scope Guard — blokira Write/Edit operacije van dozvoljenog scope-a
# Korišćenje: bash guard-scope.sh <dozvoljena_putanja_1> <dozvoljena_putanja_2> ...
# Primer:    bash guard-scope.sh src/ tests/

# Dozvoljene putanje iz argumenata
ALLOWED_PATHS=("$@")

if [ ${#ALLOWED_PATHS[@]} -eq 0 ]; then
  # Nema ograničenja — dozvoli sve
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "GREŠKA: jq nije instaliran. Potreban za guard-scope.sh." >&2
  exit 2
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  # Nema file_path u tool input-u — nije Write/Edit poziv, dozvoli
  exit 0
fi

# Konvertuj apsolutnu putanju u relativnu
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REL_PATH="${FILE_PATH#$PROJECT_DIR/}"

# Ako je putanja i dalje apsolutna (nije u projektu), blokiraj
if [[ "$REL_PATH" == /* ]]; then
  echo "BLOKIRANO: Fajl $FILE_PATH je van projektnog direktorijuma." >&2
  echo "Dozvoljene putanje: ${ALLOWED_PATHS[*]}" >&2
  exit 2
fi

# Proveri da li relativna putanja počinje sa jednom od dozvoljenih
# Normalizuj: osiguraj trailing slash da izbegneš prefix kolizije (src vs src-legacy)
for allowed in "${ALLOWED_PATHS[@]}"; do
  allowed="${allowed%/}/"
  if [[ "$REL_PATH" == "$allowed"* ]]; then
    exit 0
  fi
done

# Nijedna dozvoljena putanja ne odgovara — blokiraj
echo "BLOKIRANO: Fajl $REL_PATH je van dozvoljenog scope-a." >&2
echo "Dozvoljene putanje: ${ALLOWED_PATHS[*]}" >&2
exit 2
