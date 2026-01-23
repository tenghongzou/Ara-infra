#!/bin/bash
set -e

# Check if vendor directory exists and has autoload.php
if [ ! -f "/app/vendor/autoload.php" ]; then
    echo ">>> vendor directory not found or incomplete, running composer install..."
    composer install --prefer-dist --no-interaction
    echo ">>> composer install completed"
fi

# Run Symfony cache warmup in dev mode
if [ "$APP_ENV" = "dev" ]; then
    echo ">>> Warming up Symfony cache..."
    php bin/console cache:warmup --no-interaction 2>/dev/null || true
fi

# Execute the main command (FrankenPHP)
exec "$@"
