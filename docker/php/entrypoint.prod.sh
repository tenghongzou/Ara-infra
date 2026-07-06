#!/bin/sh
set -e

# Production entrypoint. Dependencies and the optimized autoloader are baked
# into the image, so there is no runtime composer install. Warm the prod cache
# then hand off to FrankenPHP (or the messenger consumer for worker containers).
export APP_ENV="${APP_ENV:-prod}"

php bin/console cache:clear --no-warmup --no-interaction
# Warmup is best-effort: if it fails, Symfony still warms lazily on first use.
php bin/console cache:warmup --no-interaction || echo ">>> cache:warmup skipped"

exec "$@"
