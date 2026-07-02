# DB-change REVIEW checklist (owned, vendor-neutral)
Before approving any schema/query/migration change, verify each:
- Migration safety: does any DDL lock or rewrite a large table? Require online/non-blocking
  path (or explicit downtime sign-off). Flag ADD COLUMN NOT NULL without default; flag
  dropping an index that queries still use.
- Indexing: does every filtered/sorted/joined column have a supporting index? Flag full
  scans (EXPLAIN type: ALL / Seq Scan). Composite order = equality first, then range/sort.
- N+1: any query executed per-row in a loop? Require set-based / JOIN / batched rewrite.
- Pagination: LIMIT/OFFSET deep pagination on a large table → require keyset/cursor.
- Locking/transactions: long transactions, broad locks, or FOR UPDATE on a hot path →
  flag contention risk and narrow scope.
For each finding: name it, cite the line, state the risk, propose the smallest safe fix.
