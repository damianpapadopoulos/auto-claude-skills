# DB-change REVIEW checklist (owned, vendor-neutral)
Before approving any schema/query/migration change, verify each of the five defect
classes below. For each, look for the stated signal, weigh it against the stated
threshold, and require the matching fix before sign-off.

## 1. Unsafe migration (blocking/locking DDL)
Not every ALTER is safe just because it "runs". Ask whether this DDL rewrites the
table or only touches metadata.
- Adding a column with a NOT NULL constraint and no DEFAULT forces a full table
  rewrite on many engines/versions — writes block until it finishes.
- Column type changes, PK changes, and adding a UNIQUE constraint on a populated
  table are rewrite-class operations. On a table over roughly 1M rows (or any table
  with meaningful write traffic) a rewrite-class ALTER needs an online/non-blocking
  execution path (chunked or background rebuild) or an explicit, reviewed downtime
  window — never a bare synchronous ALTER during business hours.
- Dropping an index: confirm no live query still depends on it (check application
  query patterns, not just the schema diff) before removing it — a dropped index
  that's still needed silently turns fast lookups into full scans.
- Backfills that populate a new column/table on a hot table should run in small,
  throttled batches with a resumable cursor, not a single UPDATE across the table.
Signal: DDL statement type, estimated row count of the target table, presence or
absence of DEFAULT. Fix: online schema-change tooling, chunked batch job, or a
signed-off maintenance window.

## 2. Missing index (unsupported filter/sort/join)
Any column driving a WHERE, JOIN, or ORDER BY needs a plan that uses an index, not
a scan.
- Read the query plan: EXPLAIN type `ALL` (MySQL) or a `Seq Scan` node (Postgres)
  on a table above a few thousand rows is the red flag — the engine is reading
  every row to find a handful.
- For multi-column indexes, order matters: equality-filtered columns first, then
  the column used for range/sort comparisons. An index on `(a, b, c)` serves
  `WHERE a = ? AND b = ?` and also `... ORDER BY c`, but does NOT serve a lookup on
  `b` alone — the engine can't skip the leading column.
- Watch for a plan where the index handles the WHERE clause but a separate sort
  step still appears (`Using filesort`, or a `Sort` node above the scan in
  Postgres) — the index doesn't cover the ORDER BY and the engine is sorting the
  result set in memory or on disk.
- `SELECT *` on a table where a narrower index could otherwise fully answer the
  query forces a lookup back to the base row — confirm the query actually needs
  every selected column before ruling out a covering index.
Signal: plan node type, row estimate, and which clause (filter/sort/join) is
unindexed. Fix: add a composite index ordered equality-then-range, or narrow the
SELECT list so an existing index can cover it.

## 3. N+1 (per-row query in a loop)
Look for a query issued once per item of a collection instead of once for the
whole collection.
- Pattern: a loop over IDs (from an earlier query or request payload) that opens a
  new DB call inside the loop body — 50 items in, 50 round trips out.
- Fix is a single set-based query: `WHERE id IN (...)` / `WHERE id = ANY(...)`, or
  a JOIN that pulls related rows alongside the parent rows in one round trip.
- ORM code is a common source — check for lazy-loaded associations accessed inside
  a loop (e.g. `for order in orders: order.customer.name`), which silently issues
  one query per iteration even though no SQL appears at that line.
- A handful of extra queries (two or three) for genuinely independent lookups is
  not the problem; the pattern to flag is a query count that scales with input
  size.
Signal: query call site inside a loop/iterator whose bound is a collection length.
Fix: batch into one IN/ANY query, or eager-load the association up front.

## 4. Offset pagination (deep OFFSET scans)
`LIMIT x OFFSET y` looks cheap but the engine still has to walk and discard the
first `y` rows before it can return anything.
- Small, first-page offsets (low hundreds) are fine. Once OFFSET climbs into the
  low thousands, or is effectively unbounded (a user can page indefinitely, or a
  job walks the whole table page by page), cost per page grows with how deep the
  page is — page 500 costs far more than page 1 for the same LIMIT.
- Fix is keyset/cursor pagination: carry the last row's sort key(s) forward and
  filter on them instead of counting rows to skip, e.g.
  `WHERE (created_at, id) < (last_seen) ORDER BY created_at DESC, id DESC LIMIT n`.
  This needs a composite index on the cursor columns to stay cheap at any depth.
- Also flag OFFSET-based pagination used for a background export or sync job —
  that's exactly the unbounded-depth case where the linear cost adds up fastest.
Signal: OFFSET magnitude and whether it's bounded by user behavior or can grow
without limit. Fix: cursor pagination on an indexed (sort_key, id) pair.

## 5. Lock risk (long transactions / broad locks / hot-row contention)
A change can be functionally correct and still stall concurrent traffic through
locking.
- `SELECT ... FOR UPDATE` (or any locking read) on a row or range that many
  requests hit concurrently — a "hot row" such as a counter, balance, or singleton
  config row — serializes every request that touches it. Flag it and ask whether
  the lock scope can shrink or the hot value can move to an append-only or
  optimistic-update pattern.
- A range scan used inside a locking statement without a supporting index locks
  every row (and gap) it has to examine to find matches, not just the rows it
  returns — an unindexed WHERE clause inside a transaction silently widens the
  blast radius.
- Transaction duration matters as much as scope: any transaction that does network
  calls, waits on user input, or otherwise stays open for more than a second or
  two is holding its locks — and, in MVCC engines, blocking cleanup of old row
  versions — for that whole span. Keep the transaction boundary tight around the
  actual writes.
- Watch for connections left idle mid-transaction (opened, then unrelated work
  happens, then a late commit) — these hold locks and old snapshots open with
  nothing visibly running, and are easy to miss in a code diff.
Signal: locking clause, whether the touched rows are contended, and transaction
span (does it wrap I/O beyond the DB calls themselves). Fix: narrow the lock
(index the predicate, shrink the row set), or shorten/split the transaction.

For each finding: name it, cite the line, state the risk, propose the smallest safe fix.
