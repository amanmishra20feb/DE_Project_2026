-- Spotify DBMS Project, team T0028: partitioning design for streams (Phase 5).
-- Builds spotify_part.streams, a copy of spotify.streams partitioned by RANGE (started_at) with one partition per month,
-- and runs a few queries on both. Because the copy has the same name in its own schema, the queries are the same text:
-- only the search_path changes. The real streams table is not changed, and the copy is dropped at the end, so the
-- database stays exactly as it was benchmarked.
-- Run on the large database and keep the output (notices and the expected error included):
--   psql -d spotify_large -f sql/08_partitioning.sql > benchmarks/results/large/partitioning.txt 2>&1

\set ON_ERROR_STOP on
SET search_path TO spotify;
\pset pager off
DROP SCHEMA IF EXISTS spotify_part CASCADE;
CREATE SCHEMA spotify_part;

-- Primary-key rule: on a partitioned table a PRIMARY KEY or UNIQUE constraint must include the partition key.
-- streams has PRIMARY KEY (stream_id), so this first attempt fails on purpose:
\qecho '=== Primary key without the partition key (expected to fail) ==='
\set ON_ERROR_STOP off
CREATE TABLE spotify_part.pk_test (
    stream_id  BIGINT      PRIMARY KEY,
    started_at TIMESTAMPTZ NOT NULL
) PARTITION BY RANGE (started_at);
\set ON_ERROR_STOP on

-- So the key becomes (stream_id, started_at). Uniqueness of stream_id alone is then no longer enforced by the database;
-- the identity column still hands out unique values, but a manually inserted duplicate id in another month would pass.
CREATE TABLE spotify_part.streams (
    stream_id   BIGINT      NOT NULL,
    user_id     INTEGER,
    track_id    INTEGER     NOT NULL,
    started_at  TIMESTAMPTZ NOT NULL,
    ms_played   INTEGER     NOT NULL,
    platform    VARCHAR(7)  NOT NULL,
    source_type VARCHAR(8)  NOT NULL,
    playlist_id INTEGER,
    skipped     BOOLEAN     NOT NULL,
    offline     BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_streams_part PRIMARY KEY (stream_id, started_at),
    CONSTRAINT ck_streams_part_ms_played CHECK (ms_played BETWEEN 0 AND 3600000),
    CONSTRAINT ck_streams_part_platform CHECK (platform IN ('ANDROID', 'IOS', 'WEB', 'DESKTOP', 'CAR', 'SPEAKER')),
    CONSTRAINT ck_streams_part_source_type CHECK (source_type IN ('PLAYLIST', 'ALBUM', 'ARTIST', 'RADIO', 'SEARCH')),
    CONSTRAINT ck_streams_part_playlist_only CHECK (source_type = 'PLAYLIST' OR playlist_id IS NULL),
    CONSTRAINT ck_streams_part_skipped_rule CHECK (skipped = (ms_played < 30000))
) PARTITION BY RANGE (started_at);

-- One partition per calendar month in India time (the data runs from Jan 2025 to Jun 2026), plus a DEFAULT partition
-- that catches any row outside these months instead of rejecting it. New months are added ahead of time by the same
-- statement; an old month can be detached and archived in one step (ALTER TABLE ... DETACH PARTITION).
DO $$
DECLARE
    m date;
BEGIN
    FOR m IN SELECT generate_series(date '2025-01-01', date '2026-06-01', interval '1 month')::date LOOP
        EXECUTE format('CREATE TABLE spotify_part.%I PARTITION OF spotify_part.streams FOR VALUES FROM (%L) TO (%L)',
                       'streams_' || to_char(m, 'YYYY_MM'),
                       m::text || ' 00:00:00+05:30',
                       (m + interval '1 month')::date::text || ' 00:00:00+05:30');
    END LOOP;
END $$;
CREATE TABLE spotify_part.streams_default PARTITION OF spotify_part.streams DEFAULT;

INSERT INTO spotify_part.streams SELECT * FROM spotify.streams;

-- The foreign keys are added after the copy: one check of all rows is much faster than one check per inserted row.
ALTER TABLE spotify_part.streams
    ADD CONSTRAINT fk_streams_part_user FOREIGN KEY (user_id) REFERENCES users (user_id) ON DELETE SET NULL,
    ADD CONSTRAINT fk_streams_part_track FOREIGN KEY (track_id) REFERENCES tracks (track_id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_streams_part_playlist FOREIGN KEY (playlist_id) REFERENCES playlists (playlist_id) ON DELETE SET NULL;

-- The same streams indexes as sql/05_indexes.sql; an index on the parent is created on every partition.
CREATE INDEX ix_streams_part_started_cov ON spotify_part.streams (started_at) INCLUDE (stream_id, user_id, track_id, ms_played, platform);
CREATE INDEX ix_streams_part_user_time ON spotify_part.streams (user_id, started_at DESC);
CREATE INDEX ix_streams_part_track_time ON spotify_part.streams (track_id, started_at) INCLUDE (skipped);
CREATE INDEX ix_streams_part_playlist ON spotify_part.streams (playlist_id) WHERE playlist_id IS NOT NULL;
VACUUM (ANALYZE) spotify_part.streams;

\qecho '=== Partitions: rows and size ==='
SELECT c.relname AS partition,
       pg_get_expr(c.relpartbound, c.oid) AS bounds,
       c.reltuples::bigint AS rows,
       pg_size_pretty(pg_relation_size(c.oid)) AS table_size,
       pg_size_pretty(pg_indexes_size(c.oid)) AS index_size
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'spotify_part.streams'::regclass
ORDER BY c.relname;

SELECT pg_size_pretty(sum(pg_relation_size(i.inhrelid))) AS partitioned_tables,
       pg_size_pretty(pg_relation_size('spotify.streams')) AS plain_table
FROM pg_inherits i WHERE i.inhparent = 'spotify_part.streams'::regclass;

-- Partition pruning: the planner keeps only the partitions whose range overlaps the WHERE clause.
\qecho '=== Pruning: R10 (June 2026 only) ==='
EXPLAIN (COSTS OFF)
SELECT started_at::date AS day, platform, count(*) AS streams
FROM spotify_part.streams
WHERE started_at >= '2026-06-01' AND started_at < '2026-07-01'
GROUP BY 1, 2
ORDER BY 1, 2;

\qecho '=== No pruning: R04 (one user, no date in the WHERE clause) ==='
EXPLAIN (COSTS OFF)
SELECT s.started_at, t.title, s.ms_played, s.platform
FROM spotify_part.streams s
JOIN tracks t ON t.track_id = s.track_id
WHERE s.user_id = 1038
ORDER BY s.started_at DESC
LIMIT 50;

-- Timings, 3 runs each, on the plain table and on the partitioned copy (same text as in sql/06_optimized_queries.sql).
\set q_r10 'SELECT started_at::date AS day, platform, count(*) AS streams FROM streams WHERE started_at >= ''2026-06-01'' AND started_at < ''2026-07-01'' GROUP BY 1, 2 ORDER BY 1, 2'
\set q_r07 'SELECT ta.artist_id, count(*) AS eligible_streams FROM streams s JOIN track_artists ta ON ta.track_id = s.track_id WHERE s.ms_played >= 30000 AND s.started_at >= ''2026-06-01'' AND s.started_at < ''2026-07-01'' GROUP BY ta.artist_id ORDER BY eligible_streams DESC LIMIT 20'
\set q_r16 'SELECT ta.artist_id, count(DISTINCT s.user_id) AS listeners FROM streams s JOIN track_artists ta ON ta.track_id = s.track_id WHERE s.started_at >= ''2026-06-03'' GROUP BY ta.artist_id ORDER BY listeners DESC'
\set q_r04 'SELECT s.started_at, t.title, s.ms_played, s.platform FROM streams s JOIN tracks t ON t.track_id = s.track_id WHERE s.user_id = 1038 ORDER BY s.started_at DESC LIMIT 50'
\set q_r18 'SELECT platform, count(*) AS streams, round(100.0 * count(*) FILTER (WHERE offline) / count(*), 1) AS offline_pct FROM streams GROUP BY platform ORDER BY streams DESC'

SET search_path TO spotify;
\qecho '=== R10 on streams ==='
EXPLAIN (ANALYZE, BUFFERS) :q_r10;
EXPLAIN (ANALYZE, BUFFERS) :q_r10;
EXPLAIN (ANALYZE, BUFFERS) :q_r10;
\qecho '=== R07 on streams ==='
EXPLAIN (ANALYZE, BUFFERS) :q_r07;
EXPLAIN (ANALYZE, BUFFERS) :q_r07;
EXPLAIN (ANALYZE, BUFFERS) :q_r07;
\qecho '=== R16 on streams ==='
EXPLAIN (ANALYZE, BUFFERS) :q_r16;
EXPLAIN (ANALYZE, BUFFERS) :q_r16;
EXPLAIN (ANALYZE, BUFFERS) :q_r16;
\qecho '=== R04 on streams ==='
EXPLAIN (ANALYZE, BUFFERS) :q_r04;
EXPLAIN (ANALYZE, BUFFERS) :q_r04;
EXPLAIN (ANALYZE, BUFFERS) :q_r04;
\qecho '=== R18 on streams ==='
EXPLAIN (ANALYZE, BUFFERS) :q_r18;
EXPLAIN (ANALYZE, BUFFERS) :q_r18;
EXPLAIN (ANALYZE, BUFFERS) :q_r18;

SET search_path TO spotify_part, spotify;
\qecho '=== R10 on streams_part ==='
EXPLAIN (ANALYZE, BUFFERS) :q_r10;
EXPLAIN (ANALYZE, BUFFERS) :q_r10;
EXPLAIN (ANALYZE, BUFFERS) :q_r10;
\qecho '=== R07 on streams_part ==='
EXPLAIN (ANALYZE, BUFFERS) :q_r07;
EXPLAIN (ANALYZE, BUFFERS) :q_r07;
EXPLAIN (ANALYZE, BUFFERS) :q_r07;
\qecho '=== R16 on streams_part ==='
EXPLAIN (ANALYZE, BUFFERS) :q_r16;
EXPLAIN (ANALYZE, BUFFERS) :q_r16;
EXPLAIN (ANALYZE, BUFFERS) :q_r16;
\qecho '=== R04 on streams_part ==='
EXPLAIN (ANALYZE, BUFFERS) :q_r04;
EXPLAIN (ANALYZE, BUFFERS) :q_r04;
EXPLAIN (ANALYZE, BUFFERS) :q_r04;
\qecho '=== R18 on streams_part ==='
EXPLAIN (ANALYZE, BUFFERS) :q_r18;
EXPLAIN (ANALYZE, BUFFERS) :q_r18;
EXPLAIN (ANALYZE, BUFFERS) :q_r18;

DROP SCHEMA spotify_part CASCADE;
\qecho '=== spotify_part dropped; spotify.streams is unchanged ==='
