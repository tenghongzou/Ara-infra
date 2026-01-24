#!/bin/bash
# Initialize multiple databases on first startup
# This script runs before other init scripts (00- prefix)

set -e

echo "Initializing additional databases..."

# Create ara_chat database for Chat service
# Uses CHAT_POSTGRES_DB environment variable, defaults to ara_chat
CHAT_DB="${CHAT_POSTGRES_DB:-ara_chat}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create chat database if not exists
    SELECT 'CREATE DATABASE ${CHAT_DB}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${CHAT_DB}')\gexec

    -- Grant privileges to the main user
    GRANT ALL PRIVILEGES ON DATABASE ${CHAT_DB} TO ${POSTGRES_USER};

    DO \$\$
    BEGIN
        RAISE NOTICE 'Database ${CHAT_DB} initialized successfully';
    END
    \$\$;
EOSQL

echo "Additional databases initialized successfully!"
