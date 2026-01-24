# PostgreSQL with pg_partman extension for automatic partition management
# https://github.com/pgpartman/pg_partman

FROM postgres:17

LABEL maintainer="Ara Team"
LABEL description="PostgreSQL 17 with pg_partman extension for automatic partition management"

# Install pg_partman extension
# postgresql-17-partman is the official Debian package for pg_partman
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-17-partman \
    && rm -rf /var/lib/apt/lists/*

# Copy initialization scripts
# Scripts in /docker-entrypoint-initdb.d/ run on first container startup (empty data directory)
# Order: 00-init-databases.sh (create databases) -> 01-init-partman.sh (extensions)
COPY 00-init-databases.sh /docker-entrypoint-initdb.d/00-init-databases.sh
COPY init-partman.sh /docker-entrypoint-initdb.d/01-init-partman.sh

# Ensure scripts are executable
RUN chmod +x /docker-entrypoint-initdb.d/00-init-databases.sh \
    && chmod +x /docker-entrypoint-initdb.d/01-init-partman.sh
