#!/bin/bash
# APD Verifier — pokreće se automatski pre svakog commit-a (poziva ga guard-git.sh)
#
# PRILAGODITI: Otkomentariši i podesi build/test komande za svoj projekat.
# Dok je sve zakomentarisano, verifikacija uvek prolazi — ovo je NAMERNO
# za nov projekat, ali MORA se konfigurisati pre produkcijskog rada.

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 0

ERRORS=()
CHECKS_RAN=0

# Detektuj promenjene fajlove (staged za commit, ili sve ako nema prethodnog commit-a)
if git rev-parse HEAD &>/dev/null; then
    CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null)
    [ -z "$CHANGED_FILES" ] && CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null)
else
    CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null)
fi

# ====================
# BACKEND VERIFIKACIJA
# ====================
# PRILAGODITI: putanje i komande za svoj backend
if echo "$CHANGED_FILES" | grep -qE '^src/|^tests/'; then
    echo "→ Backend promene detektovane..."
    # PRIMER (Node.js):  npm test
    # PRIMER (Python):   pytest tests/
    # PRIMER (Go):       go build ./... && go test ./...
    # PRIMER (.NET):     dotnet build && dotnet test
    #
    # CHECKS_RAN=1
    # if ! YOUR_BUILD_COMMAND 2>&1; then
    #     ERRORS+=("Backend build FAILED")
    # fi
    # if ! YOUR_TEST_COMMAND 2>&1; then
    #     ERRORS+=("Backend testovi FAILED")
    # fi
    echo "  (KONFIGURIŠI build/test komande u verify-all.sh)"
fi

# ====================
# FRONTEND VERIFIKACIJA
# ====================
# PRILAGODITI: putanje i komande za svoj frontend
if echo "$CHANGED_FILES" | grep -qE '^apps/|^frontend/|^web/'; then
    echo "→ Frontend promene detektovane..."
    # PRIMER (React/TS): cd apps/frontend && npx tsc --noEmit && npm test
    # PRIMER (Vue):      cd apps/frontend && npm run type-check && npm test
    #
    # CHECKS_RAN=1
    # if ! YOUR_TYPECHECK_COMMAND 2>&1; then
    #     ERRORS+=("Frontend type check FAILED")
    # fi
    echo "  (KONFIGURIŠI frontend check u verify-all.sh)"
fi

# ====================
# REZULTAT
# ====================
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "VERIFIKACIJA NIJE PROŠLA:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    exit 1
fi

# Failsafe: upozori ako nijedna provera nije konfigurisana
if [ "$CHECKS_RAN" -eq 0 ]; then
    echo "UPOZORENJE: verify-all.sh nema konfigurisanih provera!" >&2
    echo "  Verifier faza ne testira ništa — konfiguriši build/test komande." >&2
    echo "  Fajl: .claude/scripts/verify-all.sh" >&2
fi

echo "Verifikacija prošla"
exit 0
