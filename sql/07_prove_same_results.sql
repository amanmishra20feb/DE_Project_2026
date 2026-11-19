-- Proof that the optimized queries return the same rows as the originals (Phase 4, step 3).
-- Run after sql/05_indexes.sql:  psql -d <db> -f sql/07_prove_same_results.sql
-- For each changed query: rows_before / rows_after, and how many rows are in one result but not in the other (EXCEPT).
-- "same" is true when the counts are equal and both EXCEPT counts are 0.
-- R13 is the exception on purpose: the original is wrong (NOT IN with NULLs returns 0 rows), see the note at R13.

SET search_path TO spotify;
SHOW TimeZone;

\echo R03
WITH o AS (
SELECT track_id, title, popularity
FROM tracks
WHERE title ILIKE '%love%'
ORDER BY popularity DESC
LIMIT 20
), n AS (
SELECT track_id, title, popularity
FROM tracks
WHERE title ILIKE '%love%'
ORDER BY popularity DESC, track_id
LIMIT 20
)
SELECT 'R03' AS query,
       (SELECT count(*) FROM o) AS rows_before,
       (SELECT count(*) FROM n) AS rows_after,
       (SELECT count(*) FROM (SELECT * FROM o EXCEPT SELECT * FROM n) x) AS only_before,
       (SELECT count(*) FROM (SELECT * FROM n EXCEPT SELECT * FROM o) x) AS only_after,
       (SELECT count(*) FROM o) = (SELECT count(*) FROM n) AND NOT EXISTS (SELECT * FROM o EXCEPT SELECT * FROM n) AND NOT EXISTS (SELECT * FROM n EXCEPT SELECT * FROM o) AS same;

\echo R09
WITH o AS (
SELECT ta.artist_id, ar.artist_name, round(sum(s.ms_played) / 60000.0, 1) AS minutes
FROM streams s
JOIN track_artists ta ON ta.track_id = s.track_id AND ta.role = 'PRIMARY'
JOIN artists ar       ON ar.artist_id = ta.artist_id
WHERE s.user_id = 1038
  AND EXTRACT(YEAR FROM s.started_at) = 2025
GROUP BY ta.artist_id, ar.artist_name
ORDER BY minutes DESC
LIMIT 5
), n AS (
SELECT ta.artist_id, ar.artist_name, round(sum(s.ms_played) / 60000.0, 1) AS minutes
FROM streams s
JOIN track_artists ta ON ta.track_id = s.track_id AND ta.role = 'PRIMARY'
JOIN artists ar       ON ar.artist_id = ta.artist_id
WHERE s.user_id = 1038
  AND s.started_at >= '2025-01-01' AND s.started_at < '2026-01-01'
GROUP BY ta.artist_id, ar.artist_name
ORDER BY minutes DESC
LIMIT 5
)
SELECT 'R09' AS query,
       (SELECT count(*) FROM o) AS rows_before,
       (SELECT count(*) FROM n) AS rows_after,
       (SELECT count(*) FROM (SELECT * FROM o EXCEPT SELECT * FROM n) x) AS only_before,
       (SELECT count(*) FROM (SELECT * FROM n EXCEPT SELECT * FROM o) x) AS only_after,
       (SELECT count(*) FROM o) = (SELECT count(*) FROM n) AND NOT EXISTS (SELECT * FROM o EXCEPT SELECT * FROM n) AND NOT EXISTS (SELECT * FROM n EXCEPT SELECT * FROM o) AS same;

\echo R10
WITH o AS (
SELECT started_at::date AS day, platform, count(*) AS streams
FROM streams
WHERE started_at::date BETWEEN '2026-06-01' AND '2026-06-30'
GROUP BY 1, 2
ORDER BY 1, 2
), n AS (
SELECT started_at::date AS day, platform, count(*) AS streams
FROM streams
WHERE started_at >= '2026-06-01' AND started_at < '2026-07-01'
GROUP BY 1, 2
ORDER BY 1, 2
)
SELECT 'R10' AS query,
       (SELECT count(*) FROM o) AS rows_before,
       (SELECT count(*) FROM n) AS rows_after,
       (SELECT count(*) FROM (SELECT * FROM o EXCEPT SELECT * FROM n) x) AS only_before,
       (SELECT count(*) FROM (SELECT * FROM n EXCEPT SELECT * FROM o) x) AS only_after,
       (SELECT count(*) FROM o) = (SELECT count(*) FROM n) AND NOT EXISTS (SELECT * FROM o EXCEPT SELECT * FROM n) AND NOT EXISTS (SELECT * FROM n EXCEPT SELECT * FROM o) AS same;

\echo R13
-- R13 is corrected, not just made faster: before = 0 rows (wrong), after = the public playlists that were never played.
-- The new result is also compared with a third form of the query (LEFT JOIN ... IS NULL, an anti-join), which is
-- written differently from NOT EXISTS, so rows_after must equal it. (Check B6 in sql/03_integrity_checks.sql counts the
-- same 1,891; B6 is also written with NOT EXISTS, so the anti-join is the independent comparison.)
WITH o AS (
SELECT p.playlist_id, p.name, p.owner_user_id
FROM playlists p
WHERE p.is_public
  AND p.playlist_id NOT IN (SELECT s.playlist_id FROM streams s)
), n AS (
SELECT p.playlist_id, p.name, p.owner_user_id
FROM playlists p
WHERE p.is_public
  AND NOT EXISTS (SELECT 1 FROM streams s WHERE s.playlist_id = p.playlist_id)
)
SELECT 'R13' AS query,
       (SELECT count(*) FROM o) AS rows_before,
       (SELECT count(*) FROM n) AS rows_after,
       (SELECT count(*) FROM (SELECT * FROM o EXCEPT SELECT * FROM n) x) AS only_before,
       (SELECT count(*) FROM (SELECT * FROM n EXCEPT SELECT * FROM o) x) AS only_after,
       (SELECT count(*) FROM n) = (SELECT count(*) FROM (
            SELECT p.playlist_id FROM playlists p
            LEFT JOIN streams s ON s.playlist_id = p.playlist_id
            WHERE p.is_public AND s.stream_id IS NULL) aj)
       AND NOT EXISTS (SELECT n.playlist_id FROM n EXCEPT
            SELECT p.playlist_id FROM playlists p LEFT JOIN streams s ON s.playlist_id = p.playlist_id
            WHERE p.is_public AND s.stream_id IS NULL)
       AND NOT EXISTS (SELECT p.playlist_id FROM playlists p LEFT JOIN streams s ON s.playlist_id = p.playlist_id
            WHERE p.is_public AND s.stream_id IS NULL EXCEPT SELECT n.playlist_id FROM n) AS equals_anti_join;

\echo R19
WITH o AS (
SELECT ar.artist_id, ar.artist_name,
       (SELECT count(*) FROM streams s JOIN track_artists ta ON ta.track_id = s.track_id
         WHERE ta.artist_id = ar.artist_id) AS total_streams,
       (SELECT max(s.started_at) FROM streams s JOIN track_artists ta ON ta.track_id = s.track_id
         WHERE ta.artist_id = ar.artist_id) AS last_streamed_at
FROM artists ar
WHERE ar.is_verified
ORDER BY total_streams DESC
), n AS (
SELECT ar.artist_id, ar.artist_name,
       count(s.track_id)  AS total_streams,
       max(s.started_at)  AS last_streamed_at
FROM artists ar
LEFT JOIN track_artists ta ON ta.artist_id = ar.artist_id
LEFT JOIN streams s        ON s.track_id = ta.track_id
WHERE ar.is_verified
GROUP BY ar.artist_id, ar.artist_name
ORDER BY total_streams DESC
)
SELECT 'R19' AS query,
       (SELECT count(*) FROM o) AS rows_before,
       (SELECT count(*) FROM n) AS rows_after,
       (SELECT count(*) FROM (SELECT * FROM o EXCEPT SELECT * FROM n) x) AS only_before,
       (SELECT count(*) FROM (SELECT * FROM n EXCEPT SELECT * FROM o) x) AS only_after,
       (SELECT count(*) FROM o) = (SELECT count(*) FROM n) AND NOT EXISTS (SELECT * FROM o EXCEPT SELECT * FROM n) AND NOT EXISTS (SELECT * FROM n EXCEPT SELECT * FROM o) AS same;

\echo W04
-- W04 updates every artist. First compare the numbers each version computes, then the table after each UPDATE.
WITH o AS (
  SELECT ar.artist_id, coalesce(s.n, 0) AS n
  FROM artists ar
  JOIN (SELECT a.artist_id, count(DISTINCT st.user_id) AS n
        FROM artists a
        LEFT JOIN track_artists ta ON ta.artist_id = a.artist_id
        LEFT JOIN streams st ON st.track_id = ta.track_id AND st.started_at >= '2026-06-03'
        GROUP BY a.artist_id) s ON s.artist_id = ar.artist_id
), n AS (
  SELECT a.artist_id, coalesce(x.n, 0) AS n
  FROM artists a
  LEFT JOIN (SELECT ta.artist_id, count(DISTINCT st.user_id) AS n
             FROM streams st
             JOIN track_artists ta ON ta.track_id = st.track_id
             WHERE st.started_at >= '2026-06-03'
             GROUP BY ta.artist_id) x ON x.artist_id = a.artist_id
)
SELECT 'W04 computed values' AS query,
       (SELECT count(*) FROM o) AS rows_before, (SELECT count(*) FROM n) AS rows_after,
       (SELECT count(*) FROM (SELECT * FROM o EXCEPT SELECT * FROM n) x) AS only_before,
       (SELECT count(*) FROM (SELECT * FROM n EXCEPT SELECT * FROM o) x) AS only_after,
       NOT EXISTS (SELECT * FROM o EXCEPT SELECT * FROM n) AND NOT EXISTS (SELECT * FROM n EXCEPT SELECT * FROM o) AS same;

BEGIN;
UPDATE artists ar
SET monthly_listeners = coalesce(s.n, 0)
FROM (SELECT a.artist_id, count(DISTINCT st.user_id) AS n
      FROM artists a
      LEFT JOIN track_artists ta ON ta.artist_id = a.artist_id
      LEFT JOIN streams st ON st.track_id = ta.track_id AND st.started_at >= '2026-06-03'
      GROUP BY a.artist_id) s
WHERE s.artist_id = ar.artist_id;
SELECT md5(string_agg(artist_id || ':' || monthly_listeners, ',' ORDER BY artist_id)) AS h_before FROM artists \gset
ROLLBACK;
BEGIN;
UPDATE artists ar
SET monthly_listeners = coalesce(s.n, 0)
FROM (SELECT a.artist_id, x.n
      FROM artists a
      LEFT JOIN (SELECT ta.artist_id, count(DISTINCT st.user_id) AS n
                 FROM streams st
                 JOIN track_artists ta ON ta.track_id = st.track_id
                 WHERE st.started_at >= '2026-06-03'
                 GROUP BY ta.artist_id) x ON x.artist_id = a.artist_id) s
WHERE s.artist_id = ar.artist_id;
SELECT md5(string_agg(artist_id || ':' || monthly_listeners, ',' ORDER BY artist_id)) = :'h_before' AS "W04 table after update is the same" FROM artists;
ROLLBACK;
