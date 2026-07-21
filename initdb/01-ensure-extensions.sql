-- ============================================
-- Moustachir PostgreSQL — extension backfill helper
-- ============================================
-- Run this in EVERY existing database (including template1) after
-- swapping the docker image, so that:
--   1. extensions that exist but were never installed get installed
--   2. extensions whose default_version bumped get updated to the new
--      default (PostGIS 3.4 -> 3.5.7, pgvector 0.8.1 -> 0.8.5, etc.)
--   3. template1 propagates the up-to-date set to any FUTURE database
--      created in this cluster
--
-- Usage (one line per database, repeat for every db you care about):
--
--   psql -U postgres -d template1   < initdb/01-ensure-extensions.sql
--   psql -U postgres -d my_app_db   < initdb/01-ensure-extensions.sql
--   psql -U postgres -d postgres    < initdb/01-ensure-extensions.sql
--
-- Or via docker exec:
--
--   docker exec -i <container> psql -U postgres -d <db> \
--     < initdb/01-ensure-extensions.sql
--
-- Idempotent: safe to run multiple times. CREATE EXTENSION IF NOT EXISTS
-- is a no-op when the extension already exists at the requested version;
-- ALTER EXTENSION UPDATE brings it to the new default_version shipped
-- by this image when a newer one is available.
-- ============================================

-- contrib extensions shipped with PostgreSQL 18
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS hstore;

-- external extensions compiled from source in this image
CREATE EXTENSION IF NOT EXISTS vector;     -- pgvector 0.8.5
CREATE EXTENSION IF NOT EXISTS postgis;    -- PostGIS  3.5.7

-- bump any existing extension to the image's current default_version,
-- if a newer one is available. Safe no-op when already up to date.
ALTER EXTENSION pg_stat_statements UPDATE;
ALTER EXTENSION "uuid-ossp"       UPDATE;
ALTER EXTENSION pgcrypto          UPDATE;
ALTER EXTENSION pg_trgm           UPDATE;
ALTER EXTENSION citext            UPDATE;
ALTER EXTENSION unaccent          UPDATE;
ALTER EXTENSION hstore            UPDATE;
ALTER EXTENSION vector            UPDATE;  -- 0.8.1 -> 0.8.5
ALTER EXTENSION postgis           UPDATE;  -- 3.4.x -> 3.5.7
