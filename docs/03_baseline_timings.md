# Phase 3: Baseline timings (Team T0028)

Baseline = the schema of `sql/01_schema.sql` with **no extra indexes**. The only indexes are the ones PostgreSQL creates for
PRIMARY KEY and UNIQUE constraints (for example `pk_track_artists (track_id, artist_id)`, `uq_tracks_position (album_id, disc_no, track_no)`,
`uq_tracks_isrc`). Foreign-key columns such as `streams.user_id` and `streams.track_id` have **no index**.

**How it was measured**
- PostgreSQL 18.6 on one MacBook Pro, database `spotify_db`, schema `spotify`, seed data loaded (250,000 streams).
- `./benchmarks/run_benchmark.sh spotify_db baseline`: every query run 3 times with `EXPLAIN (ANALYZE, BUFFERS)`; the number is the
  `Execution Time` of each run. Writes ran inside `BEGIN ... ROLLBACK`, so the data did not change.
- Raw plans of all 3 runs: `benchmarks/results/baseline/R01.txt ... W05.txt`; summary: `benchmarks/results/baseline/summary.csv`.

## Timing table

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01: Artist page: artist 33's 10 most-streamed tracks in the last 28 days | READ | 31.727 | 8.582 | 8.326 | 16.212 |
| R02: Album page: tracklist of album 1469 | READ | 0.337 | 0.024 | 0.027 | 0.129 |
| R03: Search: tracks whose title contains "love", most popular first | READ | 23.820 | 21.703 | 21.053 | 22.192 |
| R04: "Recently played": user 1038's last 50 streams | READ | 5.946 | 5.586 | 5.162 | 5.565 |
| R05: Playlist page: playlist 501 in order, with every artist on each track | READ | 3.238 | 0.122 | 0.147 | 1.169 |
| R06: "Liked Songs": user 1038's liked tracks, newest first | READ | 0.481 | 0.045 | 0.040 | 0.189 |
| R07: Royalties: streams of 30 seconds or more ("royalty-eligible") per artist in June 2026, top 20 | READ | 12.900 | 10.695 | 10.809 | 11.468 |
| R08: Spotify for Artists: skip rate of each of artist 33's tracks | READ | 11.149 | 10.451 | 10.245 | 10.615 |
| R09: Wrapped 2025: user 1038's top 5 artists by minutes listened | READ | 5.961 | 5.514 | 5.486 | 5.654 |
| R10: Platform analytics: daily streams per platform in June 2026 | READ | 10.133 | 10.115 | 10.063 | 10.104 |
| R11: "Release Radar": 2026 releases by artists user 1038 follows | READ | 2.093 | 0.459 | 0.458 | 1.003 |
| R12: Compliance: explicit tracks streamed by users who were under 18 at the time | READ | 30.554 | 14.328 | 14.096 | 19.659 |
| R13: Curation team: public playlists that have never been played | READ | 21.599 | 21.459 | 20.906 | 21.321 |
| R14: Collaborative playlists: number of different people who added tracks | READ | 9.335 | 7.878 | 7.894 | 8.369 |
| R15: "Fans also like": artists most followed by the followers of artist 33 | READ | 6.224 | 1.830 | 1.791 | 3.282 |
| R16: Artist profiles: distinct listeners of every artist in the last 28 days ("monthly listeners") | READ | 16.354 | 16.131 | 16.463 | 16.316 |
| R17: Growth: free users with 4+ streams in June 2026 (Premium upsell list) | READ | 10.636 | 10.602 | 10.437 | 10.558 |
| R18: Platform analytics: share of offline listening per platform | READ | 14.965 | 14.076 | 14.434 | 14.492 |
| R19: Verified artists report: total streams and the latest stream of every verified artist | READ | 8,508.496 | 8,673.949 | 8,631.471 | 8,604.639 |
| R20: Listening patterns: streams per hour of the day per country | READ | 140.335 | 145.602 | 144.920 | 143.619 |
| R21: Rights management: look up a recording by its ISRC code | READ | 0.380 | 0.033 | 0.034 | 0.149 |
| R22: Playlist hygiene: playlists that contain the same track more than once | READ | 23.351 | 21.446 | 22.355 | 22.384 |
| R23: Support console: all streams, newest first, page 8,001 (25 per page) | READ | 43.190 | 44.836 | 43.953 | 43.993 |
| R24: Label report: average track length and explicit share per album type | READ | 11.541 | 11.497 | 11.096 | 11.378 |
| R25: Discovery: tracks released in the last 30 days, ranked by streams | READ | 16.542 | 13.746 | 13.647 | 14.645 |
| W01: Player: log a stream of track 1389 by user 1038 | WRITE | 2.126 | 0.492 | 0.488 | 1.035 |
| W02: Heart button: user 1038 likes track 1389 | WRITE | 1.234 | 0.470 | 0.460 | 0.721 |
| W03: "Add to playlist": append track 1389 to the end of playlist 501 | WRITE | 0.667 | 0.474 | 0.444 | 0.528 |
| W04: Nightly job: recompute every artist's monthly listeners (last 28 days) | WRITE | 40.460 | 39.139 | 40.523 | 40.041 |
| W05: Takedown: the label withdrew the whole album of track 1389, so remove its tracks from every playlist | WRITE | 6.545 | 6.503 | 6.375 | 6.474 |
| **Total (sum of all 30)** | | **9,012.319** | **9,117.787** | **9,073.603** | **9,067.903** |

## What the numbers show

- **R19 is the one slow query**: average 8,604.639 ms, about 95% of the total of all 30 queries. The other 29 queries together take about 463.264 ms.
- Slowest five (average ms): R19 (8,604.639), R20 (143.619), R23 (43.993), W04 (40.041), R22 (22.384).
- Run 1 is sometimes slower than Runs 2 and 3 (for example R01: 31.7 ms against 8.3 ms, R05: 3.2 ms against 0.1 ms, R11: 2.1 ms against 0.5 ms, R12: 30.6 ms against 14.1 ms), because the first run reads pages that are not yet in memory. We keep all three runs and average them, as the brief asks.
- W01 to W03 take about 0.5 ms each once warm. W04 (nightly recompute of every artist) takes about 40 ms and W05 (delete without an index on `playlist_tracks.track_id`) about 6 ms.
- At 250,000 streams most queries finish in milliseconds because all tables fit in the buffer cache. The full table scans (`streams` has 250,000 rows) are the pattern to fix in Phase 4 and the one that will grow with the data in Phase 5.

## Scan type and why each query is fast or slow

- **R01** (16.212 ms). Scan type: Parallel Seq Scan on streams; Seq Scan on track_artists; Index Scan on tracks_pkey. Why: streams has no index on started_at and track_artists has none on artist_id (its PK starts with track_id), so both are read in full to find artist 33's 160 rows and the last 28 days; fast only because the tables are small.
- **R02** (0.129 ms). Scan type: Index Scan on uq_tracks_position. Why: album_id is the first column of the UNIQUE (album_id, disc_no, track_no) index, so the 14 tracks are read directly, already in order.
- **R03** (22.192 ms). Scan type: Seq Scan on tracks. Why: ILIKE '%love%' starts with a wildcard, so no B-tree index can be used; all 67,808 tracks are checked (9,128 match) before the top-20 sort.
- **R04** (5.565 ms). Scan type: Parallel Seq Scan on streams; Index Scan on tracks_pkey. Why: no index on streams.user_id, so all 250,000 streams are scanned to find the user's 6 rows (the LIMIT 50 returns only 6).
- **R05** (1.169 ms). Scan type: Index Scans on pk_playlist_tracks, tracks_pkey, pk_track_artists, artists_pkey. Why: every step is a primary-key lookup starting from playlist 501 (9 rows), so almost nothing is read.
- **R06** (0.189 ms). Scan type: Index Scan on pk_liked_tracks; Index Scan on tracks_pkey. Why: user_id is the first column of the primary key (user_id, track_id), so the user's 2 likes are found directly.
- **R07** (11.468 ms). Scan type: Parallel Seq Scan on streams; Parallel Index Only Scan on pk_track_artists. Why: streams is read in full (no index on started_at or ms_played) to keep about 10.7k June rows, then hash-joined with all of track_artists and grouped by artist.
- **R08** (10.615 ms). Scan type: Parallel Seq Scan on streams; Seq Scan on track_artists; Index Scan on tracks_pkey. Why: no index on streams.track_id (it is a foreign key, which PostgreSQL does not index), so all 250,000 streams are read to match artist 33's 160 tracks.
- **R09** (5.654 ms). Scan type: Parallel Seq Scan on streams; Index Scans on pk_track_artists and artists_pkey. Why: no index on streams.user_id, and EXTRACT(YEAR FROM started_at) = 2025 is a function on the column, so the whole table is scanned for 4 matching rows.
- **R10** (10.104 ms). Scan type: Parallel Seq Scan on streams. Why: started_at::date casts the column, so an index on started_at could not be used; every stream is read, about 13.7k June rows are sorted and grouped.
- **R11** (1.003 ms). Scan type: Seq Scan on albums; Index Only Scan on pk_artist_follows; Index Scan on artists_pkey. Why: the user follows only 3 artists (primary-key lookup); albums has no index on release_date or artist_id, but it has only 12,000 rows.
- **R12** (19.659 ms). Scan type: Parallel Seq Scan on streams; Seq Scan on tracks; Index Scan on users_pkey. Why: every stream of an explicit track (about 28k rows) must be sorted by started_at before LIMIT 200 can be applied; the age() condition on users is a per-row function.
- **R13** (21.321 ms). Scan type: Seq Scan on playlists; hashed SubPlan with Seq Scan on streams. Why: streams is read in full to build the NOT IN list. It returns 0 rows because streams.playlist_id contains NULLs, and x NOT IN (..., NULL) is never true (integrity checks B5 and B6).
- **R14** (8.369 ms). Scan type: Seq Scan on playlist_tracks; Seq Scan on playlists. Why: all 120,004 playlist_tracks rows are read and hash-joined to the 968 collaborative playlists; COUNT(DISTINCT) needs an extra sort of 11,478 rows.
- **R15** (3.282 ms). Scan type: Seq Scan on artist_follows (f1); Index Only Scan on pk_artist_follows (f2); Index Scan on artists_pkey. Why: finding artist 33's 124 followers needs a full scan because the primary key starts with user_id; the second lookup by user_id uses the primary key.
- **R16** (16.316 ms). Scan type: Seq Scan on streams; Seq Scan on track_artists. Why: streams is scanned in full to keep 12,820 rows of the last 28 days and all 77,489 track_artists rows are hashed; COUNT(DISTINCT user_id) needs a sort of 14.6k rows.
- **R17** (10.558 ms). Scan type: Seq Scan on streams; Seq Scan on users. Why: both tables are scanned in full (no index on streams.started_at or users.subscription), then joined and filtered with HAVING count(*) >= 4 (22 users remain).
- **R18** (14.492 ms). Scan type: Parallel Seq Scan on streams. Why: no WHERE clause, so every one of the 250,000 streams has to be read once; an index cannot help a full-table aggregate.
- **R19** (8,604.639 ms). Scan type: Seq Scan on artists; two correlated SubPlans, each with Seq Scan on streams and Seq Scan on track_artists. Why: the slow query: each of the 334 verified artists runs two subqueries, and each of the 668 subquery runs reads all 250,000 streams and all of track_artists (about 13 ms per run), which adds up to about 8.6 s.
- **R20** (143.619 ms). Scan type: Seq Scan on streams; Seq Scan on users. Why: all 250,000 streams are joined to users and sorted by country and hour; the sort does not fit in work_mem and spills 4,400 kB to disk.
- **R21** (0.149 ms). Scan type: Index Scan on uq_tracks_isrc; Index Scan on albums_pkey. Why: the UNIQUE constraint on isrc gives an index, so the one matching track is found directly.
- **R22** (22.384 ms). Scan type: Seq Scan on playlist_tracks. Why: all 120,004 rows are grouped by (playlist_id, track_id); the hash table does not fit in memory and spills to disk (5 batches).
- **R23** (43.993 ms). Scan type: Seq Scan on streams. Why: OFFSET 200000 forces PostgreSQL to read and sort 200,025 rows (external merge sort, 9,336 kB on disk) just to throw away the first 200,000; there is no index on started_at.
- **R24** (11.378 ms). Scan type: Seq Scan on tracks; Seq Scan on albums. Why: every track and album is needed for the averages, so full scans and a hash join are the right plan; it is cheap because the tables are small.
- **R25** (14.645 ms). Scan type: Seq Scan on albums; Index Scan on uq_tracks_position; Seq Scan on streams. Why: the 84 recent albums are cheap, but the LEFT JOIN reads all 250,000 streams to count plays of only 460 tracks (no index on streams.track_id).
- **W01** (1.035 ms). Scan type: Insert on streams (no scan). Why: a single-row insert; the cost is the foreign-key checks: user and track are primary-key lookups, while playlist_id is NULL, so its check does nothing.
- **W02** (0.721 ms). Scan type: Insert on liked_tracks (no scan). Why: a single-row insert checked against the primary key (ON CONFLICT) plus 2 foreign-key lookups.
- **W03** (0.528 ms). Scan type: Index Only Scan Backward on pk_playlist_tracks; Index Scan on playlists_pkey. Why: max(position) is read from the end of the primary-key index, then 3 foreign-key checks run.
- **W04** (40.041 ms). Scan type: Seq Scan on streams; Seq Scan on track_artists; Seq Scan on artists; Index Scan on artists_pkey. Why: recomputes all 3,000 artists: it scans the last-28-day streams and all of track_artists, sorts about 79.5k rows for COUNT(DISTINCT), then updates 3,000 rows (Run 1 found them with a Seq Scan on artists, Runs 2 and 3 with the index).
- **W05** (6.474 ms). Scan type: Seq Scan on playlist_tracks; Index Scans on tracks_pkey and uq_tracks_position. Why: no index on playlist_tracks.track_id, so all 120,004 rows are scanned to delete 2 rows (about 6 ms).
