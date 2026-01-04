# Ara Platform - Backup Service
# Automated backup container with cron scheduling

FROM alpine:3.19

LABEL maintainer="Ara Team"
LABEL description="Automated backup service for PostgreSQL and Redis"

# Install required packages
RUN apk add --no-cache \
    bash \
    postgresql17-client \
    redis \
    aws-cli \
    curl \
    tzdata \
    dcron \
    && rm -rf /var/cache/apk/*

# Create backup user
RUN addgroup -g 1000 backup && \
    adduser -u 1000 -G backup -h /home/backup -D backup

# Create directories
RUN mkdir -p /backups /scripts /var/log/backup && \
    chown -R backup:backup /backups /scripts /var/log/backup

# Copy scripts
COPY --chown=backup:backup backup.sh /scripts/backup.sh
COPY --chown=backup:backup restore.sh /scripts/restore.sh
COPY --chown=backup:backup entrypoint.sh /scripts/entrypoint.sh

# Make scripts executable
RUN chmod +x /scripts/*.sh

# Set timezone (configurable via TZ environment variable)
ENV TZ=UTC

# Default environment variables
ENV BACKUP_DIR=/backups \
    BACKUP_RETENTION_DAYS=7 \
    BACKUP_SCHEDULE="0 2 * * *" \
    PGHOST=postgres \
    PGPORT=5432 \
    PGUSER=symfony \
    PGDATABASE=symfony \
    REDIS_HOST=redis \
    REDIS_PORT=6379 \
    S3_ENABLED=false

# Volume for backup storage
VOLUME ["/backups"]

# Health check - verify cron is running
HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD pgrep -x crond > /dev/null || exit 1

# Entrypoint
ENTRYPOINT ["/scripts/entrypoint.sh"]
