#!/bin/bash
# APD Verify All — pokreće verifikaciju za sve promenjene komponente
# ===== PRILAGODI BUILD KOMANDE ZA SVOJ STACK =====

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR" || exit 0

ERRORS=()

if git rev-parse HEAD &>/dev/null; then
    CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null)
    [ -z "$CHANGED_FILES" ] && CHANGED_FILES=$(git diff --name-only HEAD 2>/dev/null)
else
    CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null)
fi

# ===== BACKEND VERIFIKACIJA =====
# Prilagodi putanju i build komandu za svoj stack:
#   .NET:    dotnet build *.sln -v q --nologo && dotnet test *.sln -v q --nologo --no-build
#   PHP:     php bin/console lint:container && php vendor/bin/phpunit
#   Node:    npm run build && npm test
#   Python:  python -m pytest
#   Go:      go build ./... && go test ./...
#
# Primer (.NET):
# if echo "$CHANGED_FILES" | grep -qE '^src/|^tests/'; then
#     echo "→ Backend promene detektovane..."
#     if [ ! -f "$PROJECT_DIR/src/MyProject.sln" ]; then
#         ERRORS+=("Backend: .sln NE POSTOJI")
#     else
#         if ! dotnet build src/MyProject.sln -v q --nologo 2>&1; then
#             ERRORS+=("Backend build FAILED")
#         fi
#         if ! dotnet test src/MyProject.sln -v q --nologo --no-build 2>&1; then
#             ERRORS+=("Backend testovi FAILED")
#         fi
#     fi
# fi
# ================================

# ===== FRONTEND VERIFIKACIJA =====
# Primer (React/Vite):
# if echo "$CHANGED_FILES" | grep -qE '^apps/frontend/'; then
#     echo "→ Frontend promene detektovane..."
#     if [ ! -f "$PROJECT_DIR/apps/frontend/package.json" ]; then
#         ERRORS+=("Frontend: package.json NE POSTOJI")
#     else
#         if ! (cd "$PROJECT_DIR/apps/frontend" && npm run build 2>&1); then
#             ERRORS+=("Frontend build FAILED")
#         fi
#     fi
# fi
# =================================

# ===== CROSS-LAYER CONTRACT VERIFIKACIJA =====
# Pokreni verify-contracts.sh ako postoji i ako su promene u oba sloja
# SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# HAS_BACKEND=$(echo "$CHANGED_FILES" | grep -qE '^src/' && echo "true" || echo "false")
# HAS_FRONTEND=$(echo "$CHANGED_FILES" | grep -qE '^apps/' && echo "true" || echo "false")
# if [ "$HAS_BACKEND" = "true" ] && [ "$HAS_FRONTEND" = "true" ]; then
#     if [ -x "$SCRIPT_DIR/verify-contracts.sh" ]; then
#         echo "→ Cross-layer contract check..."
#         if ! bash "$SCRIPT_DIR/verify-contracts.sh" --changed 2>&1; then
#             ERRORS+=("Cross-layer contract verifikacija FAILED")
#         fi
#     fi
# fi
# ==============================================

# Upozorenje: ako ništa nije konfigurisano, verify-all je beskorisan
# Ukloni ovaj blok kad prilagodiš gornje sekcije za svoj stack
if [ ${#ERRORS[@]} -eq 0 ] && [ -n "$CHANGED_FILES" ]; then
    echo "UPOZORENJE: verify-all.sh nije prilagođen — nijedna verifikacija nije pokrenuta." >&2
    echo "Otkomentiraj backend/frontend sekcije za svoj stack." >&2
fi

# Rezultat
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
