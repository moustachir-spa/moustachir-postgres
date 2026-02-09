#!/bin/bash
set -e

##############################################
# Moustachir PostgreSQL - Extension Installer
#
# This script runs on first container start.
# It installs all extensions in template1
# (so every new database inherits them) and
# in the default database.
#
# Extensions installed:
#   - pg_stat_statements  (query performance monitoring)
#   - uuid-ossp           (UUID generation)
#   - pgvector / vector   (vector similarity search)
#   - pgcrypto            (cryptographic functions)
#   - pg_trgm             (trigram fuzzy text search)
#   - PostGIS             (geospatial data)
#   - citext              (case-insensitive text)
#   - unaccent            (accent-stripping text search)
#   - hstore              (key-value store)
##############################################

echo "==> Installing extensions in template1 (inherited by all new databases)..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname template1 <<-EOSQL

    -- Contrib extensions (shipped with PostgreSQL)
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    CREATE EXTENSION IF NOT EXISTS citext;
    CREATE EXTENSION IF NOT EXISTS unaccent;
    CREATE EXTENSION IF NOT EXISTS hstore;

    -- External extensions (compiled from source / installed via apt)
    CREATE EXTENSION IF NOT EXISTS vector;
    CREATE EXTENSION IF NOT EXISTS postgis;

EOSQL

echo "==> Installing extensions in '${POSTGRES_DB:-postgres}' database..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "${POSTGRES_DB:-postgres}" <<-EOSQL

    -- Contrib extensions
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    CREATE EXTENSION IF NOT EXISTS citext;
    CREATE EXTENSION IF NOT EXISTS unaccent;
    CREATE EXTENSION IF NOT EXISTS hstore;

    -- External extensions
    CREATE EXTENSION IF NOT EXISTS vector;
    CREATE EXTENSION IF NOT EXISTS postgis;

EOSQL

echo "==> All extensions installed successfully!"
echo ""
echo "  Installed in template1 (inherited by new databases):"
echo "    pg_stat_statements, uuid-ossp, pgcrypto, pg_trgm,"
echo "    citext, unaccent, hstore, vector (pgvector), postgis"
echo ""
