-- Database size, and table against index size for every table (Phase 5 storage section).
-- Run on the seed and on the large database:
--   psql -d spotify_db    -f benchmarks/db_sizes.sql > benchmarks/results/large/db_sizes_seed.txt
--   psql -d spotify_large -f benchmarks/db_sizes.sql > benchmarks/results/large/db_sizes_large.txt
SELECT current_database() AS database, pg_size_pretty(pg_database_size(current_database())) AS total_size;

SELECT c.relname                                            AS table_name,
       c.reltuples::bigint                                  AS rows,
       pg_size_pretty(pg_table_size(c.oid))                 AS table_size,
       pg_size_pretty(pg_indexes_size(c.oid))               AS index_size,
       pg_size_pretty(pg_total_relation_size(c.oid))        AS total_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'spotify' AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;

SELECT pg_size_pretty(sum(pg_table_size(c.oid)))   AS all_tables,
       pg_size_pretty(sum(pg_indexes_size(c.oid))) AS all_indexes,
       sum(pg_table_size(c.oid))                   AS all_tables_bytes,
       sum(pg_indexes_size(c.oid))                 AS all_indexes_bytes
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'spotify' AND c.relkind = 'r';
