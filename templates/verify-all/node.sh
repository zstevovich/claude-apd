# ===== NODE.JS BACKEND VERIFIKACIJA =====
if echo "$CHANGED_FILES" | grep -qE '^server/|^src/'; then
    echo "→ Backend promene detektovane..."
    if [ -f "$PROJECT_DIR/package.json" ]; then
        if ! (cd "$PROJECT_DIR" && npm run build 2>&1); then
            ERRORS+=("Backend build FAILED")
        fi
        if ! (cd "$PROJECT_DIR" && npm test 2>&1); then
            ERRORS+=("Backend testovi FAILED")
        fi
    fi
fi

# ===== FRONTEND VERIFIKACIJA =====
if echo "$CHANGED_FILES" | grep -qE '^client/|^frontend/|^web/'; then
    echo "→ Frontend promene detektovane..."
    FRONTEND_DIR=$(find "$PROJECT_DIR" -maxdepth 1 -type d \( -name "client" -o -name "frontend" -o -name "web" \) | head -1)
    if [ -n "$FRONTEND_DIR" ] && [ -f "$FRONTEND_DIR/package.json" ]; then
        if ! (cd "$FRONTEND_DIR" && npm run build 2>&1); then
            ERRORS+=("Frontend build FAILED")
        fi
    fi
fi
