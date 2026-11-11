# Phase 1: Problem understanding (Team T0028)

Spotify India data team. The database has no documentation, and nine problems were reported. For each one:
what the business needs, who is affected, and whether it is **real-time** (a person is waiting on a screen or
an app call) or **reporting / analytics** (a job or a dashboard that can take longer). The type decides the
performance target we aim for in Phase 4.

| # | What the business really needs | Stakeholder | Type | Queries |
|---|--------------------------------|-------------|------|---------|
| P1 | Artist, album and playlist pages must open instantly, even for artists with millions of plays. The page needs the top tracks of the last 28 days, a tracklist, and a playlist with all artists per track. | Listeners (free and Premium) | **Real-time** | R01, R02, R05 |
| P2 | Search, "Recently played" and "Liked Songs" must stay quick for heavy listeners. Logging a play and pressing the heart must not slow the player. | Listeners (heavy users, free and Premium) | **Real-time** | R03, R04, R06, W01, W02 |
| P3 | Artists want their stats live: skip rate per track, fans also like, and listener counts. The nightly listener recompute must finish in its window. | Artists (Spotify for Artists), their labels | **Real-time** for the dashboard (R08, R15), **reporting** for R16 and W04 | R08, R15, R16, W04 |
| P4 | Royalties are paid on streams of 30 seconds or more, so the count must be **exact**. Rights holders look up one recording by its ISRC. | Labels / rights holders, royalties and finance | R21 **real-time** lookup; R07, R24 **reporting** (exactness matters more than speed); W05 takedown is a **write** | R07, R21, R24, W05 |
| P5 | "Public playlists never played" returns nothing, so the curation team cannot find dead playlists. This is a **wrong result**, not a speed problem. | Curation team | **Reporting** (correctness first) | R13 |
| P6 | Wrapped, Release Radar and new-release discovery run as batch jobs and take too long. | Personalization team, listeners (as consumers of the output) | **Reporting / batch** (R11 is per user and close to real-time) | R09, R11, R25 |
| P7 | Compliance must find explicit tracks streamed by users who were under 18 **on the day of the stream**. | Compliance | **Reporting** (correctness first) | R12 |
| P8 | Adding a track to a playlist, collaborative-playlist stats and duplicate clean-up are slow. | Playlist users, playlist-features team | W03 **real-time**; R14, R22 **reporting** | R14, R22, W03 |
| P9 | Growth and platform analytics time out, and streams will grow **20x** (250,000 now, about 5 million). | Growth and platform analytics teams (upsell, hourly patterns, platform mix) | **Reporting / analytics** | R10, R17, R18, R19, R20, R23 |

## Why this classification matters
- **Real-time** queries (P1, P2, P3 dashboard, R21, W01-W03) are called on every screen open, so we target a
  time of a few milliseconds to tens of milliseconds per query, and they must not get slower as streams grow.
- **Reporting** queries (P4, P6, P7, P9 and the rest) run on a schedule or on demand. Seconds are acceptable, but
  they must scale to 20x the data and must return exactly the same results as the original query.
- **Correctness problems** (P5, and the exactness of P4 and P7) are fixed by rewriting the query, not by adding
  an index. For R13 the cause is that `NOT IN` meets `NULL` values in `streams.playlist_id` (checked in
  `sql/03_integrity_checks.sql`, B5).

## Assumptions
1. The performance targets above are our own working numbers, to be confirmed against the Phase 3 baseline.
2. "Last 28 days" and "June 2026" are measured against the end of the data (30 Jun 2026), as the queries do.
3. A stream earns royalties when `ms_played >= 30000`; this is the only royalty rule used.
4. Under-18 is judged on the stream date, not on today's date (R12 already does this).
5. All timestamps are in India time (+05:30), as in the export.
6. The seed data is the full truth of the current system; nothing outside the 10 exports exists.
7. Deleting a listener's account must not remove royalty-bearing streams (see delete rules in `docs/02`).
