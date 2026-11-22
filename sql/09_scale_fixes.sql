-- Phase 5 fixes found on the large dataset (team T0028). Run after sql/05_indexes.sql:  psql -d <db> -f sql/09_scale_fixes.sql
-- Re-runnable (drops and rebuilds the view). Only R22 missed its target on the large data (see docs/05_scalability_report.md).

SET search_path TO spotify;

-- R22 (playlist hygiene: playlists that contain the same track more than once) has to compare every one of the
-- 2,400,008 playlist_tracks rows. Even with the best index the plan is an Index Only Scan of the whole index followed by
-- a GroupAggregate over 2.4 million tiny groups, about 0.5 s, against a target of 250 ms. The report is a clean-up list
-- for the curation team and does not need to be live to the second, so the duplicates (about 36,000 pairs) are kept in a
-- materialized view and R22 reads it. R22 then reads 36,000 rows instead of 2,400,008.
-- Refresh: REFRESH MATERIALIZED VIEW CONCURRENTLY mv_playlist_duplicates;  once a night, after the nightly job W04. It does
-- not block readers (it needs the unique index below). Between two refreshes the list can be up to one day old.
DROP MATERIALIZED VIEW IF EXISTS mv_playlist_duplicates;
CREATE MATERIALIZED VIEW mv_playlist_duplicates AS
SELECT playlist_id, track_id, count(*) AS copies
FROM playlist_tracks
GROUP BY playlist_id, track_id
HAVING count(*) > 1;

-- Unique key of the view: required for REFRESH ... CONCURRENTLY, and every (playlist_id, track_id) appears once.
CREATE UNIQUE INDEX ux_mv_playlist_duplicates ON mv_playlist_duplicates (playlist_id, track_id);
-- Same order as the query: ORDER BY copies DESC, playlist_id, so R22 is an Index Scan with no sort.
CREATE INDEX ix_mv_playlist_duplicates_order ON mv_playlist_duplicates (copies DESC, playlist_id);
ANALYZE mv_playlist_duplicates;

-- Proof that the view holds exactly what the original R22 returns right now (both rows must be 0):
SELECT (SELECT count(*) FROM (SELECT playlist_id, track_id, count(*) AS copies FROM playlist_tracks
                              GROUP BY playlist_id, track_id HAVING count(*) > 1) o) AS rows_original,
       (SELECT count(*) FROM mv_playlist_duplicates) AS rows_view,
       (SELECT count(*) FROM (SELECT playlist_id, track_id, count(*) AS copies FROM playlist_tracks
                              GROUP BY playlist_id, track_id HAVING count(*) > 1
                              EXCEPT SELECT playlist_id, track_id, copies FROM mv_playlist_duplicates) x) AS only_original,
       (SELECT count(*) FROM (SELECT playlist_id, track_id, copies FROM mv_playlist_duplicates
                              EXCEPT SELECT playlist_id, track_id, count(*) FROM playlist_tracks
                              GROUP BY playlist_id, track_id HAVING count(*) > 1) x) AS only_view;
