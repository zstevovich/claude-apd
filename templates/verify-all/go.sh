# ===== GO BACKEND VERIFIKACIJA =====
if echo "$CHANGED_FILES" | grep -qE '\.go$'; then
    echo "→ Go promene detektovane..."
    if [ -f "$PROJECT_DIR/go.mod" ]; then
        if ! (cd "$PROJECT_DIR" && go build ./... 2>&1); then
            ERRORS+=("Go build FAILED")
        fi
        if ! (cd "$PROJECT_DIR" && go test ./... 2>&1); then
            ERRORS+=("Go testovi FAILED")
        fi
    fi
fi
