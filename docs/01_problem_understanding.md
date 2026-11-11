# Phase 1: Problem understanding (Team T0028)

Nine problems were reported on the Spotify India database. For each one: what the business needs, who is affected,
and the type. **Real-time** means a person is waiting on a screen or an app call. **Reporting** means a job or
dashboard that can take longer. The type sets our performance target in Phase 4.

| # | What the business needs | Stakeholder | Type | Queries |
|---|---|---|---|---|
| P1 | Artist, album and playlist pages open instantly, even for popular artists | Listeners (free and Premium) | **Real-time** | R01, R02, R05 |
| P2 | Search, Recently played and Liked Songs stay fast for heavy listeners; logging a play and pressing the heart never slows the player | Heavy listeners | **Real-time** | R03, R04, R06, W01, W02 |
| P3 | Live artist stats: skip rate, fans also like, listener counts; the nightly recompute fits its window | Artists (Spotify for Artists) | Real-time (R08, R15); reporting (R16, W04) | R08, R15, R16, W04 |
| P4 | Exact royalty counts (30-second rule) and fast lookup of one recording by ISRC | Labels, rights holders, finance | R21 real-time; R07, R24 reporting (exactness first) | R07, R21, R24, W05 |
| P5 | "Public playlists never played" returns nothing: a **wrong result**, not a speed problem | Curation team | Reporting (correctness first) | R13 |
| P6 | Wrapped, Release Radar and new-release discovery jobs finish in time | Personalization team | Reporting / batch (R11 near real-time) | R09, R11, R25 |
| P7 | Find explicit tracks streamed by users who were under 18 **on the stream date** | Compliance | Reporting (correctness first) | R12 |
| P8 | Adding a track, collaborative stats and duplicate clean-up are fast | Playlist users and team | W03 real-time; R14, R22 reporting | R14, R22, W03 |
| P9 | Analytics (upsell list, daily streams, offline share, hourly pattern, artist report) stop timing out; streams will grow **20x** | Growth and platform analytics | Reporting | R10, R17-R20, R23 |

**Why the type matters.** Real-time queries run on every screen open, so they must take milliseconds and must not
slow down as streams grow. Reporting queries may take seconds but must survive 20x the data and return exactly the
same results. Correctness problems (P5, and the exactness of P4 and P7) are fixed by rewriting the query, not by
adding an index: R13 fails because `NOT IN` meets `NULL` values in `streams.playlist_id` (check B5 in
`sql/03_integrity_checks.sql`).

**Assumptions**
1. Our performance targets are working numbers, to be confirmed against the Phase 3 baseline.
2. "Last 28 days" and "June 2026" are measured against the end of the data (30 Jun 2026), as the queries do.
3. A stream earns royalties when `ms_played >= 30000`; no other royalty rule is used.
4. Under-18 is judged on the stream date, as R12 already does. All timestamps are India time (+05:30).
5. The 10 exported files are the full truth of the current system.
