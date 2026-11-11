-- =====================================================================
-- sql/02_load_data.sql : load the 10 seed CSV files (Team T0028)
--
-- Run from the REPOSITORY ROOT (so the relative paths below resolve) after
-- unzipping seed_data.zip into ./seed_data/ (the CSV files are never committed):
--     psql -d <db> -f sql/01_schema.sql
--     psql -d <db> -f sql/02_load_data.sql
--
-- Load order: parents before children, so every foreign key is satisfied.
-- =====================================================================
\set ON_ERROR_STOP on
SET search_path TO spotify;

\copy artists         FROM 'seed_data/artists.csv'         WITH (FORMAT csv, HEADER true)
\copy users           FROM 'seed_data/users.csv'           WITH (FORMAT csv, HEADER true)
\copy albums          FROM 'seed_data/albums.csv'          WITH (FORMAT csv, HEADER true)
\copy tracks          FROM 'seed_data/tracks.csv'          WITH (FORMAT csv, HEADER true)
\copy track_artists   FROM 'seed_data/track_artists.csv'   WITH (FORMAT csv, HEADER true)
\copy playlists       FROM 'seed_data/playlists.csv'       WITH (FORMAT csv, HEADER true)
\copy playlist_tracks FROM 'seed_data/playlist_tracks.csv' WITH (FORMAT csv, HEADER true)
\copy liked_tracks    FROM 'seed_data/liked_tracks.csv'    WITH (FORMAT csv, HEADER true)
\copy artist_follows  FROM 'seed_data/artist_follows.csv'  WITH (FORMAT csv, HEADER true)
\copy streams         FROM 'seed_data/streams.csv'         WITH (FORMAT csv, HEADER true)

-- The ids were loaded explicitly, so move every identity counter past the
-- highest loaded id. Otherwise the next INSERT without an id would collide.
SELECT setval(pg_get_serial_sequence('spotify.artists',   'artist_id'),   (SELECT max(artist_id)   FROM artists));
SELECT setval(pg_get_serial_sequence('spotify.albums',    'album_id'),    (SELECT max(album_id)    FROM albums));
SELECT setval(pg_get_serial_sequence('spotify.tracks',    'track_id'),    (SELECT max(track_id)    FROM tracks));
SELECT setval(pg_get_serial_sequence('spotify.users',     'user_id'),     (SELECT max(user_id)     FROM users));
SELECT setval(pg_get_serial_sequence('spotify.playlists', 'playlist_id'), (SELECT max(playlist_id) FROM playlists));
SELECT setval(pg_get_serial_sequence('spotify.streams',   'stream_id'),   (SELECT max(stream_id)   FROM streams));

ANALYZE;

-- Row counts that must match the project brief
SELECT 'artists' AS table_name, count(*) AS rows, 3000 AS expected FROM artists
UNION ALL SELECT 'albums',          count(*), 12000  FROM albums
UNION ALL SELECT 'tracks',          count(*), 67808  FROM tracks
UNION ALL SELECT 'track_artists',   count(*), 77489  FROM track_artists
UNION ALL SELECT 'users',           count(*), 30000  FROM users
UNION ALL SELECT 'playlists',       count(*), 10000  FROM playlists
UNION ALL SELECT 'playlist_tracks', count(*), 120004 FROM playlist_tracks
UNION ALL SELECT 'streams',         count(*), 250000 FROM streams
UNION ALL SELECT 'liked_tracks',    count(*), 58533  FROM liked_tracks
UNION ALL SELECT 'artist_follows',  count(*), 69901  FROM artist_follows;
