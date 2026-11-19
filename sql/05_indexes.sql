-- Phase 4 indexes (team T0028). Run after sql/01 and sql/02:  psql -d <db> -f sql/05_indexes.sql
-- Re-runnable. Each index says which queries it serves and why this type and column order.

SET search_path TO spotify;

-- streams (250,000 rows) is read by 16 of the 30 queries and had no index except the primary key.

-- Covering index for every query that filters or sorts streams by time. started_at is the key (range and ORDER BY);
-- INCLUDE holds the other columns those queries read, so PostgreSQL can answer them with an Index Only Scan
-- and never visit the table.
-- R01, R07, R10, R12, R16, R17, R23, W04.
CREATE INDEX IF NOT EXISTS ix_streams_started_cov
    ON streams (started_at)
    INCLUDE (stream_id, user_id, track_id, ms_played, platform);

-- One listener's history: equality on user_id first, then started_at newest first. It finds one user's rows
-- directly instead of reading all 250,000 streams (the plans use a bitmap scan on it and a small sort, because one
-- user has only a few rows). R04, R09. Also the missing index on the user_id foreign key.
CREATE INDEX IF NOT EXISTS ix_streams_user_time
    ON streams (user_id, started_at DESC);

-- Streams of a given track: equality on track_id, then started_at for the date filter; skipped is included so R08 never
-- visits the table. R08, R19, R25. Also the missing index on the track_id foreign key.
CREATE INDEX IF NOT EXISTS ix_streams_track_time
    ON streams (track_id, started_at) INCLUDE (skipped);

-- Streams played from a playlist. Partial: the 137,386 rows with playlist_id NULL are never searched,
-- so they are left out (about half of the table). R13 (NOT EXISTS) and the ON DELETE SET NULL of playlists.
CREATE INDEX IF NOT EXISTS ix_streams_playlist
    ON streams (playlist_id) WHERE playlist_id IS NOT NULL;

-- track_artists has the primary key (track_id, artist_id); this is the reverse order, to go from an artist to its tracks.
-- R01, R08, R19. Also the missing index on the artist_id foreign key.
CREATE INDEX IF NOT EXISTS ix_track_artists_artist
    ON track_artists (artist_id, track_id);

-- Followers of one artist (the primary key starts with user_id, so it cannot find them). R15.
-- Also the missing index on the artist_id foreign key.
CREATE INDEX IF NOT EXISTS ix_artist_follows_artist
    ON artist_follows (artist_id, user_id);

-- Playlists that contain a track: W05 deletes by track_id and had to scan all 120,004 rows. Also the missing index on the
-- track_id foreign key (without it, deleting a track would scan the whole table).
CREATE INDEX IF NOT EXISTS ix_playlist_tracks_track
    ON playlist_tracks (track_id, playlist_id);

-- Albums of one artist, newest first: equality on artist_id, then the date. R11.
-- Also the missing index on the artist_id foreign key.
CREATE INDEX IF NOT EXISTS ix_albums_artist_date
    ON albums (artist_id, release_date DESC);

-- "Most popular tracks containing a word": the title filter matches 13% of the tracks, so reading tracks from the most
-- popular down and stopping after 20 matches is cheaper than finding all matches. The track_id tie-breaker (also in
-- the query) makes the tied rows deterministic. R03.
CREATE INDEX IF NOT EXISTS ix_tracks_popularity
    ON tracks (popularity DESC, track_id);

-- Not an index: statistics on the hour of a stream. R20 groups streams by country and EXTRACT(HOUR FROM started_at);
-- without this, PostgreSQL does not know there are only 24 hours, expects 250,000 groups, sorts all 250,000 rows
-- (4,400 kB spilled to disk) and then aggregates. With it, it aggregates in memory and the sort is gone.
CREATE STATISTICS IF NOT EXISTS st_streams_hour ON (EXTRACT(HOUR FROM started_at)) FROM streams;

-- Refresh the statistics and the visibility map (Index Only Scans need it).
VACUUM (ANALYZE);
