# ===== .NET BACKEND VERIFIKACIJA =====
if echo "$CHANGED_FILES" | grep -qE '^src/|^tests/'; then
    echo "→ Backend promene detektovane..."
    SLN_FILE=$(find "$PROJECT_DIR" -maxdepth 2 -name "*.sln" | head -1)
    if [ -z "$SLN_FILE" ]; then
        ERRORS+=("Backend: .sln NE POSTOJI")
    else
        if ! dotnet build "$SLN_FILE" -v q --nologo 2>&1; then
            ERRORS+=("Backend build FAILED")
        fi
        if ! dotnet test "$SLN_FILE" -v q --nologo --no-build 2>&1; then
            ERRORS+=("Backend testovi FAILED")
        fi
    fi
fi
