# Section request concurrency

Run `swift test --filter RequestConcurrencyTests` to repeat the isolated request test. It uses injected credentials and URLProtocol responses; no GitHub requests or local profile access occur.

Twelve independent sections, each with a 100 ms synthetic response delay, produced 12 simultaneously active requests before the change. The rolling four-section window produces a measured peak of 4 and still completes all 12 sections in configuration order. Cancellation does not start the remaining sections. This is a concurrency measurement, not a GitHub latency or throughput benchmark.

Each worker completes its section's search and required review-thread pages before the next section starts. Team membership checks follow collection as before. Existing pagination tests cover fetching beyond the first page; the limit changes scheduling only. Four is a conservative fixed cap, not an experimentally optimal value. There is no new retry loop or backoff policy.
