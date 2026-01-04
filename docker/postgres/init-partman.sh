#!/bin/bash
# Initialize pg_partman extension on first database startup
# This script runs automatically when the data directory is empty

set -e

echo "Initializing pg_partman extension..."

# Create pg_partman extension in the default database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create pg_partman schema if not exists
    CREATE SCHEMA IF NOT EXISTS partman;

    -- Create pg_partman extension
    CREATE EXTENSION IF NOT EXISTS pg_partman SCHEMA partman;

    -- Grant usage to public for convenience
    GRANT USAGE ON SCHEMA partman TO PUBLIC;
    GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA partman TO PUBLIC;

    -- Log success
    DO \$\$
    BEGIN
        RAISE NOTICE 'pg_partman extension initialized successfully';
    END
    \$\$;
EOSQL

echo "pg_partman extension initialized successfully!"
