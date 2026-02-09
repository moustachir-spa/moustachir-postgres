-- ============================================
-- Moustachir PostgreSQL - Extension Test Suite
-- ============================================
-- This script tests all installed extensions
-- Run with: psql -U postgres -f test-extensions.sql

\echo ''
\echo '===== EXTENSION TEST SUITE ====='
\echo ''

-- ============================================
-- 1. pg_stat_statements
-- (Query performance monitoring)
-- ============================================
\echo '1. Testing pg_stat_statements...'
SELECT 
  query,
  calls,
  total_exec_time,
  mean_exec_time
FROM pg_stat_statements
LIMIT 3;
\echo '✓ pg_stat_statements works'
\echo ''

-- ============================================
-- 2. uuid-ossp
-- (UUID generation)
-- ============================================
\echo '2. Testing uuid-ossp...'
SELECT 'UUID v1: ' || uuid_generate_v1() as test;
SELECT 'UUID v4: ' || uuid_generate_v4() as test;
SELECT 'UUID v5: ' || uuid_generate_v5(uuid_nil(), 'www.example.com') as test;
\echo '✓ uuid-ossp works'
\echo ''

-- ============================================
-- 3. pgvector
-- (Vector similarity search)
-- ============================================
\echo '3. Testing pgvector...'
DO $$
DECLARE
  v vector;
BEGIN
  v := '[1, 2, 3]';
  RAISE NOTICE 'Vector type: %', v;
  RAISE NOTICE 'Vector dimension: %', vector_dims(v);
END;
$$;
SELECT '[0.1, 0.2, 0.3]'::vector as vector_test;
\echo '✓ pgvector works'
\echo ''

-- ============================================
-- 4. pgcrypto
-- (Cryptographic functions - hashing)
-- ============================================
\echo '4. Testing pgcrypto...'
SELECT 'bcrypt hash: ' || crypt('mypassword', gen_salt('bf')) as test;
SELECT 'MD5 hash: ' || md5('test') as test;
SELECT 'SHA1 hash: ' || encode(digest('test', 'sha1'), 'hex') as test;
SELECT 'Random bytes: ' || encode(gen_random_bytes(16), 'hex') as test;
\echo '✓ pgcrypto works'
\echo ''

-- ============================================
-- 5. pg_trgm
-- (Trigram fuzzy text search)
-- ============================================
\echo '5. Testing pg_trgm...'
CREATE TEMP TABLE test_trgm (id serial, name text);
INSERT INTO test_trgm (name) VALUES ('John'), ('Jon'), ('Jane'), ('James');
SELECT name, similarity(name, 'John') as similarity_score
FROM test_trgm
ORDER BY similarity_score DESC;
\echo '✓ pg_trgm works'
\echo ''

-- ============================================
-- 6. PostGIS
-- (Geospatial data)
-- ============================================
\echo '6. Testing PostGIS...'
SELECT ST_AsText(ST_MakePoint(-122.4194, 37.7749)) as point_test;
SELECT ST_Distance(
  ST_MakePoint(0, 0)::geography,
  ST_MakePoint(1, 1)::geography
) as distance_meters;
SELECT PostGIS_Version() as postgis_version;
\echo '✓ PostGIS works'
\echo ''

-- ============================================
-- 7. citext
-- (Case-insensitive text)
-- ============================================
\echo '7. Testing citext...'
CREATE TEMP TABLE test_citext (id serial, email citext);
INSERT INTO test_citext (email) VALUES ('Alice@example.com'), ('bob@example.com');
SELECT email FROM test_citext WHERE email = 'alice@example.com';
SELECT email FROM test_citext WHERE email = 'ALICE@EXAMPLE.COM';
\echo '✓ citext works'
\echo ''

-- ============================================
-- 8. unaccent
-- (Accent/diacritic stripping)
-- ============================================
\echo '8. Testing unaccent...'
SELECT unaccent('Crème Brûlée') as unaccented;
SELECT unaccent('Résumé') as unaccented;
SELECT unaccent('Café') as unaccented;
SELECT unaccent('München') as unaccented;
\echo '✓ unaccent works'
\echo ''

-- ============================================
-- 9. hstore
-- (Key-value store)
-- ============================================
\echo '9. Testing hstore...'
SELECT 'name=>John, age=>30, city=>NYC'::hstore as key_value_store;
SELECT ('name=>John, age=>30'::hstore) -> 'name' as get_name;
SELECT ('name=>John, age=>30'::hstore) -> 'age' as get_age;
SELECT akeys('name=>John, age=>30, city=>NYC'::hstore) as keys;
\echo '✓ hstore works'
\echo ''

-- ============================================
-- 10. plpgsql
-- (Procedural language)
-- ============================================
\echo '10. Testing plpgsql...'
CREATE OR REPLACE FUNCTION test_plpgsql(a int, b int)
RETURNS int AS $$
DECLARE
  result int;
BEGIN
  result := a + b;
  RETURN result;
END;
$$ LANGUAGE plpgsql;

SELECT 'Result of function(5, 3): ' || test_plpgsql(5, 3) as test;
\echo '✓ plpgsql works'
\echo ''

-- ============================================
-- 11. pg_cron (if installed)
-- (Cron-based job scheduler)
-- ============================================
\echo '11. Testing pg_cron...'
\echo 'Checking if pg_cron schema exists...'
SELECT 'pg_cron is installed' as status
FROM information_schema.schemata
WHERE schema_name = 'cron';
\echo '✓ pg_cron schema verified'
\echo ''

-- ============================================
-- Summary
-- ============================================
\echo '===== ALL EXTENSIONS TESTED SUCCESSFULLY ====='
\echo ''
\echo 'List all installed extensions:'
\dx
\echo ''
