# DB-defect taxonomy (frozen)
1. unsafe-migration — blocking/locking DDL on a large table: ALTER ADD COLUMN NOT NULL without default, dropping an in-use index, non-online schema change causing downtime.
2. missing-index — a query whose predicate/sort has no supporting index → full scan (type: ALL / Seq Scan).
3. n-plus-one — per-row query inside a loop instead of a set-based/join/batched query.
4. offset-pagination — LIMIT/OFFSET deep pagination on a large table instead of keyset/cursor pagination.
5. lock-risk — long-held transaction / broad row or gap locks / SELECT ... FOR UPDATE hot path causing contention.
