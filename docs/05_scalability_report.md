# Phase 5: Scalability report (team T0028)

**Database:** PostgreSQL 18.6 on a MacBook Pro M4, no server setting changed. **Large database:** `spotify_large` (the 20× dataset, loaded with the same schema and load script as the seed, only the folder name changed). **Seed database:** `spotify_db`.
**Queries:** `sql/06_optimized_queries.sql` (Phase 4, unchanged) on the seed; `sql/10_large_workload.sql` on the large data. The two files are identical except for R22 (section 3). The original 30 queries were not run on the large data.
**Raw evidence:** every number below comes from `benchmarks/results/optimized/` (seed), `benchmarks/results/large/` (large, final run) and `benchmarks/results/large_first_run/` (the first large run, before the R22 fix). Each query has a `.txt` file with the plans of its 3 runs; `summary.csv` holds the averages.

## Headline

- On the large data **all 30 queries meet their target** (final run, `benchmarks/results/large/summary.csv`). On the **first** large run 29 of 30 met it; **R22** took 527.9 ms against 250 ms and needed a fix (section 3).
- The data grew 20× (streams 250,000 → 4,999,883); the sum of all 30 averages grew from 192.5 ms to 5,639.5 ms (29.3×).
- The database grew from 115 MB to 2133 MB (18.5×); tables take 891 MB and indexes 1230 MB in the `spotify` schema (section 4).
- The numbers are from one laptop and vary from run to run (section 2.5). Where a first (cold) run inflates an average, the report says so instead of hiding it.

## 1. Results table

Averages of 3 runs, in ms. Growth = large ÷ seed. Targets are the Phase 5 targets (real-time under 5 ms, interactive under 250 ms, reports under 5,000 ms, batch W04 under 3,000 ms). Growth is computed from the averages exactly as printed in `summary.csv` (3 decimals), so for queries under 1 ms it can differ by about 0.1× from a value recomputed with more digits.

| Query | Target (ms) | Optimized on seed (ms) | Optimized on large (ms) | Growth (large ÷ seed) | Meets target? | If not, what we changed |
|-------|------------:|-----------------------:|------------------------:|----------------------:|:-------------:|-------------------------|
| R01 | < 250 | 1.745 | 5.935 | 3.4× | ✅ |  |
| R02 | < 5 | 0.025 | 0.143 | 5.7× | ✅ |  |
| R03 | < 250 | 0.088 | 0.378 | 4.3× | ✅ |  |
| R04 | < 5 | 0.089 | 0.550 | 6.2× | ✅ |  |
| R05 | < 5 | 0.147 | 1.125 | 7.7× | ✅ |  |
| R06 | < 5 | 0.051 | 0.107 | 2.1× | ✅ |  |
| R07 | < 5,000 | 8.727 | 176.7 | 20.2× | ✅ |  |
| R08 | < 250 | 0.650 | 4.420 | 6.8× | ✅ |  |
| R09 | < 250 | 0.087 | 0.671 | 7.7× | ✅ |  |
| R10 | < 5,000 | 2.863 | 140.3 | 49.0× | ✅ |  |
| R11 | < 5 | 0.075 | 0.611 | 8.1× | ✅ |  |
| R12 | < 5,000 | 9.219 | 127.2 | 13.8× | ✅ |  |
| R13 | < 250 | 2.271 | 85.42 | 37.6× | ✅ |  |
| R14 | < 5,000 | 8.090 | 175.4 | 21.7× | ✅ |  |
| R15 | < 250 | 0.775 | 21.81 | 28.1× | ✅ |  |
| R16 | < 5,000 | 10.18 | 239.5 | 23.5× | ✅ |  |
| R17 | < 5,000 | 3.772 | 232.8 | 61.7× | ✅ |  |
| R18 | < 5,000 | 15.02 | 456.6 | 30.4× | ✅ |  |
| R19 | < 5,000 | 20.17 | 877.5 | 43.5× | ✅ |  |
| R20 | < 5,000 | 36.75 | 1,638.0 | 44.6× | ✅ |  |
| R21 | < 5 | 0.035 | 0.213 | 6.1× | ✅ |  |
| R22 | < 250 | 22.32 | 9.631 | 0.4× (see note) | ✅ after fix | First large run: 527.9 ms (over target). Reads the materialized view `mv_playlist_duplicates` now (`sql/09_scale_fixes.sql`); see section 3. The growth shown compares different query texts; the old text took 527.9 ms on large = 23.6× the seed. |
| R23 | < 5,000 | 18.59 | 27.33 | 1.5× | ✅ |  |
| R24 | < 5,000 | 11.21 | 185.9 | 16.6× | ✅ |  |
| R25 | < 250 | 1.493 | 54.49 | 36.5× | ✅ |  |
| W01 | < 5 | 0.622 | 1.633 | 2.6× | ✅ |  |
| W02 | < 5 | 0.526 | 1.286 | 2.4× | ✅ |  |
| W03 | < 5 | 0.599 | 1.472 | 2.5× | ✅ |  |
| W04 | < 3,000 | 16.25 | 1,171.8 | 72.1× | ✅ |  |
| W05 | < 250 | 0.094 | 0.429 | 4.6× | ✅ |  |

The R23 query still uses `OFFSET 200000`; we did not switch to keyset pagination, so there is no "last seen" value to choose. Its cost depends on the offset, not on the table size: both databases read the same 200,025 index entries (`rows=200025` in both plans), and it grew only 1.5× (18.59 → 27.33 ms). Page 8,001 gets slower the deeper the page is, so a real console should use keyset pagination (`WHERE started_at < :last_started_at`), where the "last seen" value is the `started_at` (with `stream_id` as tie-breaker) of the last row on the previous page.

## 2. Growth analysis

### 2.1 How much the data grew

| Table | Rows on seed | Rows on large | Growth |
|-------|-------------:|--------------:|-------:|
| streams | 250,000 | 4,999,883 | 20.0× |
| tracks | 67,808 | 1,360,381 | 20.1× |
| playlist_tracks | 120,004 | 2,400,008 | 20.0× |
| track_artists | 77,489 | 1,554,720 | 20.1× |
| artist_follows | 69,901 | 1,399,801 | 20.0× |
| users | 30,000 | 600,000 | 20.0× |
| liked_tracks | 58,533 | 1,171,457 | 20.0× |
| albums | 12,000 | 240,000 | 20.0× |
| playlists | 10,000 | 200,000 | 20.0× |
| artists | 3,000 | 60,000 | 20.0× |

(Row counts are `reltuples` from the last `ANALYZE`/`VACUUM`, so they are estimates and can differ from `count(*)` by a few rows.)

We group the queries by growth factor: **under 10×** (stayed far below the 20× the data grew), **10× to 30×** (about 20×) and **over 30×** (more than 20×). R22 is left out because its query text changed.

### 2.2 Stayed about the same (under 10×, 15 queries)

| Query | Seed (ms) | Large (ms) | Growth |
|-------|----------:|-----------:|-------:|
| R01 | 1.745 | 5.935 | 3.4× |
| R02 | 0.025 | 0.143 | 5.7× |
| R03 | 0.088 | 0.378 | 4.3× |
| R04 | 0.089 | 0.550 | 6.2× |
| R05 | 0.147 | 1.125 | 7.7× |
| R06 | 0.051 | 0.107 | 2.1× |
| R08 | 0.650 | 4.420 | 6.8× |
| R09 | 0.087 | 0.671 | 7.7× |
| R11 | 0.075 | 0.611 | 8.1× |
| R21 | 0.035 | 0.213 | 6.1× |
| R23 | 18.59 | 27.33 | 1.5× |
| W01 | 0.622 | 1.633 | 2.6× |
| W02 | 0.526 | 1.286 | 2.4× |
| W03 | 0.599 | 1.472 | 2.5× |
| W05 | 0.094 | 0.429 | 4.6× |

**Why.** These queries touch one user, one album, one artist, one playlist, one ISRC or the newest rows, through a B-tree index, so the work depends on how many rows that one key has, not on the table size. A lookup costs about log n: on the large data an index probe on `ix_streams_playlist` reads 3.0 pages instead of 2.0 on the seed (R13 plans: 378,520 pages for 126,153 probes against 12,635 pages for 6,317 probes), so the tree is about one level deeper after 20× more rows. All of them stay under 27.33 ms. For sub-millisecond queries the ratio is also mostly fixed cost and cache state (R06: 0.051 → 0.107 ms), so a factor of 5 to 8 on a few hundred microseconds is not a warning sign. R23 stays at 1.5× because it always reads the same 200,025 index entries. The three single-row inserts W01 to W03 grew 2.4× to 2.6×; the streams insert has to maintain deeper indexes, and it is still 1.633 ms against a 5 ms target.

### 2.3 Grew about 20× (10× to 30×, 6 queries)

| Query | Seed (ms) | Large (ms) | Growth | Large, runs 2 and 3 only (ms) |
|-------|----------:|-----------:|-------:|-----------------------------:|
| R07 | 8.727 | 176.7 | 20.2× | 170.0 |
| R12 | 9.219 | 127.2 | 13.8× | 62.99 |
| R14 | 8.090 | 175.4 | 21.7× | 174.2 |
| R15 | 0.775 | 21.81 | 28.1× | 6.247 |
| R16 | 10.18 | 239.5 | 23.5× | 237.6 |
| R24 | 11.21 | 185.9 | 16.6× | 184.2 |

**Why.** R07, R14, R16 and R24 read a fixed *share* of a table that grew 20×, so the rows they read grew about 20× and so did the time. R12 and R15 are in this group only because a cold first run inflates their average; warm they would be under 10× (section 2.5).
- **R07** reads June 2026, which is the same ~5.5% of streams in both databases (13,736 → 274,725 rows in R10's plans for the same month), and joins them to `track_artists`.
- **R14** and **R24** have to read all of `playlist_tracks` (collaborative playlists) or all of `tracks` and `albums` (label report). Their plans are sequential scans on both databases, and `playlist_tracks` grew 20.0× and `tracks` 20.1×.
- **R16** reads the streams of the last 28 days, again a fixed share of the table.
- **R12** has a `LIMIT 200`, so it stops early; its average is inflated by a cold first run (255.6 ms, then 63.69 and 62.30 ms). Warm, it grew 6.8×.
- **R15** depends on the followers of one artist: artist 33 has 124 followers on the seed and 606 on the large data (4.9×). Its average includes a cold first run too (52.92 ms); warm it grew 8.1×.

### 2.4 Grew more than 20× (over 30×, 8 queries)

| Query | Seed (ms) | Large (ms) | Growth | Large, runs 2 and 3 only (ms) | Warm growth |
|-------|----------:|-----------:|-------:|-----------------------------:|------------:|
| R10 | 2.863 | 140.3 | 49.0× | 139.8 | 48.8× |
| R13 | 2.271 | 85.42 | 37.6× | 76.64 | 33.7× |
| R17 | 3.772 | 232.8 | 61.7× | 233.4 | 61.9× |
| R18 | 15.02 | 456.6 | 30.4× | 490.4 | 32.7× |
| R19 | 20.17 | 877.5 | 43.5× | 421.4 | 20.9× |
| R20 | 36.75 | 1,638.0 | 44.6× | 1,526.5 | 41.5× |
| R25 | 1.493 | 54.49 | 36.5× | 37.76 | 25.3× |
| W04 | 16.25 | 1,171.8 | 72.1× | 1,172.8 | 72.2× |

All eight are far inside their targets (the largest is R20 at 1,638 ms against 5,000 ms, and W04 at 1,172 ms against 3,000 ms), so none needed a fix. What the plans show:

- **R10** (49×): the rows to aggregate grew 20× (13,736 → 274,725), but the sort changed from an in-memory quicksort (773 kB) to an **external merge sort on disk** (5,520 kB) because it no longer fits in the memory a sort may use (`work_mem`; we did not change it). The Index Only Scan itself went from 1.0 ms to 43.1 ms.
- **R13** (38×): the anti-join probes `ix_streams_playlist` once per public playlist: 6,317 probes on the seed and 126,153 on the large data (20×), and each probe reads 3 pages instead of 2 (section 2.2). 20× more probes times 1.5× more pages per probe gives the extra growth; PostgreSQL also started one parallel worker here (`Gather`) on the large data.
- **R17** (62×): the hash of the 266,994 FREE users no longer fits in one batch (`Batches: 2`, temp files) and its `Seq Scan on users` reads 6,561 pages from outside PostgreSQL's buffer cache on every run (`read=6561`); on the seed everything was a cache hit.
- **R18** (30×): a full scan of `streams`. The seed table (2,576 pages) stayed in the buffer cache; on the large data it is 399 MB and each run reads 50,487 pages from outside it (`read=50487`), with 2 workers instead of 1.
- **R19** (44×, but 21× warm): the average is inflated by a cold first run of 1,789.7 ms (runs 2 and 3: 419.6 and 423.3 ms). The join work grew less than 20× (index probes into `ix_streams_track_time`: 18,918 → 132,871, 7×) but 12,927 pages are read from outside the cache; we did not isolate the rest of the difference.
- **R20** (45×): the hash of all 600,000 users now needs 4 batches (`Batches: 4`), so most of the 5,000,000 stream rows are written to temp files and read again (`temp read=21098 written=21120` pages, about 165 MB), and 56,928 pages are read from outside the cache. The seed did it in one in-memory batch.
- **R25** (37×, 25× warm): it joins the albums released in the last 30 days: 84 albums on the seed and 1,997 on the large data (24×), and each of their tracks probes `ix_streams_track_time` (11,165 probes). The cold first run (87.95 ms) inflates the average.
- **W04** (72×): the plan changed. On the seed it hashed `track_artists` (77,489 rows); on the large data the planner reads all 1,554,720 `track_artists` rows with a sequential scan, sorts 293,125 rows with an **external merge sort on disk** (5,184 kB) and merge-joins; then it updates all 60,000 `artists` rows. About 790 ms of the 1,166 ms is the join and sort; the remaining 375 ms or so is the update of 60,000 rows.

We did not change any of these plans or any server setting: all are inside their targets, and raising `work_mem` or `shared_buffers` to make the spills disappear would hide how the queries behave at scale (and is not allowed in this project).

### 2.5 How reliable the averages are

Each average is 3 runs on a laptop, and the first run of a query is often cold. The table lists the queries whose first run was more than twice the average of runs 2 and 3 (and more than 3 ms slower):

| Query | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average in section 1 (ms) |
|-------|-----------:|-----------:|-----------:|--------------------------:|
| R01 | 15.45 | 1.176 | 1.178 | 5.935 |
| R08 | 6.698 | 2.803 | 3.758 | 4.420 |
| R12 | 255.6 | 63.69 | 62.30 | 127.2 |
| R15 | 52.92 | 5.925 | 6.569 | 21.81 |
| R19 | 1,789.7 | 419.6 | 423.3 | 877.5 |
| R25 | 87.95 | 37.85 | 37.66 | 54.49 |

The averages in section 1 are the plain average of the 3 runs, as the project requires, not the warm values. Using the warm values would lower them; it would not change a single "meets target" answer.

The large benchmark was also run once before the R22 fix (`benchmarks/results/large_first_run/`). The SQL of the other 29 queries is identical in both runs, so differences between the two runs are run-to-run noise. The biggest ones:

| Query | First large run (ms) | Final large run (ms) |
|-------|---------------------:|---------------------:|
| R01 | 3.108 | 5.935 |
| R15 | 31.50 | 21.81 |
| R19 | 454.7 | 877.5 |

The final run is the one used everywhere in this report. Both runs meet every target except R22 in the first run, so the conclusion does not depend on which run is used.

## 3. What broke at scale and how we fixed it

### 3.1 R22: playlists that contain the same track more than once (target 250 ms)

On the seed R22 took 22.32 ms. On the large data it took **527.9 ms** (runs 533.2, 543.7, 506.8), more than twice the 250 ms target, while the other 24 reads and all 5 writes were fine. The plan **before** the fix (`benchmarks/results/large_first_run/R22.txt`, run 3):

```
Sort (actual time=504.338..505.601 rows=36000.00 loops=1)
  Sort Key: (count(*)) DESC, playlist_id
  Sort Method: quicksort  Memory: 2662kB
  Buffers: shared hit=6551
  ->  GroupAggregate (actual time=0.148..491.342 rows=36000.00 loops=1)
        Group Key: track_id, playlist_id
        Filter: (count(*) > 1)
        Rows Removed by Filter: 2328008
        Buffers: shared hit=6545
        ->  Index Only Scan using ix_playlist_tracks_track on playlist_tracks (actual time=0.129..158.776 rows=2400008.00 loops=1)
              Heap Fetches: 0
              Index Searches: 1
              Buffers: shared hit=6545
Planning Time: 0.555 ms
Execution Time: 506.846 ms
```

**Why.** The query finds duplicates by grouping every row of `playlist_tracks`. The plan is already the best one for that text (an Index Only Scan on `ix_playlist_tracks_track` with no heap fetches, then a `GroupAggregate`): it reads all 2,400,008 rows (about 160 to 180 ms) and aggregates 2,364,008 groups to keep 36,000 (the other 2,328,008 are removed by the `HAVING`). That work is proportional to the table, 20× more than on the seed, and no ordinary index avoids it, because a duplicate can only be found by looking at all the rows; an extra index on `(playlist_id, track_id)` would still have to read all 2,400,008 entries. Nor can the data be changed: the duplicates are real data (the table has 36,000 of them).

**Fix (`sql/09_scale_fixes.sql`).** The duplicates change slowly (a playlist gets a duplicate only when someone adds the same track twice), so the database keeps them in a **materialized view**, refreshed once a night:

```sql
CREATE MATERIALIZED VIEW mv_playlist_duplicates AS
SELECT playlist_id, track_id, count(*) AS copies
FROM playlist_tracks GROUP BY playlist_id, track_id HAVING count(*) > 1;
CREATE UNIQUE INDEX ux_mv_playlist_duplicates ON mv_playlist_duplicates (playlist_id, track_id);
CREATE INDEX ix_mv_playlist_duplicates_order ON mv_playlist_duplicates (copies DESC, playlist_id);
```

R22 now reads `SELECT playlist_id, track_id, copies FROM mv_playlist_duplicates ORDER BY copies DESC, playlist_id;` (same columns, same order; `sql/10_large_workload.sql`). The plan **after** the fix (`benchmarks/results/large/R22.txt`, run 3):

```
Index Scan using ix_mv_playlist_duplicates_order on mv_playlist_duplicates (actual time=0.012..7.720 rows=36000.00 loops=1)
  Index Searches: 1
  Buffers: shared hit=36139
Planning Time: 0.342 ms
Execution Time: 8.964 ms
```

R22 now takes **9.631 ms** (runs 10.86, 9.065, 8.964), 55× faster than before and well under 250 ms. The 9 ms is the time to return 36,000 rows, so it grows with the number of duplicate pairs, not with the table.

**Proof that the view returns the same rows.** `sql/09_scale_fixes.sql` compares the view with the original query in both directions (`EXCEPT`) and the row counts; `benchmarks/results/large/scale_fixes.txt` holds its output: 36,000 rows in the original, 36,000 in the view, 0 rows only in the original, 0 rows only in the view.

**Trade-offs.**
- The list is up to **one day old**: a duplicate added after the last refresh is not shown until the next one. For a playlist-hygiene tool that is acceptable; for a screen that must show a duplicate the moment it is created it would not be.
- The view must be refreshed (`REFRESH MATERIALIZED VIEW CONCURRENTLY mv_playlist_duplicates;`, possible because of the unique index and without blocking readers), for example right after the nightly job W04. A refresh costs about what the old R22 cost, roughly 0.5 s (the first-run plans), plus the concurrent merge, which we did not measure.
- It uses a little extra space (36,000 rows and 2 indexes; not measured separately, it is not part of the table sizes in section 4).
- It lives inside the database, so it respects the project rule against caching outside the database. It does not change any data.

### 3.2 Other plans that changed at scale (no target missed)

These are not failures, but they are the places that will break first at 100× (section 5):

| Query | Seed plan | Large plan | Evidence |
|-------|-----------|------------|----------|
| R10 | in-memory quicksort, 773 kB | external merge sort on disk, 5,520 kB | `large/R10.txt` |
| R17 | one in-memory hash batch | 2 hash batches, temp files, 6,561 pages read outside the cache | `large/R17.txt` |
| R20 | one hash batch, in-memory | 4 hash batches, `temp read=21098 written=21120` pages | `large/R20.txt` |
| W04 | hash join, in-memory sort | sequential scan of 1,554,720 rows, external merge sort 5,184 kB, merge join | `large/W04.txt` |
| R13 | single process | `Gather` with 1 parallel worker, 3 pages per index probe instead of 2 | `large/R13.txt` |
| R18, R20 | table fully cached | 50,487 pages read from outside the buffer cache per run | `large/R18.txt`, `large/R20.txt` |

## 4. Storage

| | Seed (`spotify_db`) | Large (`spotify_large`) | Growth |
|---|---:|---:|---:|
| Total database size (`pg_database_size`) | 115 MB | 2133 MB | 18.5× |
| All tables, without indexes (`spotify` schema) | 45 MB | 891 MB | 19.8× |
| All indexes (`spotify` schema) | 62 MB | 1230 MB | 20.0× |

The database total is larger than tables + indexes because it also holds the system catalogs and, on the large database, the materialized view and its two indexes. Table and index sizes per table (`benchmarks/db_sizes.sql`; outputs in `benchmarks/results/large/db_sizes_seed.txt` and `db_sizes_large.txt`):

| Table | Seed table | Seed indexes | Large table | Large indexes | Large total |
|-------|-----------:|-------------:|------------:|--------------:|------------:|
| streams | 20 MB | 37 MB | 399 MB | 732 MB | 1131 MB |
| tracks | 5352 kB | 8160 kB | 104 MB | 159 MB | 263 MB |
| playlist_tracks | 6152 kB | 5288 kB | 119 MB | 103 MB | 222 MB |
| track_artists | 3464 kB | 3424 kB | 67 MB | 67 MB | 134 MB |
| artist_follows | 3056 kB | 3096 kB | 59 MB | 60 MB | 119 MB |
| users | 2800 kB | 2888 kB | 55 MB | 60 MB | 115 MB |
| liked_tracks | 2568 kB | 1296 kB | 50 MB | 25 MB | 75 MB |
| albums | 1096 kB | 944 kB | 21 MB | 18 MB | 39 MB |
| playlists | 680 kB | 240 kB | 13 MB | 4408 kB | 17 MB |
| artists | 264 kB | 160 kB | 4680 kB | 2752 kB | 7432 kB |

- **Everything grew about 20×**, as the row counts did. Tables and indexes grew almost exactly in step (19.8× and 20.0×), so the indexes added in Phase 4 did not become more expensive relative to the data.
- **Indexes are larger than the data**: 1230 MB of indexes against 891 MB of tables, and `streams` alone has 732 MB of indexes for 399 MB of table. That is the price of the 9 indexes of `sql/05_indexes.sql` (the covering index `ix_streams_started_cov` is the biggest). It buys the read speed above and costs some write time: W01 took 0.622 ms on the seed and 1.633 ms on the large data.
- `streams` is 53% of the tables-plus-indexes total on the large data, so it is the table that matters for any storage or maintenance plan.

## 5. Architecture for 100×

We read "100×" as 100× the **seed**: 25,000,000 streams, which is 5× the large data we measured. We extrapolate linearly from our own measurements and say where that is a guess.

### 5.1 What would break first (estimates, not measurements)

Index lookups (the 15 queries of section 2.2) grow with log n and will not be a problem. The queries that read a share of `streams` will grow about 5×:

| Query | Large (ms) | Estimate at 100× (large × 5, ms) | Target (ms) | Status |
|-------|-----------:|--------------------------------:|------------:|--------|
| W04 | 1,171.8 | 5,859.1 | 3,000 | over target |
| R13 | 85.42 | 427.1 | 250 | over target |
| R20 | 1,638.0 | 8,190.2 | 5,000 | over target |
| R25 | 54.49 | 272.4 | 250 | over target |
| R19 | 877.5 | 4,387.7 | 5,000 | close (above half the target) |
| R18 | 456.6 | 2,283.1 | 5,000 | ok |
| R15 | 21.81 | 109.0 | 250 | ok |
| R16 | 239.5 | 1,197.4 | 5,000 | ok |
| R17 | 232.8 | 1,163.8 | 5,000 | ok |
| R24 | 185.9 | 929.7 | 5,000 | ok |
| R07 | 176.7 | 883.5 | 5,000 | ok |
| R14 | 175.4 | 877.2 | 5,000 | ok |
| R10 | 140.3 | 701.7 | 5,000 | ok |
| R12 | 127.2 | 636.0 | 5,000 | ok |

**Confidence: medium to low.** The estimate ignores that the spills in section 2.4 get worse when a hash or sort is 5× bigger, and that the first cold run inflates some of the averages. By this estimate R13, R20, R25, W04 would exceed their targets at 100×. Two of them are interactive queries (R13, R25, target 250 ms) and two are report/batch queries (R20, W04). What we would do, in order of effort, and none of it is built or tested:
- **Summary tables** maintained by the nightly job: a table of streams per (day, platform), per (day, country, hour) and per (day, track) would answer R10, R18, R20, R25 and most of R07/R16 by reading thousands of rows instead of millions. The cost is freshness (one day, as with R22) and a job that must be correct.
- **Incremental W04**: only stream rows since the last run are read, and a small table (artist, user, day) keeps the distinct listeners of the last 28 days. `count(DISTINCT user_id)` cannot be added up from daily totals, which is why the extra table is needed.
- **R13** (public playlists never played): keep a `play_count` per playlist (or a "last played" column) up to date instead of probing `streams` once per playlist.

### 5.2 Partitioning

**Table and column.** `streams`, by **RANGE on `started_at`**, one partition per month. `streams` is 53% of the database, it only grows by appending new rows with newer timestamps, most analytics filter by a time window (R07, R10, R16, R17, R23, W04), and old months are rarely read. LIST would need a small set of fixed values and HASH on `user_id` would spread each month over all partitions, which loses both pruning by time and cheap archiving.

**DDL** (full script: `sql/08_partitioning.sql`; it builds a partitioned copy `spotify_part.streams` in the large database, measures it and drops it, so the benchmarked tables are untouched; output in `benchmarks/results/large/partitioning.txt`):

```sql
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
    CONSTRAINT pk_streams_part PRIMARY KEY (stream_id, started_at)   -- must contain the partition key
    -- ... the same CHECK constraints as spotify.streams
) PARTITION BY RANGE (started_at);

CREATE TABLE spotify_part.streams_2026_06 PARTITION OF spotify_part.streams
    FOR VALUES FROM ('2026-06-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');   -- 18 monthly partitions, Jan 2025 to Jun 2026
CREATE TABLE spotify_part.streams_default PARTITION OF spotify_part.streams DEFAULT;  -- catches rows outside every range
```

The 18 monthly partitions hold between 256,410 and 283,883 rows each (20 to 23 MB of table and 41 to 45 MB of indexes); the default partition is empty. Together they take 399 MB, the same as the plain table. Note that W01 inserts a stream dated 2026-07-01: with these partitions it would land in the default partition, so a real system must create next month's partition ahead of time (a scheduled `CREATE TABLE ... PARTITION OF`).

**Primary-key rule.** On a partitioned table every PRIMARY KEY or UNIQUE constraint must contain the partition key. `streams` has `PRIMARY KEY (stream_id)`, and PostgreSQL refuses it (the error is in `partitioning.txt`, from a test table):

```
ERROR:  unique constraint on partitioned table must include all partitioning columns
DETAIL:  PRIMARY KEY constraint on table "pk_test" lacks column "started_at" which is part of the partition key.
```

So the key becomes `(stream_id, started_at)`. The consequence is real: the database no longer guarantees that `stream_id` alone is unique, because two rows with the same id in different months would be accepted. The identity column still hands out unique values, but a manually inserted duplicate would pass. No other table has a foreign key to `streams`, so nothing else breaks. If a global uniqueness guarantee is needed, it has to be enforced by the application or by a separate unique table of ids.

**Pruning shown with `EXPLAIN`.** A query for June 2026 (R10) touches one partition out of 19:

```
                                                                               QUERY PLAN                                                                               
------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 GroupAggregate
   Group Key: ((streams.started_at)::date), streams.platform
   ->  Sort
         Sort Key: ((streams.started_at)::date), streams.platform
         ->  Seq Scan on streams_2026_06 streams
               Filter: ((started_at >= '2026-06-01 00:00:00+05:30'::timestamp with time zone) AND (started_at < '2026-07-01 00:00:00+05:30'::timestamp with time zone))
(6 rows)
```

A query without a date (R04, one user's last 50 streams) cannot be pruned: it needs an index scan on each of the 18 monthly partitions plus a scan of the empty default partition, 84 pages in total in the timed run (`partitioning.txt`).

**Did it make the queries faster? No, not at this size.** Same queries, same data, 3 runs each, plain table against partitioned copy (averages, ms; `partitioning.txt`):

| Query | Plain `streams` | Partitioned | Partitions read |
|-------|----------------:|------------:|----------------:|
| R10 | 139.9 | 136.2 | 1 of 19 |
| R07 | 159.5 | 894.6 | 1 of 19 |
| R16 | 218.7 | 978.7 | 2 of 19 (June + default) |
| R04 | 0.330 | 0.253 | 19 of 19 |
| R18 | 400.2 | 530.8 | 19 of 19 |

R10 and R04 did not change. **R07 became 5.6× and R16 4.5× slower, although pruning worked** (only the June partition is read). The plans show why: on the partition the planner no longer used the covering index and the parallel hash join; it chose a sequential scan of the June partition and a nested loop with a Memoize node, which probes `track_artists` once per stream row (R07: 197,306 index searches, 594,725 buffer hits and no parallel workers, against 10,441 pages (2,415 hits and 8,026 reads) and a parallel hash join on the plain table). That is a different plan, not a cost of pruning, and we did not try to tune it, so we cannot say it is unfixable; we can say that partitioning does not come for free and that every report query has to be re-checked after the change. R18 reads all partitions and became 1.33× slower (the extra `Append` and per-partition overhead).

**So why partition?** For maintenance, not for speed (section 5.5): an old month can be detached and archived in one statement, each partition has its own indexes (41 to 45 MB instead of one set of 732 MB), which are built and vacuumed per partition, and a bad month can be rebuilt without touching the rest. **Our recommendation:** do not partition at 20× (5 million rows, it gains nothing we could measure); introduce monthly partitioning before the 100× volume, together with the archiving process, after re-checking R07, R16 and the other report queries on the partitioned table. Confidence: medium; we tested one partitioning scheme at one size.

### 5.3 Sharding

**Size does not force it.** Our estimate for 100× is about 5 × 2.1 GB ≈ 10 GB, which fits on one server. What would force sharding is write rate and CPU for the reports, which we did not measure. We would first use partitioning, replicas and summary tables (5.1, 5.2, 5.4), and shard only when one node runs out of write or CPU capacity.

**If we had to shard, we would shard `streams` by `user_id` (hash)**, together with `users`, `liked_tracks`, `artist_follows`, `playlists` and `playlist_tracks` (by playlist owner), and replicate the small, read-mostly tables (`artists`, `albums`, `tracks`, `track_artists`) to every shard. The reasoning, from our own queries:
- The real-time, listener-facing queries are all about **one user**: R04 (Recently Played), R06, R09, W01, W02, W03. Sharded by user, each of them goes to exactly one shard, which keeps them at their 5 ms target. Sharded by track or artist, R04 and R09 would have to ask every shard.
- Sharded by user, the artist and report queries become **cross-shard**: R01, R07, R08, R16, R19, R25, W04 (per artist or track over all users) and R10, R18, R20, R23 (all streams). R12 and R17 stay local to a shard (they group by user) and only need a final merge.
- Most of these can be handled by running the query on every shard and **merging the partial results**: counts and sums are added (R10, R18, R20, R08's skip rate from summed counts), maxima are taken again (R19), and `count(DISTINCT user_id)` per artist (R16, W04) can simply be **added up, because every user lives on exactly one shard**, so the distinct sets of different shards never overlap. That is the main advantage of sharding by user for these two queries.
- Two cases are harder. R07 (top 20 artists) needs the full per-artist counts from each shard, since an artist outside every shard's top 20 can still be in the global top 20. R23 (page 8,001 of all streams) needs the first 200,025 rows of every shard sorted together, so it must be replaced by keyset pagination. W05 (takedown) deletes `playlist_tracks` rows by track across all shards, so it is a write to every shard.
- **By time** (one shard per month) is the worst choice for the workload: all writes and all "last 28 days" reads would hit the newest shard. Time is handled better inside one node by partitioning. **By track or artist** makes R01, R08, R16 and R19 single-shard, but puts the most latency-sensitive path (R04) on every shard.

### 5.4 Read replicas and caching

| Where | Queries | Why |
|-------|---------|-----|
| **Primary only** | W01, W02, W03, W04, W05 | They write. |
| **Primary** (cheap, and a user must see their own change at once) | R04 Recently Played (after W01), R05 playlist page (after W03), R06 Liked Songs (after W02) | A replica can lag behind, so a listener could miss the track just played or just liked. They take 0.1 to 1.1 ms, so keeping them on the primary costs very little. |
| **Replica** (stale by a few seconds is fine) | R01, R03, R08, R09, R11, R15, R21 | Artist pages, search, Wrapped (2025 is closed), Release Radar, ISRC lookup. Index lookups that are fast anyway; the replica takes read load off the primary. |
| **Replica** (heavy, can be minutes or a day old) | R07, R10, R12, R13, R14, R16, R17, R18, R19, R20, R22, R23, R24, R25 | Reports and analytics. They scan a share of the tables for hundreds of ms; they must not compete with the listener queries on the primary. R22 reads its materialized view, refreshed on the primary and replicated. |
| **Cache candidates** | R02, R21, R03 (popular searches), R16/R10/R18 (dashboards) | Their results change rarely or are read many times. |

Two cautions. First, **caching outside the database was not used and is not in any number of this report**; the replica and cache columns are a design, not measurements. Second, R02 (an album tracklist) and R21 (an ISRC lookup) take 0.1 to 0.2 ms, so a cache would hardly help them; the useful caches are the expensive, repeated ones (dashboards R10, R18, R20, and the monthly-listener numbers R16, which W04 already stores in `artists.monthly_listeners`). R16 is in fact a recomputation of that column.

### 5.5 Maintenance

- **VACUUM / autovacuum for `streams`.** `streams` is append-only (inserts only), so there are almost no dead rows, but our fastest plans are **Index Only Scans** (R10, R17, R23, W04 and others) that depend on the **visibility map**, which VACUUM sets. After our `VACUUM (ANALYZE)` those scans show `Heap Fetches: 67` on 5,000,000 rows; if the map goes stale the heap fetches grow and the scans slow down. By default autovacuum starts after 20% new rows (1 million at today's size, 5 million at 100×). We would lower it for this table, for example `ALTER TABLE streams SET (autovacuum_vacuum_insert_scale_factor = 0.01, autovacuum_analyze_scale_factor = 0.01);` (50,000 new rows at 5 million), and watch `pg_stat_user_tables.last_autovacuum`. This is a proposal that we did not test. With partitioning, autovacuum works per partition but never analyzes the parent table, so `ANALYZE streams;` must be scheduled.
- **`artists` after W04.** The nightly job rewrites every artist row; `monthly_listeners` is not indexed, so these updates can be heap-only, and autovacuum on this small table must keep up. A lower `fillfactor` (for example 90) on `artists` would leave room for that. Untested.
- **Archiving old data.** With monthly partitions an old month is archived in one statement: `ALTER TABLE streams DETACH PARTITION streams_2025_01;` followed by a dump or a move to cheaper storage and `DROP TABLE`. In our DDL there is a default partition, and PostgreSQL then **refuses** `DETACH PARTITION ... CONCURRENTLY` ("cannot detach partitions concurrently when a default partition exists"; we tested this on PostgreSQL 16), so a plain `DETACH` is used, which takes a short exclusive lock on the parent. We would keep 18 to 24 months online; reports older than that read the archive.
- **Summary tables and materialized views.** `mv_playlist_duplicates` is refreshed every night with `REFRESH MATERIALIZED VIEW CONCURRENTLY` after W04. The summary tables of section 5.1 would be filled by the same nightly job, for the previous day only, and the job must check that yesterday's totals match `streams` before it replaces them.
- **Statistics.** `CREATE STATISTICS st_streams_hour` (Phase 4) and an `ANALYZE` after every large load keep the plans stable; the plan changes in section 3.2 followed the larger row counts, so statistics must be current after each bulk load.

## 6. Conclusion

**Is the database ready for next year (20× the volume)? Yes, with one fix and some caveats.** All 30 queries meet their targets on the 20× data. The single failure (R22, 527.9 ms) was fixed with a materialized view (9.631 ms). The data did not change, the SQL of the other 29 queries is unchanged since Phase 4, and no server setting was touched. Confidence: **high** that the targets are met on this machine, **medium** on other hardware.

**Smallest margins** (target ÷ measured, final run):

| Query | Measured (ms) | Target (ms) | Headroom |
|-------|--------------:|------------:|---------:|
| W04 | 1,171.8 | 3,000 | 2.6× |
| R13 | 85.42 | 250 | 2.9× |
| R20 | 1,638.0 | 5,000 | 3.1× |
| W01 | 1.633 | 5 | 3.1× |
| W03 | 1.472 | 5 | 3.4× |
| W02 | 1.286 | 5 | 3.9× |

**Remaining risks**
1. **One machine, three runs.** The numbers come from one laptop (MacBook Pro M4, local SSD) and vary between runs (section 2.5). If the grading machine were about 2.6× slower, W04 would miss its target; at about 3× slower R20 would, too.
2. **100× is not safe yet.** By our estimate (section 5.1) R13, R25, R20 and W04 would exceed their targets, and R19 would come close. The fixes (summary tables, incremental W04) are designed, not built.
3. **R22 is up to a day stale** and depends on a nightly refresh that nobody has scheduled yet. If the refresh is forgotten, the list silently goes out of date.
4. **Spills and cache misses.** R10, R17, R20 and W04 already spill to disk or read from outside the cache on the large data; they get slower than linearly as the data grows.
5. **Write cost and index size.** The 9 indexes are 58% of the stored size, and every stream insert maintains up to 4 of them (W01: 0.6 → 1.6 ms). A much higher insert rate than the one we modelled would need partitioning and batching.
6. **Partitioning is not a free win.** It slowed R07 and R16 down in our test and changes the primary key of `streams` to `(stream_id, started_at)`.
7. **Synthetic data.** The large data is the faculty's scaled copy of the seed. Real listening is skewed (a few tracks and artists get most streams), and R01, R08 and R19 depend on that skew.

**What would change our conclusion:** a real hardware target with much slower storage or less memory; a measured insert rate; or a repeat of the benchmark with a warm and a cold run reported separately.

## Files for this report

| File | What it is |
|------|------------|
| `sql/09_scale_fixes.sql` | The R22 fix: materialized view, its indexes, and the proof that it returns the same rows |
| `sql/10_large_workload.sql` | The 30 queries for the large data (identical to `06`, except R22) |
| `sql/08_partitioning.sql` | The partitioned copy of `streams`, pruning and timings |
| `benchmarks/db_sizes.sql` | Database, table and index sizes |
| `benchmarks/results/large/` | Final large run: `summary.csv`, one `.txt` plan file per query, `partitioning.txt`, `db_sizes_*.txt`, `scale_fixes.txt` |
| `benchmarks/results/large_first_run/` | First large run, before the R22 fix |

