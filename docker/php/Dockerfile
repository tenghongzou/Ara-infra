FROM dunglas/frankenphp

RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libpq-dev \
    libicu-dev \
    libzip-dev \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions
RUN docker-php-ext-install \
    pdo \
    pdo_pgsql \
    intl \
    zip

# Redis
RUN pecl install redis \
    && docker-php-ext-enable redis

# Xdebug
RUN pecl install xdebug \
    && docker-php-ext-enable xdebug

# Xdebug config
RUN echo "xdebug.mode=debug,develop" >> /usr/local/etc/php/conf.d/docker-xdebug.ini \
 && echo "xdebug.start_with_request=yes" >> /usr/local/etc/php/conf.d/docker-xdebug.ini \
 && echo "xdebug.client_host=host.docker.internal" >> /usr/local/etc/php/conf.d/docker-xdebug.ini \
 && echo "xdebug.client_port=9003" >> /usr/local/etc/php/conf.d/docker-xdebug.ini \
 && echo "xdebug.log_level=0" >> /usr/local/etc/php/conf.d/docker-xdebug.ini

# 安裝 Composer（官方推薦方式）
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

# 先複製 composer 檔案（利用 Docker cache）
COPY backend/composer.json backend/composer.lock ./

# 安裝依賴（開發環境）
RUN composer install \
    --prefer-dist \
    --no-interaction \
    --no-scripts

# 再複製其餘專案檔案
COPY backend/ .

# Caddyfile
COPY docker/caddy/Caddyfile /etc/frankenphp/Caddyfile

# Entrypoint script for auto composer install
COPY docker/php/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV FRANKENPHP_CONFIG="worker /app/public/index.php"

EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["frankenphp", "run", "--config", "/etc/frankenphp/Caddyfile"]
