-- Size of every index added in sql/05_indexes.sql next to the size of its table (Phase 4 report).
-- Run:  psql -d <db> -f benchmarks/index_sizes.sql
SELECT c.relname                                   AS index_name,
       t.relname                                   AS table_name,
       pg_size_pretty(pg_relation_size(c.oid))     AS index_size,
       pg_size_pretty(pg_relation_size(t.oid))     AS table_size,
       round(100.0 * pg_relation_size(c.oid) / pg_relation_size(t.oid)) AS pct_of_table
FROM pg_class c
JOIN pg_index i ON i.indexrelid = c.oid
JOIN pg_class t ON t.oid = i.indrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'spotify' AND c.relname LIKE 'ix\_%'
ORDER BY pg_relation_size(c.oid) DESC;

-- Total of all new indexes against the total of the tables
SELECT pg_size_pretty(sum(pg_relation_size(c.oid)))  AS all_new_indexes,
       (SELECT pg_size_pretty(sum(pg_relation_size(t.oid))) FROM pg_class t
         JOIN pg_namespace n ON n.oid = t.relnamespace WHERE n.nspname = 'spotify' AND t.relkind = 'r') AS all_tables
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'spotify' AND c.relname LIKE 'ix\_%' AND c.relkind = 'i';
