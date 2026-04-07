# ===== GO BACKEND VERIFICATION =====
if echo "$CHANGED_FILES" | grep -qE '\.go$'; then
    echo "-> Go changes detected..."
    if [ -f "$PROJECT_DIR/go.mod" ]; then
        if ! (cd "$PROJECT_DIR" && go build ./... 2>&1); then
            ERRORS+=("Go build FAILED")
        fi
        if ! (cd "$PROJECT_DIR" && go test ./... 2>&1); then
            ERRORS+=("Go tests FAILED")
        fi
    fi
fi
