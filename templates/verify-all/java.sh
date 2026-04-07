# ===== JAVA BACKEND VERIFICATION =====
if echo "$CHANGED_FILES" | grep -qE '^src/main/|^src/test/'; then
    echo "-> Backend changes detected..."
    if [ -f "$PROJECT_DIR/pom.xml" ]; then
        if ! (cd "$PROJECT_DIR" && mvn compile -q 2>&1); then
            ERRORS+=("Maven build FAILED")
        fi
        if ! (cd "$PROJECT_DIR" && mvn test -q 2>&1); then
            ERRORS+=("Maven tests FAILED")
        fi
    elif [ -f "$PROJECT_DIR/build.gradle" ] || [ -f "$PROJECT_DIR/build.gradle.kts" ]; then
        if ! (cd "$PROJECT_DIR" && ./gradlew build -q 2>&1); then
            ERRORS+=("Gradle build FAILED")
        fi
    fi
fi
