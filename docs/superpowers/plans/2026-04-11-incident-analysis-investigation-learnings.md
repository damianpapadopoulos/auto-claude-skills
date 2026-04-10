# Incident-Analysis Skill Improvements — Investigation Learnings

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Encode four generalizable improvements into the incident-analysis skill based on the 2026-04-09 OCS logout investigation.

**Architecture:** Four targeted prose insertions into `skills/incident-analysis/SKILL.md`. No code changes. Step 2d (baseline-first gate) already exists from an earlier edit. The four new additions are: database metrics gate (Step 3), connection pool branching (Step 3c), parallel sweep pattern (Step 3c), and parallel execution constraint (Constraint 13).

**Tech Stack:** Markdown prose. Tests: `bash tests/run-tests.sh`.

---

### Task 1: Add Constraint 13 — Parallel Execution Strategy

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` — insert after Constraint 12 (after line 227, before `## Investigation Modes`)

- [ ] **Step 1: Insert Constraint 13**

Insert the following after the `URL construction templates and encoding rules: references/evidence-links.md.` line and before `## Investigation Modes`:

```markdown
### 13. Parallel Execution Strategy — Batch Independent Queries

When multiple independent queries are needed at the same investigation step, dispatch them in parallel rather than sequentially. Independence means the queries do not depend on each other's results to formulate the filter.

**Mandatory parallel batches:**

| Phase | What to batch | Why |
|-------|---------------|-----|
| Step 1 + Step 2 | Preflight + timezone detection + scope queries | No dependencies between them |
| Step 2b + 2c | Inventory queries + impact quantification | Independent data sources |
| Step 2d | Incident count + baseline count (per error signal) | Same query, different time window |
| Step 3 (intermediary found) | All-container ERROR inventory + deployment history + auth layer errors + HTTP status distribution | Architecture discovery — each query is independent |
| Step 3c (2+ services) | Per-service ERROR log queries (all services in one batch) | Same query template, different service filter |
| Step 3c item 3+4 | Deployment history + runtime signal (per service, all in one batch) | Independent per-service queries |
| Step 5 | Disconfirming query + per-service attribution queries | Independent verification checks |

**Always pair incident + baseline:** Every count or rate query should have a parallel twin for the baseline period (same service, same error class, same time-of-day on a prior day). This adds zero wall-clock time (parallel) and prevents deep-diving into baseline signals (Step 2d gate).

**When NOT to parallelize:** Queries that depend on a prior result to formulate the filter. For example, Step 4 (trace correlation) requires a trace_id from Step 3 exemplars — these must be sequential.

**Anti-pattern this prevents:** Sequential single-service discovery through an intermediary, where each service is found and queried one at a time. In one investigation, 5 services were discovered over ~5 minutes of sequential queries that could have been a single parallel batch.
```

- [ ] **Step 2: Verify syntax**

Run: `head -250 skills/incident-analysis/SKILL.md | tail -5` to confirm the constraint ends before `## Investigation Modes`.

- [ ] **Step 3: Run tests**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (constraint additions don't affect hook behavior).

- [ ] **Step 4: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat(incident-analysis): add Constraint 13 — parallel execution strategy"
```

---

### Task 2: Add Database Metrics Gate to Step 3

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` — insert after "Resource metrics (CPU, memory, latency) if available" (line 525) in Step 3: Single-Service Deep Dive

- [ ] **Step 1: Insert database metrics gate**

Insert after the line `- Resource metrics (CPU, memory, latency) if available` and before `- **Application-logic analysis (for the dominant error path):**`:

```markdown
- **Database/connection-pool metrics (conditional — when JDBC or connection errors are present):**

  When the service shows `JDBCConnectionException`, `acquisition timeout`, `pool exhausted`, `ConnectionRefused` to a database, or Cloud SQL proxy errors, **query the database's own metrics before attributing the issue to database capacity**. This is mandatory — do not conclude "database under pressure" or "connection starvation" from application-side errors alone.

  **Required queries (incident window + baseline, in parallel per Constraint 13):**

  | Metric | Tier 1 (`list_time_series`) | Tier 2 (REST API via `curl` + `gcloud auth print-access-token`) |
  |--------|----------------------------|----------------------------------------------------------------|
  | Connection count | `cloudsql.googleapis.com/database/network/connections` | Same metric via Monitoring REST API |
  | CPU utilization | `cloudsql.googleapis.com/database/cpu/utilization` | Same metric via Monitoring REST API |
  | Query rate | `cloudsql.googleapis.com/database/mysql/questions` (MySQL) or `cloudsql.googleapis.com/database/postgresql/transaction_count` (PostgreSQL) | Same metric via Monitoring REST API |

  **Decision branch:**

  | DB metrics vs baseline | Diagnosis | Investigation route |
  |------------------------|-----------|-------------------|
  | Connections, CPU, query rate all **normal** (within 1.5x baseline) | **App-side pool exhaustion** — connections held too long, not too many | Investigate application: slow queries holding connections, transaction scope changes, connection leak, pool sizing (max size, timeout, leak detection). Check deployment history for code changes affecting connection lifecycle. |
  | Connections **elevated** (approaching or at `max_connections`) | **Database-level exhaustion** — too many consumers | Investigate database: `max_connections` setting, per-service pool sizing, total connection demand across all consumers. Consider connection isolation (dedicated instances for critical services like auth). |
  | CPU **elevated** (>80%) or query rate **spiked** | **Database under load** — slow queries or query volume | Investigate database: slow query log, query plan regressions, lock contention. Check for new query patterns from recent deployments. |

  **Anti-pattern this prevents:** Concluding "shared database starvation" from application-side JDBC errors when the database itself is healthy. In one investigation, this led to incorrect action items ("isolate Keycloak DB") that were revised after Cloud SQL metrics showed normal connection count, CPU, and query rate — the issue was app-side pool exhaustion (connections held too long under normal DB load).
```

- [ ] **Step 2: Run tests**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat(incident-analysis): add database metrics gate before DB capacity conclusions"
```

---

### Task 3: Extend Connection Pool Exhaustion in Step 3c with Branching Logic

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` — extend Step 3c item 2, after the connection pool exhaustion bullet (line 600)

- [ ] **Step 1: Extend the connection pool bullet**

Replace the line:
```
   - **Connection pool exhaustion** (`JDBCConnectionException`, `Acquisition timeout`, `pool exhausted`) — indicates this service is an epicenter, not just a victim
```

With:
```markdown
   - **Connection pool exhaustion** (`JDBCConnectionException`, `Acquisition timeout`, `pool exhausted`) — indicates this service is an epicenter, not just a victim. **When found, trigger the database metrics gate (Step 3) for this service's backing database before proceeding.** The gate determines whether the exhaustion is app-side (connections held too long — normal DB metrics) or database-level (DB at capacity — elevated DB metrics). Record `pool_exhaustion_type: "app-side" | "database-level" | "not_determined"` in the service inventory. Different types require different action items: app-side → investigate application connection lifecycle; database-level → investigate DB capacity and connection isolation.
```

- [ ] **Step 2: Run tests**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat(incident-analysis): add app-side vs database-level pool exhaustion branching"
```

---

### Task 4: Add Parallel Breadth-First Sweep to Step 3c

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` — insert between the Step 3c gate paragraph and the `**Procedure:**` line (between lines 591 and 593)

- [ ] **Step 1: Insert parallel sweep pattern**

Insert after the gate paragraph (`Skip only for confirmed single-service incidents with no cross-service error signals.`) and before `**Procedure:**`:

```markdown
**Parallel sweep pattern (Constraint 13):** When the error chain involves 3+ services (typically discovered through an intermediary layer), dispatch the per-service queries in parallel rather than sequentially. Specifically:

1. **Architecture discovery batch (one parallel round):** Query all containers in the namespace with ERROR logs grouped by container name + deployment history for the 72h window + auth/identity service errors. This reveals the full service landscape and recent changes in a single round-trip instead of discovering services one at a time.

2. **Per-service sweep batch (one parallel round):** For each service identified in the architecture discovery, dispatch items 1-3 of the procedure below (ERROR logs + error classification + deployment history) as parallel queries. Each query is independent — they target different services with the same query template.

3. **Baseline comparison batch (one parallel round):** For each service's error count from the sweep, query the baseline count from a prior day in parallel. Feed results into the Step 2d baseline-first gate to skip baseline signals before deep-diving.

This pattern collapses an N-service sequential sweep (N round-trips) into 3 parallel rounds regardless of N. The procedure below describes what to query per service; this pattern describes how to batch the execution.
```

- [ ] **Step 2: Run tests**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add skills/incident-analysis/SKILL.md
git commit -m "feat(incident-analysis): add parallel breadth-first sweep pattern to Step 3c"
```

---

### Task 5: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

- [ ] **Step 2: Verify SKILL.md line count is reasonable**

Run: `wc -l skills/incident-analysis/SKILL.md`
Expected: ~1180-1200 lines (was 1121 + ~70 lines of additions).

- [ ] **Step 3: Verify constraint numbering**

Run: `grep -n "^### [0-9]" skills/incident-analysis/SKILL.md`
Expected: Constraints 1-13 in sequence, no gaps.

- [ ] **Step 4: Spot-check cross-references**

Verify that:
- Step 3 database metrics gate references "Constraint 13" for parallel queries
- Step 3c parallel sweep references "Step 2d" for baseline gate
- Step 3c connection pool bullet references "Step 3 database metrics gate"
- Constraint 13 references "Step 2d", "Step 3c"
