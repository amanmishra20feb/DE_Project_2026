-- =====================================================================
-- sql/03_integrity_checks.sql : checks that the loaded data is consistent.
-- Each row = one check. "violations" must be 0 for the checks in section A.
-- Section B lists data problems we FOUND (non-zero on purpose, explained in
-- docs/02_schema_design.md). They are NOT turned into CHECK constraints,
-- because the seed data would be rejected.
-- Run:  psql -d <db> -f sql/03_integrity_checks.sql
-- =====================================================================
SET search_path TO spotify;

-- ---------------- A. rules the data must obey (expected 0) ----------------
SELECT 'A1 nobody streamed a track before its album was released' AS check_name,
       count(*) AS violations
FROM streams s
JOIN tracks t ON t.track_id = s.track_id
JOIN albums a ON a.album_id = t.album_id
WHERE (s.started_at AT TIME ZONE 'Asia/Kolkata')::date < a.release_date
UNION ALL
SELECT 'A2 ms_played never exceeds the track duration', count(*)
FROM streams s JOIN tracks t ON t.track_id = s.track_id
WHERE s.ms_played > t.duration_ms
UNION ALL
SELECT 'A3 every track has exactly one PRIMARY artist', count(*)
FROM tracks t
WHERE (SELECT count(*) FROM track_artists ta
       WHERE ta.track_id = t.track_id AND ta.role = 'PRIMARY') <> 1
UNION ALL
SELECT 'A4 the PRIMARY artist of a track is the artist of its album', count(*)
FROM track_artists ta
JOIN tracks t ON t.track_id = ta.track_id
JOIN albums a ON a.album_id = t.album_id
WHERE ta.role = 'PRIMARY' AND ta.artist_id <> a.artist_id
UNION ALL
SELECT 'A5 a featured artist is never also the primary artist of the same track', count(*)
FROM track_artists f
JOIN track_artists p ON p.track_id = f.track_id AND p.role = 'PRIMARY'
WHERE f.role = 'FEATURED' AND f.artist_id = p.artist_id
UNION ALL
SELECT 'A6 playlist positions run 1..n with no gaps', count(*)
FROM (SELECT playlist_id FROM playlist_tracks
      GROUP BY playlist_id
      HAVING min(position) <> 1 OR max(position) <> count(*)) g
UNION ALL
SELECT 'A7 a stream that names a playlist plays a track that is in that playlist', count(*)
FROM streams s
WHERE s.playlist_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM playlist_tracks pt
                  WHERE pt.playlist_id = s.playlist_id AND pt.track_id = s.track_id)
UNION ALL
SELECT 'A8 only collaborative playlists have tracks added by someone other than the owner', count(*)
FROM playlist_tracks pt
JOIN playlists p ON p.playlist_id = pt.playlist_id
WHERE pt.added_by_user_id <> p.owner_user_id AND NOT p.is_collaborative
UNION ALL
SELECT 'A9 no stream happens before the listener created the account', count(*)
FROM streams s JOIN users u ON u.user_id = s.user_id
WHERE s.started_at < u.created_at
UNION ALL
SELECT 'A10 no like happens before the listener created the account', count(*)
FROM liked_tracks l JOIN users u ON u.user_id = l.user_id
WHERE l.liked_at < u.created_at
UNION ALL
SELECT 'A11 no stream is older than the playlist it was played from', count(*)
FROM streams s JOIN playlists p ON p.playlist_id = s.playlist_id
WHERE s.started_at < p.created_at
UNION ALL
SELECT 'A12 stored artists.monthly_listeners equals the real distinct listeners of the last 28 days', count(*)
FROM artists ar
LEFT JOIN (SELECT ta.artist_id, count(DISTINCT st.user_id) AS n
           FROM track_artists ta
           JOIN streams st ON st.track_id = ta.track_id
                          AND st.started_at >= TIMESTAMPTZ '2026-06-03 00:00:00+05:30'
           GROUP BY ta.artist_id) x ON x.artist_id = ar.artist_id
WHERE ar.monthly_listeners <> coalesce(x.n, 0)
ORDER BY 1;

-- ---------------- B. data problems found (non-zero is expected) ----------------
-- B1 follows that are dated before the follower's account existed.
SELECT 'B1 follows dated before the follower created the account' AS problem,
       count(*) AS rows_affected
FROM artist_follows f JOIN users u ON u.user_id = f.user_id
WHERE f.followed_at < u.created_at
UNION ALL
-- B8 playlists dated before the owner's account existed.
SELECT 'B8 playlists created before their owner created the account', count(*)
FROM playlists p JOIN users u ON u.user_id = p.owner_user_id
WHERE p.created_at < u.created_at
UNION ALL
-- B2 the same track appears more than once in a playlist (query R22).
SELECT 'B2 (playlist, track) pairs that occur more than once', count(*)
FROM (SELECT 1 FROM playlist_tracks GROUP BY playlist_id, track_id HAVING count(*) > 1) d
UNION ALL
-- B3 users younger than 13 on the day they signed up.
SELECT 'B3 users younger than 13 when the account was created',
       count(*)
FROM users
WHERE age((created_at AT TIME ZONE 'Asia/Kolkata')::date, birth_date) < interval '13 years'
UNION ALL
SELECT 'B4 streams with ms_played = 0 (kept: a stream can be skipped instantly)', count(*)
FROM streams WHERE ms_played = 0
UNION ALL
-- B5 why query R13 ("public playlists never played") returns nothing:
-- streams.playlist_id is NULL for non-playlist plays, and  x NOT IN (..., NULL)  is never true.
SELECT 'B5 streams with playlist_id NULL (these make R13''s NOT IN return no rows)', count(*)
FROM streams WHERE playlist_id IS NULL
UNION ALL
SELECT 'B6 public playlists that were really never played (the correct answer to R13)', count(*)
FROM playlists p
WHERE p.is_public
  AND NOT EXISTS (SELECT 1 FROM streams s WHERE s.playlist_id = p.playlist_id)
UNION ALL
SELECT 'B7 album+track_no pairs reused on disc 2 (why track_no alone is not a key)', count(*)
FROM (SELECT 1 FROM tracks GROUP BY album_id, track_no HAVING count(*) > 1) d;
