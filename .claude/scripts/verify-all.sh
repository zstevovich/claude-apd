#!/bin/bash
# APD Verifier — pokreće se pre svakog commit-a
# PRILAGODITI: build i test komande za svoj projekat

# PROMENITI na apsolutnu putanju projekta:
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 0

ERRORS=()

# ====================
# BACKEND VERIFIKACIJA
# ====================
# PRILAGODITI: komande za build i test
if git diff --name-only HEAD 2>/dev/null | grep -qE '^src/|^tests/'; then
    echo "→ Backend build..."
    # PRIMER: dotnet build src/MyProject.sln -v q --nologo
    # BUILD=$(dotnet build src/MyProject.sln -v q --nologo 2>&1)
    # if echo "$BUILD" | grep -q "Build FAILED"; then
    #     ERRORS+=("Backend build FAILED")
    # fi

    echo "→ Backend testovi..."
    # PRIMER: dotnet test src/MyProject.sln -v q --nologo --no-build
    # TEST=$(dotnet test src/MyProject.sln -v q --nologo --no-build 2>&1)
    # if echo "$TEST" | grep -q "Failed:"; then
    #     ERRORS+=("Backend testovi FAILED")
    # fi
    echo "  (KONFIGURIŠI build/test komande u verify-all.sh)"
fi

# ====================
# FRONTEND VERIFIKACIJA
# ====================
# PRILAGODITI: putanja i komande za frontend
if git diff --name-only HEAD 2>/dev/null | grep -qE '^apps/|^frontend/|^web/'; then
    echo "→ Frontend TypeScript check..."
    # PRIMER: cd apps/frontend && npx tsc --noEmit
    # TSC_ERRORS=$(npx tsc --noEmit 2>&1 | grep ": error TS" | wc -l)
    # if [ "$TSC_ERRORS" -gt 0 ]; then
    #     ERRORS+=("Frontend TS: $TSC_ERRORS grešaka")
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

echo "Verifikacija prošla"
exit 0
