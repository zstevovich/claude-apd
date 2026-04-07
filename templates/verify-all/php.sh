# ===== PHP BACKEND VERIFIKACIJA =====
if echo "$CHANGED_FILES" | grep -qE '\.php$'; then
    echo "→ PHP promene detektovane..."
    if [ -f "$PROJECT_DIR/composer.json" ]; then
        if [ -f "$PROJECT_DIR/bin/console" ]; then
            if ! (cd "$PROJECT_DIR" && php bin/console lint:container 2>&1); then
                ERRORS+=("Symfony container lint FAILED")
            fi
        fi
        if ! (cd "$PROJECT_DIR" && php vendor/bin/phpunit 2>&1); then
            ERRORS+=("PHPUnit testovi FAILED")
        fi
    fi
fi
