#!/bin/bash
# Ara Platform - Database Restore Script
# Restores PostgreSQL database from backup
# Usage: ./restore.sh <backup_file.dump>

set -euo pipefail

# Configuration
PGHOST="${PGHOST:-postgres}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-symfony}"
PGPASSWORD="${PGPASSWORD:-symfony}"
PGDATABASE="${PGDATABASE:-symfony}"

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Verify checksum
verify_checksum() {
    local backup_file="$1"
    local checksum_file="${backup_file}.sha256"

    if [ -f "$checksum_file" ]; then
        log "Verifying backup checksum..."
        if sha256sum -c "$checksum_file"; then
            log "Checksum verification passed"
            return 0
        else
            log_error "Checksum verification failed!"
            return 1
        fi
    else
        log "No checksum file found, skipping verification"
        return 0
    fi
}

# Restore PostgreSQL
restore_postgres() {
    local backup_file="$1"

    if [ ! -f "$backup_file" ]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi

    log "=========================================="
    log "Starting PostgreSQL Restore"
    log "Backup file: $backup_file"
    log "Target database: $PGDATABASE@$PGHOST:$PGPORT"
    log "=========================================="

    # Verify checksum
    verify_checksum "$backup_file" || exit 1

    export PGPASSWORD="$PGPASSWORD"

    # Confirm restore
    log "WARNING: This will overwrite the current database!"
    log "Database: $PGDATABASE"
    read -p "Are you sure you want to continue? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        log "Restore cancelled by user"
        exit 0
    fi

    # Check if database exists
    if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -lqt | cut -d \| -f 1 | grep -qw "$PGDATABASE"; then
        log "Database exists, dropping and recreating..."

        # Terminate existing connections
        psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -c "
            SELECT pg_terminate_backend(pg_stat_activity.pid)
            FROM pg_stat_activity
            WHERE pg_stat_activity.datname = '$PGDATABASE'
            AND pid <> pg_backend_pid();
        " || true

        # Drop and recreate database
        psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -c "DROP DATABASE IF EXISTS $PGDATABASE;"
        psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -c "CREATE DATABASE $PGDATABASE OWNER $PGUSER;"
    fi

    # Create pg_partman extension (required before restore)
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "
        CREATE SCHEMA IF NOT EXISTS partman;
        CREATE EXTENSION IF NOT EXISTS pg_partman SCHEMA partman;
    " || log "pg_partman extension may already exist"

    # Restore database
    log "Restoring database from backup..."
    if pg_restore -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
        --verbose \
        --no-owner \
        --no-privileges \
        --clean \
        --if-exists \
        "$backup_file" 2>&1 | while read line; do log "  pg_restore: $line"; done; then

        log "Database restore completed successfully!"
    else
        # pg_restore may return non-zero even on warnings
        log "pg_restore completed (check output for any errors)"
    fi

    # Verify restore
    log "Verifying restored database..."
    local table_count=$(psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -t -c "
        SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = 'public';
    " | xargs)

    log "Restored $table_count tables"

    # Run pg_partman maintenance to ensure partitions are up to date
    log "Running pg_partman maintenance..."
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "
        SELECT partman.run_maintenance();
    " || log "pg_partman maintenance skipped (may not be configured)"

    log "=========================================="
    log "Restore completed!"
    log "=========================================="
}

# List available backups
list_backups() {
    local backup_dir="${BACKUP_DIR:-/backups}"

    log "Available backups in $backup_dir:"
    echo ""

    find "$backup_dir" -name "*.dump" -type f -printf "%T@ %Tc %p\n" 2>/dev/null | \
        sort -rn | \
        head -20 | \
        while read timestamp date file; do
            local size=$(du -h "$file" | cut -f1)
            echo "  $date  ($size)  $file"
        done

    echo ""
    log "To restore, run: $0 <backup_file.dump>"
}

# Main
main() {
    if [ $# -eq 0 ]; then
        list_backups
        exit 0
    fi

    case "$1" in
        --list|-l)
            list_backups
            ;;
        --help|-h)
            echo "Usage: $0 [options] <backup_file.dump>"
            echo ""
            echo "Options:"
            echo "  --list, -l    List available backups"
            echo "  --help, -h    Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 /backups/2026/01/05/postgres/db_20260105_020000.dump"
            echo "  $0 --list"
            ;;
        *)
            restore_postgres "$1"
            ;;
    esac
}

main "$@"
