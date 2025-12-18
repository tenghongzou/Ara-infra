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
    zip \
    opcache

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

# Caddyfile
COPY docker/caddy/Caddyfile /etc/caddy/Caddyfile

WORKDIR /app

ENV FRANKENPHP_CONFIG="worker ./public/index.php"

EXPOSE 80 443
