# ===== PYTHON BACKEND VERIFIKACIJA =====
if echo "$CHANGED_FILES" | grep -qE '\.py$'; then
    echo "→ Python promene detektovane..."
    if [ -f "$PROJECT_DIR/pyproject.toml" ] || [ -f "$PROJECT_DIR/setup.py" ]; then
        if ! (cd "$PROJECT_DIR" && python -m pytest 2>&1); then
            ERRORS+=("Python testovi FAILED")
        fi
    fi
fi
