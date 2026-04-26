# ===== NODE.JS BACKEND VERIFICATION =====
if echo "$CHANGED_FILES" | grep -qE '^server/|^src/|^backend/|^api/'; then
    echo "-> Backend changes detected..."
    if [ -f "$PROJECT_DIR/package.json" ]; then
        if ! (cd "$PROJECT_DIR" && npm run build 2>&1); then
            ERRORS+=("Backend build FAILED")
        fi
        if ! (cd "$PROJECT_DIR" && npm test 2>&1); then
            ERRORS+=("Backend tests FAILED")
        fi
    fi
fi

# ===== FRONTEND VERIFICATION =====
if echo "$CHANGED_FILES" | grep -qE '^client/|^frontend/|^web/'; then
    echo "-> Frontend changes detected..."
    FRONTEND_DIR=$(find "$PROJECT_DIR" -maxdepth 1 -type d \( -name "client" -o -name "frontend" -o -name "web" \) | head -1)
    if [ -n "$FRONTEND_DIR" ] && [ -f "$FRONTEND_DIR/package.json" ]; then
        if ! (cd "$FRONTEND_DIR" && npm run build 2>&1); then
            ERRORS+=("Frontend build FAILED")
        fi
    fi
fi
