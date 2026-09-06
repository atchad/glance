# Local queue-cost diagnostic

Run `GLANCE_BENCHMARK=1 swift test -c release --filter QueueCostTests`.

This opt-in diagnostic uses a temporary profile and injected snapshots, with no GitHub requests or notifications. Five overlapping sections contain the same unique PRs. It reports the median of five refreshes (including cache persistence and one section's visible-row calculation), one search/navigation construction, and cache size. It asserts refresh success and the row count; timings are observations, not CI thresholds.

September 5, Apple Silicon, release build:

| Unique PRs | Row occurrences | Refresh median | Search/navigation | Cache size |
|---:|---:|---:|---:|---:|
| 100 | 500 | 7.9 ms | 7.6 ms | 0.43 MB |
| 1,000 | 5,000 | 74.0 ms | 90.2 ms | 4.30 MB |
| 5,000 | 25,000 | 350.0 ms | 354.8 ms | 21.52 MB |

These synthetic large queues show measurable synchronous work. They do not measure rendered scrolling, GitHub latency, rate limits, or requests with many reviews/checks. The fixture repeats ordinary PR metadata and contains no active snoozes. Numbers depend on hardware and concurrent load; rerun on the target machine.

Do not infer a networking fix from these timings. Section queries currently execute independently, including overlap; each section needs at least one search request and more pages as needed. Team membership and incomplete review threads can add requests. Measure request concurrency separately before choosing a limit or retry policy. Preserve GitHub's retry guidance; an immediate retry loop would increase load.
