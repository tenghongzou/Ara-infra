#!/bin/bash
# Ara Platform - Automated Backup Script
# Backs up PostgreSQL database and Redis data
# Usage: ./backup.sh [postgres|redis|all]

set -euo pipefail

# Configuration (can be overridden via environment variables)
BACKUP_DIR="${BACKUP_DIR:-/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE_DIR=$(date +%Y/%m/%d)

# PostgreSQL configuration
PGHOST="${PGHOST:-postgres}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-symfony}"
PGPASSWORD="${PGPASSWORD:-symfony}"
PGDATABASE="${PGDATABASE:-symfony}"

# Additional databases to backup (comma-separated)
BACKUP_ADDITIONAL_DBS="${BACKUP_ADDITIONAL_DBS:-}"

# Redis configuration
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"

# S3 configuration (optional)
S3_ENABLED="${S3_ENABLED:-false}"
S3_BUCKET="${S3_BUCKET:-}"
S3_PREFIX="${S3_PREFIX:-backups}"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Create backup directory structure
init_backup_dir() {
    local backup_path="$BACKUP_DIR/$DATE_DIR"
    mkdir -p "$backup_path/postgres"
    mkdir -p "$backup_path/redis"
    echo "$backup_path"
}

# PostgreSQL backup for a single database
backup_postgres_db() {
    local backup_path="$1"
    local db_name="$2"
    local backup_file="$backup_path/postgres/${db_name}_${TIMESTAMP}.dump"

    log "Starting PostgreSQL backup for database: $db_name..."

    export PGPASSWORD="$PGPASSWORD"

    # Full database backup with compression
    if pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db_name" \
        --format=custom \
        --compress=9 \
        --file="$backup_file" \
        --verbose 2>&1 | while read line; do log "  pg_dump: $line"; done; then

        log "PostgreSQL backup completed: $backup_file"

        # Calculate and log backup size
        local size=$(du -h "$backup_file" | cut -f1)
        log "Backup size: $size"

        # Create checksum
        sha256sum "$backup_file" > "$backup_file.sha256"
        log "Checksum created: $backup_file.sha256"

        # Upload to S3 if enabled
        if [ "$S3_ENABLED" = "true" ] && [ -n "$S3_BUCKET" ]; then
            upload_to_s3 "$backup_file" "postgres"
            upload_to_s3 "$backup_file.sha256" "postgres"
        fi

        return 0
    else
        log_error "PostgreSQL backup failed for database: $db_name!"
        return 1
    fi
}

# PostgreSQL backup (all configured databases)
backup_postgres() {
    local backup_path="$1"
    local exit_code=0

    log "Starting PostgreSQL backup..."

    # Backup primary database
    backup_postgres_db "$backup_path" "$PGDATABASE" || exit_code=1

    # Backup additional databases if configured
    if [ -n "$BACKUP_ADDITIONAL_DBS" ]; then
        IFS=',' read -ra DBS <<< "$BACKUP_ADDITIONAL_DBS"
        for db in "${DBS[@]}"; do
            db=$(echo "$db" | xargs)  # trim whitespace
            if [ -n "$db" ]; then
                backup_postgres_db "$backup_path" "$db" || exit_code=1
            fi
        done
    fi

    return $exit_code
}

# PostgreSQL partition-aware backup (for large deployments)
backup_postgres_partitions() {
    local backup_path="$1"
    local start_date="${2:-$(date -d '7 days ago' +%Y-%m-%d)}"
    local end_date="${3:-$(date +%Y-%m-%d)}"

    log "Starting partition-aware PostgreSQL backup ($start_date to $end_date)..."

    export PGPASSWORD="$PGPASSWORD"

    # Backup only recent partitions for messages table
    local partition_backup="$backup_path/postgres/partitions_${TIMESTAMP}.sql"

    # Get list of partitions in date range
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -c "
        SELECT tablename FROM pg_tables
        WHERE schemaname = 'public'
        AND tablename LIKE 'messages_p%'
        ORDER BY tablename DESC
        LIMIT 7;
    " | while read partition; do
        if [ -n "$partition" ]; then
            partition=$(echo "$partition" | xargs)  # trim whitespace
            log "  Backing up partition: $partition"
            pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
                --table="$partition" \
                --format=custom \
                --file="$backup_path/postgres/${partition}_${TIMESTAMP}.dump"
        fi
    done

    log "Partition backup completed"
}

# Redis backup
backup_redis() {
    local backup_path="$1"
    local backup_file="$backup_path/redis/dump_${TIMESTAMP}.rdb"

    log "Starting Redis backup..."

    # Trigger background save
    if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" BGSAVE; then
        log "Redis BGSAVE initiated, waiting for completion..."

        # Wait for BGSAVE to complete (max 5 minutes)
        local max_wait=300
        local waited=0
        while [ $waited -lt $max_wait ]; do
            local status=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LASTSAVE)
            sleep 2
            local new_status=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LASTSAVE)

            if [ "$status" != "$new_status" ]; then
                log "Redis BGSAVE completed"
                break
            fi

            waited=$((waited + 2))
        done

        if [ $waited -ge $max_wait ]; then
            log_error "Redis BGSAVE timeout after ${max_wait}s"
            return 1
        fi

        # Copy the RDB file from Redis container
        # Note: This assumes Redis volume is accessible or using redis-cli --rdb
        if redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --rdb "$backup_file" 2>/dev/null; then
            log "Redis backup saved: $backup_file"

            # Calculate and log backup size
            local size=$(du -h "$backup_file" | cut -f1)
            log "Backup size: $size"

            # Create checksum
            sha256sum "$backup_file" > "$backup_file.sha256"

            # Upload to S3 if enabled
            if [ "$S3_ENABLED" = "true" ] && [ -n "$S3_BUCKET" ]; then
                upload_to_s3 "$backup_file" "redis"
                upload_to_s3 "$backup_file.sha256" "redis"
            fi

            return 0
        else
            log "Redis --rdb not available, skipping RDB copy (data still saved on Redis server)"
            return 0
        fi
    else
        log_error "Redis BGSAVE failed!"
        return 1
    fi
}

# Upload to S3
upload_to_s3() {
    local file="$1"
    local prefix="$2"
    local s3_path="s3://$S3_BUCKET/$S3_PREFIX/$DATE_DIR/$prefix/$(basename $file)"

    log "Uploading to S3: $s3_path"

    if aws s3 cp "$file" "$s3_path" --quiet; then
        log "S3 upload completed: $s3_path"
    else
        log_error "S3 upload failed: $file"
        return 1
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up backups older than $BACKUP_RETENTION_DAYS days..."

    # Local cleanup
    find "$BACKUP_DIR" -type f -mtime +$BACKUP_RETENTION_DAYS -delete 2>/dev/null || true
    find "$BACKUP_DIR" -type d -empty -delete 2>/dev/null || true

    local deleted=$(find "$BACKUP_DIR" -type f -mtime +$BACKUP_RETENTION_DAYS 2>/dev/null | wc -l)
    log "Cleaned up $deleted old backup files"

    # S3 cleanup (if enabled)
    if [ "$S3_ENABLED" = "true" ] && [ -n "$S3_BUCKET" ]; then
        log "Cleaning up S3 backups older than $BACKUP_RETENTION_DAYS days..."
        local cutoff_date=$(date -d "$BACKUP_RETENTION_DAYS days ago" +%Y-%m-%d)
        # S3 lifecycle rules should handle this, but we can also use aws s3 rm
        log "S3 cleanup should be handled by S3 lifecycle rules"
    fi
}

# Generate backup report
generate_report() {
    local backup_path="$1"
    local report_file="$backup_path/backup_report_${TIMESTAMP}.txt"

    {
        echo "=================================="
        echo "Ara Platform Backup Report"
        echo "=================================="
        echo ""
        echo "Timestamp: $(date)"
        echo "Backup Path: $backup_path"
        echo ""
        echo "PostgreSQL Backups:"
        ls -lh "$backup_path/postgres/" 2>/dev/null || echo "  (none)"
        echo ""
        echo "Redis Backups:"
        ls -lh "$backup_path/redis/" 2>/dev/null || echo "  (none)"
        echo ""
        echo "Total Backup Size:"
        du -sh "$backup_path" 2>/dev/null || echo "  Unknown"
        echo ""
        echo "=================================="
    } > "$report_file"

    log "Report generated: $report_file"
    cat "$report_file"
}

# Main backup function
run_backup() {
    local backup_type="${1:-all}"
    local backup_path

    log "=========================================="
    log "Starting Ara Platform Backup"
    log "Backup type: $backup_type"
    log "=========================================="

    # Initialize backup directory
    backup_path=$(init_backup_dir)
    log "Backup directory: $backup_path"

    local exit_code=0

    case "$backup_type" in
        postgres)
            backup_postgres "$backup_path" || exit_code=1
            ;;
        redis)
            backup_redis "$backup_path" || exit_code=1
            ;;
        all)
            backup_postgres "$backup_path" || exit_code=1
            backup_redis "$backup_path" || exit_code=1
            ;;
        *)
            log_error "Unknown backup type: $backup_type"
            log "Usage: $0 [postgres|redis|all]"
            exit 1
            ;;
    esac

    # Cleanup old backups
    cleanup_old_backups

    # Generate report
    generate_report "$backup_path"

    if [ $exit_code -eq 0 ]; then
        log "=========================================="
        log "Backup completed successfully!"
        log "=========================================="
    else
        log_error "=========================================="
        log_error "Backup completed with errors!"
        log_error "=========================================="
    fi

    return $exit_code
}

# Run backup
run_backup "${1:-all}"
