# Multi-stage build for the Symfony/FrankenPHP backend.
#
#   dev  (default) — Xdebug + full deps; source is bind-mounted over /app by
#                    docker-compose, so this is what `docker compose up` builds.
#   prod           — no Xdebug, prod-only deps, optimized autoloader, prod ini;
#                    code + vendor baked in, no bind mount, no runtime composer.
#                    Selected by docker-compose.prod.yml via `build.target: prod`.

# ---------------------------------------------------------------------------
# Shared base: runtime, PHP extensions, composer, Caddyfile.
# ---------------------------------------------------------------------------
FROM dunglas/frankenphp AS base

RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libpq-dev \
    libicu-dev \
    libzip-dev \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-install \
    pdo \
    pdo_pgsql \
    intl \
    zip \
    bcmath

RUN pecl install redis \
    && docker-php-ext-enable redis

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# Caddyfile (routes the microservices + Symfony)
COPY docker/caddy/Caddyfile /etc/frankenphp/Caddyfile

ENV FRANKENPHP_CONFIG="worker /app/public/index.php"

EXPOSE 80 443

# ---------------------------------------------------------------------------
# Production image.
# ---------------------------------------------------------------------------
FROM base AS prod

# Production PHP settings (display_errors off, OPcache tuned for immutable code)
COPY docker/php/php.prod.ini /usr/local/etc/php/conf.d/zz-app-prod.ini

# Install prod dependencies against the lockfile first (better layer caching)
COPY backend/composer.json backend/composer.lock ./
RUN composer install \
    --no-dev \
    --prefer-dist \
    --no-interaction \
    --no-scripts \
    --no-autoloader

# Bake the application code and build an optimized, authoritative autoloader
COPY backend/ .
RUN composer dump-autoload --no-dev --optimize --classmap-authoritative

COPY docker/php/entrypoint.prod.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile"]

# ---------------------------------------------------------------------------
# Development image (default target).
# ---------------------------------------------------------------------------
FROM base AS dev

# Xdebug (kept out of the prod image)
RUN pecl install xdebug \
    && docker-php-ext-enable xdebug
RUN echo "xdebug.mode=debug,develop" >> /usr/local/etc/php/conf.d/docker-xdebug.ini \
 && echo "xdebug.start_with_request=yes" >> /usr/local/etc/php/conf.d/docker-xdebug.ini \
 && echo "xdebug.client_host=host.docker.internal" >> /usr/local/etc/php/conf.d/docker-xdebug.ini \
 && echo "xdebug.client_port=9003" >> /usr/local/etc/php/conf.d/docker-xdebug.ini \
 && echo "xdebug.log_level=0" >> /usr/local/etc/php/conf.d/docker-xdebug.ini

# Install dependencies (full, incl. dev) — cache on composer files first
COPY backend/composer.json backend/composer.lock ./
RUN composer install \
    --prefer-dist \
    --no-interaction \
    --no-scripts

# Baked copy is a fallback; docker-compose bind-mounts ./backend over /app
COPY backend/ .

# Entrypoint runs composer install at start if vendor/ is missing (bind mount)
COPY docker/php/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile"]
