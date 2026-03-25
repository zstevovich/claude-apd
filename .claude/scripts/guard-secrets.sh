#!/bin/bash
# APD Secrets Guard — blokira čitanje osetljivih fajlova iz Bash komandi
# Registruje se na Bash matcher SAMO za agente (ne za orkestratora)

if ! command -v jq &>/dev/null; then
  echo "GREŠKA: jq nije instaliran. Potreban za guard-secrets.sh." >&2
  exit 2
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Osetljivi pattern-i — fajlovi koji ne smeju biti čitani od strane agenata
# Dodaj pattern-e specifične za svoj projekat po potrebi
SENSITIVE_PATTERNS='(\.(env|pem|key|p12|pfx|keystore|jks)(\..*)?$|/\.ssh/|credential|secret[s]?\.)'

# Detektuj read komande sa osetljivim fajlovima
# Pokriveno: cat, head, tail, less, more, bat, grep na osetljivim fajlovima
READ_COMMANDS='(cat|head|tail|less|more|bat|strings|xxd|hexdump|od)'

# Izvuci sve argumente iz read komandi
if echo "$COMMAND" | grep -qE "$READ_COMMANDS"; then
  # Proveri svaki argument read komande
  ARGS=$(echo "$COMMAND" | grep -oE "$READ_COMMANDS[[:space:]]+[^;|&]+" | sed -E "s/$READ_COMMANDS[[:space:]]+//" | tr ' ' '\n')
  for arg in $ARGS; do
    # Preskoči flag-ove (počinju sa -)
    [[ "$arg" == -* ]] && continue
    # Proveri da li matchuje osetljiv pattern
    if echo "$arg" | grep -qiE "$SENSITIVE_PATTERNS"; then
      echo "BLOKIRANO: Čitanje osetljivog fajla '$arg' nije dozvoljeno." >&2
      echo "  Agenti ne smeju pristupati credential/secret/key fajlovima." >&2
      echo "  Ako je ovo potrebno, zatraži od orkestratora." >&2
      exit 2
    fi
  done
fi

# Proveri i source/. komande (sa razmakom iza da ne hvata svaki '.' u komandi)
if echo "$COMMAND" | grep -qE '(source[[:space:]]|\.[[:space:]])' ; then
  SOURCE_FILES=$(echo "$COMMAND" | grep -oE '(source|\.)[[:space:]]+[^ ;|&]+' | awk '{print $NF}')
  for sf in $SOURCE_FILES; do
    if echo "$sf" | grep -qiE "$SENSITIVE_PATTERNS"; then
      echo "BLOKIRANO: Source-ovanje osetljivog fajla '$sf' nije dozvoljeno." >&2
      exit 2
    fi
  done
fi

exit 0
