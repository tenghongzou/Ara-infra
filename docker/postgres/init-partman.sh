#!/bin/bash
# Initialize pg_partman extension on first database startup
# This script runs automatically when the data directory is empty

set -e

# Function to initialize pg_partman in a database
init_partman_in_db() {
    local db_name=$1
    echo "Initializing pg_partman extension in database: ${db_name}..."

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db_name" <<-EOSQL
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
            RAISE NOTICE 'pg_partman extension initialized successfully in ${db_name}';
        END
        \$\$;
EOSQL

    echo "pg_partman initialized in ${db_name}!"
}

# Initialize in main database (backend)
init_partman_in_db "$POSTGRES_DB"

# Initialize in chat database if it exists
CHAT_DB="${CHAT_POSTGRES_DB:-ara_chat}"
if psql -U "$POSTGRES_USER" -lqt | cut -d \| -f 1 | grep -qw "$CHAT_DB"; then
    init_partman_in_db "$CHAT_DB"
else
    echo "Chat database ${CHAT_DB} not found, skipping pg_partman initialization"
fi

echo "pg_partman extension initialized successfully!"
