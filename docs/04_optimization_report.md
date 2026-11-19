# Phase 4: Optimization report (Team T0028)

PostgreSQL 18.6, MacBook Pro, Apple M4, 16GB RAM. Same laptop and same method as `docs/03_baseline_timings.md`: every query run 3 times with `EXPLAIN (ANALYZE, BUFFERS)`, average of the three `Execution Time` values, writes inside `BEGIN ... ROLLBACK`. We used 3 runs, as in the baseline and in `CHECKPOINTS.md` (the README example shows 5; a fair before/after needs the same number on both sides).

## Summary

- **Total time of the 30 queries: 9,067.903 ms before, 192.523 ms after (97.9% less, 47× faster).**
- 21 of the 30 queries are at least 50% faster (17 of them because of a real change; R02, R05, R06 and R21 have no change and their difference is run-to-run noise). The biggest gain is **R19**: 8,604.639 ms → 20.166 ms (427×).
- **R13 returned a wrong answer** (0 rows). It uses `NOT IN` on `streams.playlist_id`, which contains NULLs; `x NOT IN (..., NULL)` is never true. We fixed it with `NOT EXISTS` and it now returns the 1,891 playlists that were really never played (see below).
- 9 indexes, 1 statistics object and 6 changed queries (R03, R09, R10, R13, R19, W04). The other 24 queries have the same SQL as the baseline; they are faster only because of the indexes. Files: `sql/05_indexes.sql`, `sql/06_optimized_queries.sql`, proof in `sql/07_prove_same_results.sql`.
- Cost: the new indexes take 39 MB (the tables hold 45 MB) on disk, and each insert into `streams` now maintains up to 4 more indexes (3 for a stream that is not played from a playlist, because the playlist index is partial; see Write overhead).

## The optimization table

| Query | Before (ms) | Problem found in the plan | Optimization applied | After (ms) | Improvement | Same result? |
|-------|------------:|---------------------------|----------------------|-----------:|------------:|:------------:|
| R01: Artist page: artist 33's 10 most-streamed tracks in the last 28 days | 16.212 | Seq Scan on streams (250,000 rows) and on track_artists (77,489): nothing leads from artist 33 to its tracks | ix_track_artists_artist + the covering streams indexes (Index Only Scans); query unchanged | 1.745 | 89.2% (9.3×) | ✅ |
| R02: Album page: tracklist of album 1469 | 0.129 | none: already an Index Scan on uq_tracks_position | none needed | 0.025 | 80.6% (5.2×) | ✅ |
| R03: Search: tracks whose title contains "love", most popular first | 22.192 | Seq Scan on tracks: the title filter tests all 67,808 rows (13% match) before the top-20 sort | ix_tracks_popularity (popularity DESC, track_id) + track_id tie-breaker in ORDER BY: reads the most popular tracks first and stops after 20 matches | 0.088 | 99.6% (252×) | ✅ |
| R04: "Recently played": user 1038's last 50 streams | 5.565 | Seq Scan on all 250,000 streams to find one user's rows (no index on streams.user_id) | ix_streams_user_time (user_id, started_at DESC); query unchanged | 0.089 | 98.4% (63×) | ✅ |
| R05: Playlist page: playlist 501 in order, with every artist on each track | 1.169 | none: already primary-key lookups | none needed | 0.147 | 87.4% (8.0×) | ✅ |
| R06: "Liked Songs": user 1038's liked tracks, newest first | 0.189 | none: already primary-key lookups | none needed | 0.051 | 73.0% (3.7×) | ✅ |
| R07: Royalties: streams of 30 seconds or more ("royalty-eligible") per artist in June 2026, top 20 | 11.468 | Seq Scan on streams for the June range (about 10.7k of 250k rows) | covering index ix_streams_started_cov (Index Only Scan on the date range); the hash join with track_artists remains | 8.727 | 23.9% (1.3×) | ✅ |
| R08: Spotify for Artists: skip rate of each of artist 33's tracks | 10.615 | Seq Scan on streams and on track_artists to collect artist 33's tracks and their plays | ix_track_artists_artist + ix_streams_track_time (INCLUDE skipped, so no table visit) | 0.650 | 93.9% (16×) | ✅ |
| R09: Wrapped 2025: user 1038's top 5 artists by minutes listened | 5.654 | Seq Scan on streams for one user; EXTRACT(YEAR FROM started_at) hides the column from any index | range predicate on started_at instead of EXTRACT + ix_streams_user_time | 0.087 | 98.5% (65×) | ✅ |
| R10: Platform analytics: daily streams per platform in June 2026 | 10.104 | Seq Scan on streams; started_at::date hides the column from any index | range predicate on started_at + covering index ix_streams_started_cov (Index Only Scan) | 2.863 | 71.7% (3.5×) | ✅ |
| R11: "Release Radar": 2026 releases by artists user 1038 follows | 1.003 | Seq Scan on albums (12,000 rows) for the followed artists' albums | ix_albums_artist_date (artist_id, release_date DESC) | 0.075 | 92.5% (13×) | ✅ |
| R12: Compliance: explicit tracks streamed by users who were under 18 at the time | 19.659 | Seq Scan on all streams, hash join with explicit tracks, then a sort of about 28k rows before LIMIT 200 | covering index ix_streams_started_cov read newest first: the join stops after 200 matching rows and nothing is sorted; query unchanged | 9.219 | 53.1% (2.1×) | ✅ |
| R13: Curation team: public playlists that have never been played | 21.321 | WRONG ANSWER: NOT IN against a column with NULLs returns 0 rows; the plan also scans all of streams | rewritten with NOT EXISTS (correct result: 1,891 playlists) + partial index ix_streams_playlist | 2.271 | 89.3% (9.4×) | ✅ fixed: 0 → 1,891 rows |
| R14: Collaborative playlists: number of different people who added tracks | 8.369 | Seq Scan on playlist_tracks (120,004 rows) hash-joined to the 968 collaborative playlists, then a sort for COUNT(DISTINCT) | none helped: the join must read the tracks of every collaborative playlist (see "Queries we could not speed up") | 8.090 | 3.3% (1.0×) | ✅ |
| R15: "Fans also like": artists most followed by the followers of artist 33 | 3.282 | Seq Scan on artist_follows (69,901 rows) to find the followers of artist 33 (the primary key starts with user_id) | ix_artist_follows_artist (artist_id, user_id); query unchanged | 0.775 | 76.4% (4.2×) | ✅ |
| R16: Artist profiles: distinct listeners of every artist in the last 28 days ("monthly listeners") | 16.316 | Seq Scan on streams and track_artists, then a sort of about 14.6k rows for COUNT(DISTINCT user_id) | covering index ix_streams_started_cov (Index Only Scan on the 28-day range); the join and the distinct count remain | 10.180 | 37.6% (1.6×) | ✅ |
| R17: Growth: free users with 4+ streams in June 2026 (Premium upsell list) | 10.558 | Seq Scan on streams (June) and users | covering index ix_streams_started_cov (Index Only Scan); query unchanged | 3.772 | 64.3% (2.8×) | ✅ |
| R18: Platform analytics: share of offline listening per platform | 14.492 | Seq Scan on all streams: the query has no filter | none possible: it must read every row (see "Queries we could not speed up") | 15.018 | -3.6% (1.0×) | ✅ |
| R19: Verified artists report: total streams and the latest stream of every verified artist | 8,604.639 | Two correlated subqueries per verified artist (334 x 2), each scanning all 250,000 streams again | rewritten as one JOIN + GROUP BY; ix_track_artists_artist and ix_streams_track_time (Index Only Scans) | 20.166 | 99.8% (427×) | ✅ |
| R20: Listening patterns: streams per hour of the day per country | 143.619 | Sorts all 250,000 joined rows on disk (4,400 kB external merge): PostgreSQL expected 250,000 groups because it had no statistics on the hour | CREATE STATISTICS on EXTRACT(HOUR FROM started_at): in-memory hash aggregate, no big sort (the planner also chose a parallel scan with 1 worker, which is part of the gain); query unchanged | 36.746 | 74.4% (3.9×) | ✅ |
| R21: Rights management: look up a recording by its ISRC code | 0.149 | none: already an Index Scan on uq_tracks_isrc | none needed | 0.035 | 76.5% (4.3×) | ✅ |
| R22: Playlist hygiene: playlists that contain the same track more than once | 22.384 | Seq Scan on playlist_tracks and a hash aggregate that spills to disk | none helped: it must read all 120,004 rows (see "Queries we could not speed up") | 22.322 | 0.3% (1.0×) | ✅ |
| R23: Support console: all streams, newest first, page 8,001 (25 per page) | 43.993 | Seq Scan on all streams, then an external sort of 200,025 rows (9,336 kB on disk) to skip 200,000 | covering index ix_streams_started_cov read newest first (Index Only Scan Backward): no sort; the 200,000 skipped entries are still walked | 18.585 | 57.8% (2.4×) | ✅ |
| R24: Label report: average track length and explicit share per album type | 11.378 | Seq Scan on tracks and albums | none possible: it needs every track (see "Queries we could not speed up") | 11.215 | 1.4% (1.0×) | ✅ |
| R25: Discovery: tracks released in the last 30 days, ranked by streams | 14.645 | Seq Scan on all 250,000 streams to count the plays of 460 new tracks | ix_streams_track_time (Index Scan per track instead of reading all streams); query unchanged | 1.493 | 89.8% (9.8×) | ✅ |
| W01: Player: log a stream of track 1389 by user 1038 | 1.035 | 1 row inserted; 3 foreign-key checks (playlist_id is NULL, so that check does nothing) | no change to the query; 3 new streams indexes are now maintained on every insert (the 4th, partial one is skipped because playlist_id is NULL) | 0.622 | 39.9% (1.7×) | ✅ |
| W02: Heart button: user 1038 likes track 1389 | 0.721 | 1 row inserted with ON CONFLICT and 2 foreign-key checks | no change; liked_tracks has no new index | 0.526 | 27.0% (1.4×) | ✅ |
| W03: "Add to playlist": append track 1389 to the end of playlist 501 | 0.528 | 1 row inserted; max(position) from the primary-key index | no change; playlist_tracks has one new index to maintain | 0.599 | -13.4% (0.9×) | ✅ |
| W04: Nightly job: recompute every artist's monthly listeners (last 28 days) | 40.041 | Joins every artist to every one of its streams (79,538 rows) and sorts them before counting | rewritten: count distinct listeners per artist from the 28-day streams (about 14k rows) + covering index | 16.248 | 59.4% (2.5×) | ✅ table identical |
| W05: Takedown: the label withdrew the whole album of track 1389, so remove its tracks from every playlist | 6.474 | Seq Scan on playlist_tracks (120,004 rows) to find the rows of one album's tracks | ix_playlist_tracks_track (track_id, playlist_id) | 0.094 | 98.5% (69×) | ✅ |
| **Total (sum of all 30)** | **9,067.903** | | | **192.523** | **97.9%** (47×) | |

Improvement % = (before − after) / before × 100; the factor in brackets is before ÷ after. Before = average of the 3 baseline runs (`benchmarks/results/baseline/summary.csv`), after = average of the 3 optimized runs (`benchmarks/results/optimized/summary.csv`). ✅ for a query whose SQL did not change means the same SQL runs on the same data, so only the plan changed; the rewritten ones are proven below. Differences under about 1 ms (R02, R05, R06, R21 and the writes W01 to W03) are within the run-to-run noise of the laptop. For W01 to W03 the percentages in the table come mostly from the slow first baseline run; the like-for-like comparison is in Write overhead (W01 is about 0.1 ms slower, not faster).

## Read the results: R13 returns a wrong answer

R13 asks for the public playlists that were never played. The baseline returned **0 rows**, and in the plan the whole `Seq Scan on playlists` finished with `rows=0` while its `SubPlan` read all 250,000 streams. The cause is a NULL rule: `streams.playlist_id` is NULL for every stream that was not played from a playlist (137,386 rows, check B5), and `p.playlist_id NOT IN (…, NULL)` is never true, because comparing with NULL gives "unknown", not true. So one NULL in the list wipes out every row.

`NOT EXISTS` ignores the NULLs. The corrected query returns **1,891** public playlists, the same number as check B6 in `sql/03_integrity_checks.sql` and as a third form of the query written as a LEFT JOIN anti-join (B6 is also written with `NOT EXISTS`, so the anti-join is the independent comparison; see the proof). This is a change of the answer on purpose, not just of the speed, so "Same result?" says so.

## Proof that the results are unchanged

`sql/07_prove_same_results.sql` runs the original and the optimized version of every changed query side by side and counts the rows with `EXCEPT` in both directions. `same = t` means equal counts and no row in one result that is missing from the other. For W04 it also compares the table after the UPDATE (md5 of `artist_id:monthly_listeners`). Output on our laptop:

```
SET
   TimeZone   
--------------
 Asia/Kolkata
(1 row)

R03
 query | rows_before | rows_after | only_before | only_after | same 
-------+-------------+------------+-------------+------------+------
 R03   |          20 |         20 |           0 |          0 | t
(1 row)

R09
 query | rows_before | rows_after | only_before | only_after | same 
-------+-------------+------------+-------------+------------+------
 R09   |           4 |          4 |           0 |          0 | t
(1 row)

R10
 query | rows_before | rows_after | only_before | only_after | same 
-------+-------------+------------+-------------+------------+------
 R10   |         180 |        180 |           0 |          0 | t
(1 row)

R13
 query | rows_before | rows_after | only_before | only_after | equals_anti_join 
-------+-------------+------------+-------------+------------+------------------
 R13   |           0 |       1891 |           0 |       1891 | t
(1 row)

R19
 query | rows_before | rows_after | only_before | only_after | same 
-------+-------------+------------+-------------+------------+------
 R19   |         334 |        334 |           0 |          0 | t
(1 row)

W04
        query        | rows_before | rows_after | only_before | only_after | same 
---------------------+-------------+------------+-------------+------------+------
 W04 computed values |        3000 |       3000 |           0 |          0 | t
(1 row)

BEGIN
UPDATE 3000
ROLLBACK
BEGIN
UPDATE 3000
 W04 table after update is the same 
------------------------------------
 t
(1 row)

ROLLBACK
```

R03 note: `ORDER BY popularity DESC LIMIT 20` has ties (57 tracks with "love" all have popularity 100), so which 20 of them the original returns is not defined by the query; it depends on how the rows are stored. The optimized query adds `track_id` as a tie-breaker, which turns an undefined order into a defined one. On our data the two returned the same 20 rows, but that is a property of our data, not a guarantee of the original. R09 and R10 compare dates in the session time zone, as the original did; the optimized form keeps that behavior.

## Before and after plans of the 5 biggest improvements

Chosen by milliseconds saved. Cost estimates and buffer lines are left out; the plans are the last of the 3 runs, from `benchmarks/results/baseline/*.txt` and `benchmarks/results/optimized/*.txt`.

### R19: 8,604.639 ms → 20.166 ms (427×)

_Verified artists report: total streams and the latest stream of every verified artist_

Before:
```
Sort  (actual time=8631.413..8631.422 rows=334.00 loops=1)
  Sort Key: ((SubPlan 1)) DESC
  Sort Method: quicksort  Memory: 43kB
  ->  Seq Scan on artists ar  (actual time=32.391..8631.306 rows=334.00 loops=1)
        Filter: is_verified
        Rows Removed by Filter: 2666
        SubPlan 1
          ->  Aggregate  (actual time=12.920..12.920 rows=1.00 loops=334)
                ->  Hash Join  (actual time=1.636..12.911 rows=207.89 loops=334)
                      Hash Cond: (s.track_id = ta.track_id)
                      ->  Seq Scan on streams s  (actual time=0.000..5.090 rows=250000.00 loops=334)
                      ->  Hash  (actual time=1.464..1.464 rows=56.64 loops=334)
                            Buckets: 1024  Batches: 1  Memory Usage: 29kB
                            ->  Seq Scan on track_artists ta  (actual time=0.125..1.461 rows=56.64 loops=334)
                                  Filter: (artist_id = ar.artist_id)
                                  Rows Removed by Filter: 77432
        SubPlan 2
          ->  Aggregate  (actual time=12.921..12.921 rows=1.00 loops=334)
                ->  Hash Join  (actual time=1.640..12.912 rows=207.89 loops=334)
                      Hash Cond: (s_1.track_id = ta_1.track_id)
                      ->  Seq Scan on streams s_1  (actual time=0.000..5.094 rows=250000.00 loops=334)
                      ->  Hash  (actual time=1.467..1.467 rows=56.64 loops=334)
                            Buckets: 1024  Batches: 1  Memory Usage: 29kB
                            ->  Seq Scan on track_artists ta_1  (actual time=0.125..1.464 rows=56.64 loops=334)
                                  Filter: (artist_id = ar.artist_id)
                                  Rows Removed by Filter: 77432
Planning:
Planning Time: 0.422 ms
Execution Time: 8631.471 ms
```
After:
```
Sort  (actual time=19.672..19.679 rows=334.00 loops=1)
  Sort Key: (count(s.track_id)) DESC
  Sort Method: quicksort  Memory: 43kB
  ->  HashAggregate  (actual time=19.626..19.641 rows=334.00 loops=1)
        Group Key: ar.artist_id
        Batches: 1  Memory Usage: 72kB
        ->  Nested Loop Left Join  (actual time=0.014..16.165 rows=70687.00 loops=1)
              ->  Nested Loop Left Join  (actual time=0.009..1.700 rows=18918.00 loops=1)
                    ->  Seq Scan on artists ar  (actual time=0.004..0.127 rows=334.00 loops=1)
                          Filter: is_verified
                          Rows Removed by Filter: 2666
                    ->  Index Only Scan using ix_track_artists_artist on track_artists ta  (actual time=0.001..0.003 rows=56.64 loops=334)
                          Index Cond: (artist_id = ar.artist_id)
                          Heap Fetches: 0
                          Index Searches: 334
              ->  Index Only Scan using ix_streams_track_time on streams s  (actual time=0.000..0.001 rows=3.67 loops=18918)
                    Index Cond: (track_id = ta.track_id)
                    Heap Fetches: 23
                    Index Searches: 18918
Planning:
Planning Time: 0.571 ms
Execution Time: 19.728 ms
```

### R20: 143.619 ms → 36.746 ms (3.9×)

_Listening patterns: streams per hour of the day per country_

Before:
```
GroupAggregate  (actual time=108.817..144.042 rows=96.00 loops=1)
  Group Key: u.country_code, (EXTRACT(hour FROM s.started_at))
  ->  Sort  (actual time=108.667..131.662 rows=250000.00 loops=1)
        Sort Key: u.country_code, (EXTRACT(hour FROM s.started_at))
        Sort Method: external merge  Disk: 4400kB
        ->  Hash Join  (actual time=2.536..40.519 rows=250000.00 loops=1)
              Hash Cond: (s.user_id = u.user_id)
              ->  Seq Scan on streams s  (actual time=0.002..6.178 rows=250000.00 loops=1)
              ->  Hash  (actual time=2.508..2.508 rows=30000.00 loops=1)
                    Buckets: 32768  Batches: 1  Memory Usage: 1428kB
                    ->  Seq Scan on users u  (actual time=0.003..1.230 rows=30000.00 loops=1)
Planning:
Planning Time: 0.322 ms
Execution Time: 144.920 ms
```
After:
```
Finalize GroupAggregate  (actual time=35.623..36.494 rows=96.00 loops=1)
  Group Key: u.country_code, (EXTRACT(hour FROM s.started_at))
  ->  Gather Merge  (actual time=35.617..36.450 rows=192.00 loops=1)
        Workers Planned: 1
        Workers Launched: 1
        ->  Sort  (actual time=34.590..34.594 rows=96.00 loops=2)
              Sort Key: u.country_code, (EXTRACT(hour FROM s.started_at))
              Sort Method: quicksort  Memory: 28kB
              Worker 0:  Sort Method: quicksort  Memory: 28kB
              ->  Partial HashAggregate  (actual time=34.540..34.545 rows=96.00 loops=2)
                    Group Key: u.country_code, EXTRACT(hour FROM s.started_at)
                    Batches: 1  Memory Usage: 32kB
                    Worker 0:  Batches: 1  Memory Usage: 32kB
                    ->  Hash Join  (actual time=2.654..22.878 rows=125000.00 loops=2)
                          Hash Cond: (s.user_id = u.user_id)
                          ->  Parallel Seq Scan on streams s  (actual time=0.001..3.414 rows=125000.00 loops=2)
                          ->  Hash  (actual time=2.629..2.630 rows=30000.00 loops=2)
                                Buckets: 32768  Batches: 1  Memory Usage: 1428kB
                                ->  Seq Scan on users u  (actual time=0.014..1.248 rows=30000.00 loops=2)
Planning:
Planning Time: 0.488 ms
Execution Time: 36.549 ms
```

### R23: 43.993 ms → 18.585 ms (2.4×)

_Support console: all streams, newest first, page 8,001 (25 per page)_

Before:
```
Limit  (actual time=43.624..43.625 rows=25.00 loops=1)
  ->  Sort  (actual time=35.107..40.256 rows=200025.00 loops=1)
        Sort Key: started_at DESC
        Sort Method: external merge  Disk: 9336kB
        ->  Seq Scan on streams  (actual time=0.004..12.029 rows=250000.00 loops=1)
Planning:
Planning Time: 0.135 ms
Execution Time: 43.953 ms
```
After:
```
Limit  (actual time=11.635..11.637 rows=25.00 loops=1)
  ->  Index Only Scan Backward using ix_streams_started_cov on streams  (actual time=0.041..8.417 rows=200025.00 loops=1)
        Heap Fetches: 69
        Index Searches: 1
Planning:
Planning Time: 0.295 ms
Execution Time: 11.649 ms
```

### W04: 40.041 ms → 16.248 ms (2.5×)

_Nightly job: recompute every artist's monthly listeners (last 28 days)_

Before:
```
Update on artists ar  (actual time=40.453..40.454 rows=0.00 loops=1)
  ->  Merge Join  (actual time=28.648..33.628 rows=3000.00 loops=1)
        Merge Cond: (ar.artist_id = s.artist_id)
        ->  Index Scan using artists_pkey on artists ar  (actual time=0.002..0.527 rows=3000.00 loops=1)
              Index Searches: 1
        ->  Subquery Scan on s  (actual time=28.644..32.818 rows=3000.00 loops=1)
              ->  GroupAggregate  (actual time=28.640..32.614 rows=3000.00 loops=1)
                    Group Key: a.artist_id
                    ->  Sort  (actual time=28.609..30.082 rows=79538.00 loops=1)
                          Sort Key: a.artist_id, st.user_id
                          Sort Method: quicksort  Memory: 3913kB
                          ->  Hash Right Join  (actual time=12.844..21.810 rows=79538.00 loops=1)
                                Hash Cond: (ta.artist_id = a.artist_id)
                                ->  Hash Right Join  (actual time=12.536..16.726 rows=79538.00 loops=1)
                                      Hash Cond: (st.track_id = ta.track_id)
                                      ->  Seq Scan on streams st  (actual time=7.172..7.692 rows=12820.00 loops=1)
                                            Filter: (started_at >= '2026-06-03 00:00:00+05:30'::timestamp with time zone)
                                            Rows Removed by Filter: 237180
                                      ->  Hash  (actual time=5.310..5.310 rows=77489.00 loops=1)
                                            Buckets: 131072  Batches: 1  Memory Usage: 4051kB
                                            ->  Seq Scan on track_artists ta  (actual time=0.003..2.461 rows=77489.00 loops=1)
                                ->  Hash  (actual time=0.299..0.299 rows=3000.00 loops=1)
                                      Buckets: 16384  Batches: 1  Memory Usage: 234kB
                                      ->  Seq Scan on artists a  (actual time=0.003..0.205 rows=3000.00 loops=1)
Planning:
Planning Time: 0.384 ms
Execution Time: 40.523 ms
```
After:
```
Update on artists ar  (actual time=16.469..16.470 rows=0.00 loops=1)
  ->  Hash Left Join  (actual time=9.875..10.472 rows=3000.00 loops=1)
        Hash Cond: (a.artist_id = x.artist_id)
        ->  Hash Join  (actual time=0.335..0.689 rows=3000.00 loops=1)
              Hash Cond: (ar.artist_id = a.artist_id)
              ->  Seq Scan on artists ar  (actual time=0.002..0.133 rows=3000.00 loops=1)
              ->  Hash  (actual time=0.322..0.322 rows=3000.00 loops=1)
                    Buckets: 16384  Batches: 1  Memory Usage: 257kB
                    ->  Seq Scan on artists a  (actual time=0.001..0.206 rows=3000.00 loops=1)
        ->  Hash  (actual time=9.535..9.536 rows=2675.00 loops=1)
              Buckets: 4096  Batches: 1  Memory Usage: 252kB
              ->  Subquery Scan on x  (actual time=8.409..9.401 rows=2675.00 loops=1)
                    ->  GroupAggregate  (actual time=8.405..9.256 rows=2675.00 loops=1)
                          Group Key: ta.artist_id
                          ->  Sort  (actual time=8.396..8.645 rows=14619.00 loops=1)
                                Sort Key: ta.artist_id, st.user_id
                                Sort Method: quicksort  Memory: 727kB
                                ->  Hash Join  (actual time=5.318..6.965 rows=14619.00 loops=1)
                                      Hash Cond: (st.track_id = ta.track_id)
                                      ->  Index Only Scan using ix_streams_started_cov on streams st  (actual time=0.005..0.504 rows=12820.00 loops=1)
                                            Index Cond: (started_at >= '2026-06-03 00:00:00+05:30'::timestamp with time zone)
                                            Heap Fetches: 69
                                            Index Searches: 1
                                      ->  Hash  (actual time=5.248..5.248 rows=77489.00 loops=1)
                                            Buckets: 131072  Batches: 1  Memory Usage: 4051kB
                                            ->  Seq Scan on track_artists ta  (actual time=0.003..2.474 rows=77489.00 loops=1)
Planning:
Planning Time: 0.574 ms
Execution Time: 16.542 ms
```

### R03: 22.192 ms → 0.088 ms (252×)

_Search: tracks whose title contains "love", most popular first_

Before:
```
Limit  (actual time=21.043..21.044 rows=20.00 loops=1)
  ->  Sort  (actual time=21.043..21.043 rows=20.00 loops=1)
        Sort Key: popularity DESC
        Sort Method: top-N heapsort  Memory: 26kB
        ->  Seq Scan on tracks  (actual time=0.004..20.632 rows=9128.00 loops=1)
              Filter: ((title)::text ~~* '%love%'::text)
              Rows Removed by Filter: 58680
Planning:
Planning Time: 0.212 ms
Execution Time: 21.053 ms
```
After:
```
Limit  (actual time=0.009..0.071 rows=20.00 loops=1)
  ->  Index Scan using ix_tracks_popularity on tracks  (actual time=0.009..0.070 rows=20.00 loops=1)
        Filter: ((title)::text ~~* '%love%'::text)
        Rows Removed by Filter: 146
        Index Searches: 1
Planning:
Planning Time: 0.269 ms
Execution Time: 0.080 ms
```

## Write overhead

| Write | Before (ms) | After (ms) | Change | Runs 2-3 before (ms) | Runs 2-3 after (ms) | Change (runs 2-3) |
|-------|------------:|-----------:|-------:|---------------------:|--------------------:|------------------:|
| W01: Player: log a stream of track 1389 by user 1038 | 1.035 | 0.622 | −0.413 ms (−40%) | 0.490 | 0.595 | +0.105 ms (+22%) |
| W02: Heart button: user 1038 likes track 1389 | 0.721 | 0.526 | −0.195 ms (−27%) | 0.465 | 0.512 | +0.047 ms (+10%) |
| W03: "Add to playlist": append track 1389 to the end of playlist 501 | 0.528 | 0.599 | +0.071 ms (+13%) | 0.459 | 0.499 | +0.041 ms (+9%) |
| W04: Nightly job: recompute every artist's monthly listeners (last 28 days) | 40.041 | 16.248 | −23.793 ms (−59%) | 39.831 | 16.704 | −23.127 ms (−58%) |
| W05: Takedown: the label withdrew the whole album of track 1389, so remove its tracks from every playlist | 6.474 | 0.094 | −6.380 ms (−99%) | 6.439 | 0.090 | −6.349 ms (−99%) |

**Which writes got slower, and by how much.** The 3-run average is the number used everywhere else, but for the single-row writes it is misleading: in the baseline the first run of each write was much slower than the next two, probably a cold cache (W01: 2.126 / 0.492 / 0.488 ms), and that first run pulls the baseline average up. The warm runs (2 and 3, last three columns) compare like with like. On the warm runs W01, W02, W03 got slower: W01 by 0.105 ms (+22%); W02 by 0.047 ms (+10%); W03 by 0.041 ms (+9%). W01 and W03 write to tables that got new indexes, and every index has to be updated on each insert; W02 writes to `liked_tracks`, which has no new index, so its change is noise and shows how large the noise is. W01 (log one stream) matters most, because the player writes a stream for every song played; it maintains 3 of the 4 new `streams` indexes (the partial `ix_streams_playlist` is skipped when `playlist_id` is NULL, as in W01), so it costs about 0.1 ms more per play. On the 3-run average, W01 to W03 look -0.413 / -0.195 / +0.071 ms, which is mostly the slow first run of the baseline and not a real speed-up.

The cost of an index is paid on every INSERT, UPDATE of an indexed column and DELETE: `streams` now has 5 indexes instead of 1 (the primary key), and `playlist_tracks`, `track_artists`, `artist_follows`, `albums` and `tracks` have one more each. A tenth of a millisecond per stream is acceptable for this workload: it is read-heavy (25 reads, 5 writes, and each write touches 1 row except the nightly job W04). A system that bulk-loads millions of streams would feel the extra indexes more, and would load first and build the indexes afterwards. W04 and W05 got faster because their reads got faster.

## Index storage

Sizes from `benchmarks/index_sizes.sql` (`pg_relation_size`), index next to its table:

```
        index_name        |   table_name    | index_size | table_size | pct_of_table 
--------------------------+-----------------+------------+------------+--------------
 ix_streams_started_cov   | streams         | 13 MB      | 20 MB      |           65
 ix_streams_track_time    | streams         | 9920 kB    | 20 MB      |           48
 ix_streams_user_time     | streams         | 7720 kB    | 20 MB      |           37
 ix_playlist_tracks_track | playlist_tracks | 2656 kB    | 6120 kB    |           43
 ix_track_artists_artist  | track_artists   | 1712 kB    | 3432 kB    |           50
 ix_artist_follows_artist | artist_follows  | 1544 kB    | 3024 kB    |           51
 ix_tracks_popularity     | tracks          | 1504 kB    | 5320 kB    |           28
 ix_streams_playlist      | streams         | 928 kB     | 20 MB      |            5
 ix_albums_artist_date    | albums          | 280 kB     | 1064 kB    |           26
(9 rows)

 all_new_indexes | all_tables 
-----------------+------------
 39 MB           | 45 MB
(1 row)
```

The three big `streams` indexes (a fourth, partial one is only 928 kB) are the expensive ones. `ix_streams_started_cov` is wide on purpose (it carries `stream_id`, `user_id`, `track_id`, `ms_played`, `platform`) so that R07, R10, R12, R16, R17, R23 and W04 never visit the table. Together the new indexes are almost as large as the tables themselves (totals under the table above), which is the price for turning scans into index lookups on a 250,000-row table; the first step to cut it would be to drop `INCLUDE` columns of that one index and accept table visits for some queries.

## Queries we could not speed up

These changed less than 20% (or got slower); we did not force them:

- **R14** (8.369 → 8.090 ms): It has to read the tracks of every collaborative playlist (11,478 rows) and count distinct contributors per playlist; the plan is already a hash join of 968 playlists against `playlist_tracks`, and the best index for it would only replace the sequential read of 120,004 rows by index reads of 11,478 rows, a gain we expect to be small for a query that already finishes in about 8 ms. We did not build or measure such an index.
- **R18** (14.492 → 15.018 ms): No WHERE clause: every one of the 250,000 streams is counted once. An aggregate over a whole table must read the whole table; only a summary table (stale data) or a smaller index could help.
- **R22** (22.384 → 22.322 ms): It groups all 120,004 playlist rows by (playlist, track) to find duplicates, so it has to read every row. The plan is a sequential read plus a hash aggregate; the new indexes do not change it. We did not save plans for any alternative form, so we make no claim about one.
- **R24** (11.378 → 11.215 ms): Averages over all 67,808 tracks joined to all 12,000 albums: every row is needed.
- **R02, R05, R06, R21, W01, W02, W03** were already fast (primary-key or unique-index lookups, one-row inserts), so there was nothing to gain.
- **R20 and R23** are faster but remain among the slowest: R20 reads all 250,000 streams, and R23 (`OFFSET 200000`) still walks 200,000 index entries. Only a different pagination (keyset: "after the last started_at seen") would remove that work, and it needs the last value from the previous page, so it would change how the page is requested and not only the query.

## Not done, and why

- **No trigram (GIN) index for R03** (`pg_trgm`). The word "love" matches 13% of the titles, so a trigram index would not be selective, and reading by popularity and stopping after 20 matches already takes about a tenth of a millisecond. We did not measure a trigram index. It would help a search for a rare word.
- **No materialized view** for the reports (R16, R18, R20, R24): they would answer instantly but from stale data; the brief asks us to state a refresh plan, and we preferred to keep these queries live.
- **No server settings were changed** (`work_mem`, `enable_*`): the gains come from indexes, statistics and query shape only.

## How to reproduce

```bash
psql -d spotify_db -f sql/05_indexes.sql
psql -d spotify_db -f sql/07_prove_same_results.sql
bash benchmarks/run_benchmark.sh spotify_db optimized 3 sql/06_optimized_queries.sql
psql -d spotify_db -f benchmarks/index_sizes.sql
```
