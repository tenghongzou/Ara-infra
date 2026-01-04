#!/bin/bash
# Ara Platform - Backup Service Entrypoint
# Sets up cron job and starts cron daemon

set -e

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "=========================================="
log "Ara Platform Backup Service"
log "=========================================="

# Display configuration
log "Configuration:"
log "  Backup Directory: $BACKUP_DIR"
log "  Retention Days: $BACKUP_RETENTION_DAYS"
log "  Schedule: $BACKUP_SCHEDULE"
log "  PostgreSQL: $PGUSER@$PGHOST:$PGPORT/$PGDATABASE"
log "  Redis: $REDIS_HOST:$REDIS_PORT"
log "  S3 Enabled: $S3_ENABLED"
if [ "$S3_ENABLED" = "true" ]; then
    log "  S3 Bucket: $S3_BUCKET"
fi
log "  Timezone: $TZ"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"
chown backup:backup "$BACKUP_DIR"

# Export environment variables for cron
printenv | grep -E '^(BACKUP_|PG|REDIS_|S3_|AWS_|TZ)' > /etc/environment

# Create cron job
log "Setting up cron schedule: $BACKUP_SCHEDULE"
CRON_FILE=/etc/crontabs/backup

cat > "$CRON_FILE" << EOF
# Ara Platform Backup Schedule
# Run backup at specified schedule
$BACKUP_SCHEDULE /scripts/backup.sh all >> /var/log/backup/backup.log 2>&1

# Keep cron log rotated (weekly)
0 0 * * 0 find /var/log/backup -name "*.log" -mtime +7 -delete
EOF

# Set proper permissions for cron file
chmod 600 "$CRON_FILE"
chown backup:backup "$CRON_FILE"

# Create log file
touch /var/log/backup/backup.log
chown backup:backup /var/log/backup/backup.log

# Wait for dependencies to be ready
log "Waiting for PostgreSQL to be ready..."
max_retries=30
retry=0
while [ $retry -lt $max_retries ]; do
    if PGPASSWORD="$PGPASSWORD" pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" > /dev/null 2>&1; then
        log "PostgreSQL is ready!"
        break
    fi
    retry=$((retry + 1))
    log "Waiting for PostgreSQL... ($retry/$max_retries)"
    sleep 2
done

if [ $retry -eq $max_retries ]; then
    log "WARNING: PostgreSQL not ready after $max_retries attempts"
fi

log "Waiting for Redis to be ready..."
retry=0
while [ $retry -lt $max_retries ]; do
    if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping > /dev/null 2>&1; then
        log "Redis is ready!"
        break
    fi
    retry=$((retry + 1))
    log "Waiting for Redis... ($retry/$max_retries)"
    sleep 2
done

if [ $retry -eq $max_retries ]; then
    log "WARNING: Redis not ready after $max_retries attempts"
fi

# Run initial backup if BACKUP_ON_START is set
if [ "${BACKUP_ON_START:-false}" = "true" ]; then
    log "Running initial backup..."
    /scripts/backup.sh all || log "Initial backup failed (will retry on schedule)"
fi

log "=========================================="
log "Backup service started!"
log "Next backup: $(echo "$BACKUP_SCHEDULE" | awk '{print "At "$2":"$1" daily"}')"
log "Logs: /var/log/backup/backup.log"
log "=========================================="

# Start cron daemon in foreground
exec crond -f -l 2
