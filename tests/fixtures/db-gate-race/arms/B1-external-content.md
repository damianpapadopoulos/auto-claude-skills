<!-- PROVENANCE: external content, verbatim vendor wording from planetscale/database-skills
     (skills/mysql + skills/postgres, SKILL.md + references/). MUST NOT be shown to the Task 3
     corpus author (blind constraint applies only to the corpus author, not this arm). Hosting
     marketing blocks stripped; only review-relevant technical guidance retained. -->

# DB review guidance (source: planetscale/database-skills, mysql + postgres)

## EXPLAIN red flags
Access Types (Best → Worst): `system` → `const` → `eq_ref` → `ref` → `range` → `index` (full
index scan) → `ALL` (full table scan). Target `ref` or better. `ALL` on >1000 rows almost
always needs an index.

Key Extra Flags:
| Flag | Meaning | Action |
|---|---|---|
| `Using index` | Covering index (optimal) | None |
| `Using filesort` | Sort not via index | Index the ORDER BY columns |
| `Using temporary` | Temp table for GROUP BY | Index the grouped columns |
| `Using join buffer` | No index on join column | Add index on join column |

`ORDER BY + LIMIT` without an index: `LIMIT` does not automatically make sorting cheap. If no
index supports the order, MySQL may sort many rows (`Using filesort`) and then apply LIMIT.

## Composite / covering indexing rules
Leftmost Prefix Rule — Index `(a, b, c)` is usable for `WHERE a`, `WHERE a AND b`, and
`WHERE a AND b AND c`; NOT usable for `WHERE b` alone (the search must start from the
leftmost column). Column order: equality first, then range/sort — range predicates
(`>`, `<`, `BETWEEN`, `LIKE 'prefix%'`) stop index usage for filtering subsequent columns.

A covering index contains all columns a query needs — the engine satisfies it from the index
alone (`Using index` in EXPLAIN Extra, no table lookups). Pitfall: `SELECT *` defeats
covering indexes — select only the columns you need.

Postgres: always index foreign key columns (PostgreSQL does not auto-create these); index
columns in WHERE, JOIN, and ORDER BY clauses; verify with EXPLAIN ANALYZE that indexes are
actually used.

## Cursor vs OFFSET pagination
Cursor pagination, not `OFFSET`. `OFFSET N` scans and discards N rows.

```sql
-- Bad: OFFSET 10000 scans 10020 rows
SELECT id, title FROM article ORDER BY created_at DESC LIMIT 20 OFFSET 10000;
-- Good: cursor-based (requires index on (created_at DESC, id DESC))
SELECT id, title FROM article
WHERE (created_at, id) < ('2025-06-15T12:00:00Z', 987654)
ORDER BY created_at DESC, id DESC LIMIT 20;
```

## N+1 detection
The N+1 pattern occurs when you fetch N parent records, then execute N additional queries
(one per parent) to fetch related data. Queries inside loops → batch with ANY/IN:

```python
# Bad
for uid in user_ids:
    cursor.execute("SELECT name FROM user WHERE id = %s", (uid,))
# Good (Postgres specific)
cursor.execute("SELECT id, name FROM user WHERE id = ANY(%s)", (list(user_ids),))
```

## Online DDL / migration safety
Not all `ALTER TABLE` is equal — some block writes for the entire duration.

| Algorithm | What Happens | DML During? |
|---|---|---|
| `INSTANT` | Metadata-only change | Yes |
| `INPLACE` | Rebuilds in background | Usually yes |
| `COPY` | Full table copy to tmp table | **Blocked** |

Always request `LOCK=NONE` (and an explicit `ALGORITHM`) to surface conflicts early instead
of silently falling back to a more blocking method. On huge tables, consider external tools:
pt-online-schema-change or gh-ost (triggerless, uses binlog stream, preferred for high-write
tables). Never run `ALTER TABLE` on production without checking the algorithm — a surprise
`COPY` on a 100M-row table can lock writes for hours.

## Transactions & locking
InnoDB's default isolation level (REPEATABLE READ) uses next-key locks for locking reads
(`SELECT ... FOR UPDATE`, `UPDATE`, `DELETE`) to prevent phantom reads — a range scan locks
every gap in that range. If the WHERE column has no index, InnoDB must scan all rows and
locks every row examined. Keep transactions short — hold locks for milliseconds, not seconds.

Postgres: a single long-running transaction blocks VACUUM from removing dead tuples across
the entire database, causing table bloat and slower queries. `idle_in_transaction`
connections are the #1 operational MVCC issue — set `idle_in_transaction_session_timeout`
(30s–5min). Apps must handle "could not serialize access" with retry logic.
