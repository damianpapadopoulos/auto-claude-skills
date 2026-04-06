# Postmortem: OCS Access Failures — SpiceDB CPU Saturation + Calendar Deployment Regression

**Date:** 2026-03-09
**Author:** damian.papadopoulos (investigation), Claude Code (analysis)
**Status:** Draft
**Severity:** High

## 1. Summary

Coaches were unable to access OCS (ocs.ovivacoach.com) from approximately 13:09 UTC, with widespread reports starting at ~14:30 UTC on Monday 2026-03-09. The incident persisted through at least 16:59 UTC.

Two concurrent, independent issues caused coach-facing OCS failures:

**Issue 1 — SpiceDB CPU saturation (chronic, from at least 13:09 UTC):** SpiceDB, the shared authorization service, was chronically CPU-saturated (83-96% of its 1-core CPU limit across all 3 pods). `CheckPermission` gRPC calls took 1-3.5 seconds instead of sub-100ms. Backend services (`diet-suggestions`, `devices-integration`) with 3-second gRPC deadlines received intermittent `DEADLINE_EXCEEDED` errors, returning HTTP 500s. Amplified by an N+1 permission check pattern and gRPC HTTP/2 connection pinning.

**Issue 2 — Calendar v1.194.0-rc.0 deployment regression (from 14:12 UTC):** A FluxCD rolling update deployed calendar v1.194.0-rc.0 at 14:12:54. The new version introduced a `NoResultException` bug in `mustFindUserByLegacyId()` causing HTTP 500s on `/app/calendar/metadata.json`. Backend-core, which calls calendar for patient appointment data, received "EOF reached while reading" errors. Calendar does NOT depend on SpiceDB — its failures are entirely independent.

Both issues manifested through ocs-proxy as timeout errors, making them appear as a single incident to coaches.

## 2. Impact

**User impact:**
- Coaches experienced intermittent-to-persistent failures accessing OCS pages: patient lists, meal log analyses, calendar events, and device information
- Affected endpoints: `/diet-suggestions/meal-log-analyses`, `/rest/users/coaches.json`, `/rest/users/v3/patients.json`, `/rest/calendar/events.json`, `/content-engine/users/self/recipes`, `/app/device/devices.json`
- Multiple services returned HTTP 500 to end users
- Duration: at least 3h 50m (13:09 UTC first error — 16:59 UTC last confirmed error)
- Recovery time not verified — recovery mechanism unknown (not verified from evidence)

**Infrastructure scope:**
- 3 SpiceDB pods (all affected equally by CPU saturation)
- 3 ocs-proxy pods (all logging timeout errors)
- Backend services affected by SpiceDB saturation: `diet-suggestions`, `devices-integration`
- Backend services affected by calendar deployment: `calendar`, `backend-core` (via calendar)
- Also affected: `content-engine` (via ocs-proxy timeout, root cause not isolated)
- Cluster: `oviva-prod1`, namespace: `prod`, region: `europe-west3`
- Calendar deployment: v1.193.0 → v1.194.0-rc.0 via FluxCD at 14:12:54 UTC (rolling update completed 14:16:19)

## 3. Action Items

| Priority | Action | Current State | Owner | Due | Status |
|----------|--------|---------------|-------|-----|--------|
| P0 | Increase SpiceDB CPU limit from 1 core to 2 cores and request from 0.5 to 1 core | CPU request: 0.5, limit: 1.0, usage: 0.83-0.96 cores | ⚠ Owner needed | 2026-03-12 | Open |
| P0 | Add HPA for SpiceDB based on CPU utilization (target 70%) | No HPA configured; static 3 replicas | ⚠ Owner needed | 2026-03-16 | Open |
| P1 | Fix N+1 permission check in `diet-suggestions` `findMealLogsWithPermissionCheck` — batch `CheckPermission` calls or use `LookupResources` | Sequential `hasReadPermission()` per meal log via blocking gRPC | Squad Cosmos | 2026-03-23 | Open |
| P1 | Implement gRPC client-side load balancing for SpiceDB clients (round-robin or pick-first with periodic reconnect) to avoid HTTP/2 connection pinning | Clients use K8s Service ClusterIP (`10.208.1.65`); gRPC HTTP/2 pins all requests from one client to one pod | ⚠ Owner needed | 2026-03-23 | Open |
| P2 | Add SpiceDB latency alerting — alert when p95 `CheckPermission` latency exceeds 500ms for 5 minutes | No SpiceDB-specific latency alerting exists | ⚠ Owner needed | 2026-03-30 | Open |
| P0 | Investigate and fix calendar v1.194.0-rc.0 `NoResultException` regression in `mustFindUserByLegacyId` — users missing `ResourceDBVO` cause HTTP 500 on `/app/calendar/metadata.json` | Deployed at 14:12:54 via FluxCD; `NoResultException` confirmed in calendar-86d467c6f5 pods | Squad GlobalOperations | 2026-03-12 | Open |
| P2 | Investigate HTTP 431 (Request Header Fields Too Large) from calendar to backend-core | backend-core logs `Request failed with status code: 431` from calendar | Squad GlobalOperations | 2026-03-30 | Open |

## 4. Root Cause & Trigger

### Causal chains (two independent issues)

**Issue 1 — SpiceDB (chronic, no trigger):**
```
SpiceDB CPU saturation (chronic, 83-96% of 1-core limit)
  → CheckPermission latency 1-3.5s (should be <100ms)
    → gRPC DEADLINE_EXCEEDED after 3s client timeout
      → diet-suggestions, devices-integration return HTTP 500
        → ocs-proxy Apache ProxyTimeout exceeded
```

**Issue 2 — Calendar deployment (acute trigger at 14:12):**
```
FluxCD deploys calendar v1.194.0-rc.0 at 14:12:54
  → New version has NoResultException bug in mustFindUserByLegacyId()
    → GET /app/calendar/metadata.json returns HTTP 500
    → backend-core's CalendarClientImpl.fetchCalendarEvents() gets "EOF reached while reading"
      → GET /rest/users/v3/patients.json and /rest/calendar/events.json fail
        → ocs-proxy Apache ProxyTimeout exceeded
```

### Root cause 1 — SpiceDB CPU saturation (infrastructure)

SpiceDB was configured with a **1-core CPU limit** and **0.5-core CPU request** across 3 pods. Actual CPU usage was **0.83-0.96 cores per pod** — consistently at 83-96% of the limit throughout the observation window (13:35-15:30 UTC). This is a chronic condition, not triggered by any deployment or configuration change. `DEADLINE_EXCEEDED` errors appear as early as 13:09 UTC.

**Amplifying factors:**

1. **N+1 permission check pattern:** `diet-suggestions`'s `MealLogTemporaryReflectionFacade.findMealLogsWithPermissionCheck()` calls `hasReadPermission()` sequentially per meal log. With SpiceDB latency at ~1s per call, viewing 10 meal logs takes ~10 seconds — far exceeding any proxy timeout.

2. **gRPC connection pinning:** All SpiceDB clients connect via the K8s Service ClusterIP (`10.208.1.65:50051`). gRPC uses HTTP/2, which multiplexes requests over a single persistent connection. K8s Service load-balances at the connection level, not the request level. One dominant caller (pod `10.204.5.20`) sent 48% of SpiceDB calls in a sampled minute, all pinned to a single SpiceDB pod (`spicedb-6f7bcf799d-vd4cn`) via TCP port 40834.

### Root cause 2 — Calendar v1.194.0-rc.0 deployment regression

FluxCD deployed calendar from v1.193.0 to v1.194.0-rc.0 at **14:12:54 UTC** (rolling update completed 14:16:19). The new version introduced a data consistency issue: `ResourceDaoImpl.mustFindUserByLegacyId()` throws `NoResultException` for some users, causing HTTP 500 on `GET /app/calendar/metadata.json`.

**Evidence that calendar is independent from SpiceDB:**
- Calendar has **zero** `DEADLINE_EXCEEDED` errors in the incident window
- Calendar CPU was low (0.06-0.42 cores) — not resource-constrained
- Calendar errors are `NoResultException` (database query returning no rows) and `ConstraintViolationException` (duplicate key in domain event processing) — neither involve SpiceDB
- The error class (`mustFindUserByLegacyId` for users who exist) is consistent with a schema migration or query change in v1.194.0-rc.0

### Trigger (acute)

**SpiceDB:** No acute trigger. Chronic CPU saturation. Coach awareness at ~14:30 coincides with Monday afternoon peak hours.

**Calendar:** Acute trigger at 14:12:54 — FluxCD rolling deployment of v1.194.0-rc.0.

## 5. Timeline (all timestamps UTC)

| Timestamp | Precision | Event | Issue | Evidence Source |
|-----------|-----------|-------|-------|-----------------|
| 13:09:53 | exact | First `DEADLINE_EXCEEDED` error: `diet-suggestions` → SpiceDB `CheckPermission` after 3s | SpiceDB | diet-suggestions application logs |
| 13:11:41 | exact | `devices-integration` also hits SpiceDB `DEADLINE_EXCEEDED` on `/app/device/devices.json` | SpiceDB | devices-integration application logs |
| 14:12:51 | exact | FluxCD `HelmChartConfigured` — calendar v1.194.0-rc.0 detected | Calendar | k8s_cluster events |
| 14:12:54 | exact | Calendar rolling update begins: `calendar-86d467c6f5` scaled up, `calendar-777c5b9b` scaled down | Calendar | k8s_cluster events |
| 14:13:42 | exact | New calendar pods starting (Camel routes initializing) | Calendar | calendar application logs |
| 14:16:19 | exact | Calendar rollout complete: old ReplicaSet `calendar-777c5b9b` scaled to 0 | Calendar | k8s_cluster events |
| 14:20:00 | minute | New calendar pod CPU spike to 0.786 cores (Java JIT warmup) | Calendar | GCP container CPU metrics |
| ~14:30 | approximate | Coaches report OCS access issues | Both | User report |
| 14:30:00 | exact | SpiceDB CPU at 0.937 cores (pod 4r9qf), p50 latency 1042ms, 56% of calls >1000ms | SpiceDB | GCP metrics, SpiceDB gRPC logs |
| 14:32:13 | exact | Calendar `ConstraintViolationException` (duplicate entry in domain event processing) | Calendar | calendar application logs |
| 14:40:03 | exact | `backend-core` fails fetching calendar events: "EOF reached while reading" | Calendar | backend-core application logs |
| 14:41:35 | exact | Calendar HTTP 500 on `GET /app/calendar/metadata.json` (`NoResultException: mustFindUserByLegacyId`) | Calendar | calendar application logs |
| 14:42:31 | exact | First `ocs-proxy` timeout errors: `AH01102: timeout expired` proxying to `diet-suggestions:8080` | SpiceDB | ocs-proxy stderr logs |
| 14:43:54 | exact | `ocs-proxy` timeouts expand to `backend-core:8080` and `calendar:8080` | Both | ocs-proxy stderr logs |
| 15:55:29 | exact | SpiceDB `DEADLINE_EXCEEDED` errors continue in `diet-suggestions` | SpiceDB | diet-suggestions application logs |
| 15:59:51 | exact | `ocs-proxy` timeout errors continue to `backend-core:8080` | Both | ocs-proxy stderr logs |
| 16:59:04 | exact | Last confirmed `ocs-proxy` timeout error in investigation window | Both | ocs-proxy stderr logs |
| unknown | — | Recovery not verified — recovery mechanism unknown (not verified from evidence) | Both | — |

## 6. Contributing Factors

**1. SpiceDB CPU under-provisioning (most impactful for Issue 1)**
SpiceDB pods run at 83-96% of their 1-core CPU limit chronically. The 0.5-core request means Kubernetes only guarantees half a core — the rest depends on node headroom. No HPA is configured, so the deployment cannot scale with load.

**Capacity Context:**
- Current utilization: 0.83-0.96 cores vs 1.0 core limit (83-96%)
- Request coverage: 0.83-0.96 actual vs 0.5 requested (166-192% of request)
- HPA: not configured, static 3 replicas
- Chronic: CPU has been at this level across the full 2-hour observation window with no spikes — this is steady-state, not a burst

**2. Calendar v1.194.0-rc.0 deployment during business hours (most impactful for Issue 2)**
The FluxCD rolling update at 14:12 deployed a version with a data consistency bug (`mustFindUserByLegacyId` fails for some users). Deploying an `-rc.0` (release candidate) version to production during peak hours compounded the existing SpiceDB degradation.

**3. N+1 sequential permission checks in diet-suggestions**
Each `POST /app/meal-log-analyses` triggers sequential `CheckPermission` calls per meal log. This multiplies SpiceDB latency linearly and consumes SpiceDB capacity disproportionately.

**4. gRPC HTTP/2 connection pinning via K8s Service**
K8s Service provides L4 (connection-level) load balancing. gRPC's HTTP/2 multiplexing means all requests from one client travel over one persistent connection to one backend pod. This creates uneven load distribution across SpiceDB pods, with one caller potentially overloading one pod.

**5. Tight 3-second gRPC deadline**
The client-side gRPC deadline of 3 seconds provides insufficient headroom when SpiceDB p50 latency is already ~1 second. Any minor fluctuation pushes calls past the deadline.

**6. Two concurrent issues masked each other**
Because both issues manifested through ocs-proxy as identical timeout errors, they appeared as a single incident. This made diagnosis harder and could lead to an incomplete fix if only one root cause is addressed.

## 7. Lessons Learned

**What went well:**
- Structured logging with trace IDs and gRPC timing (`grpc.time_ms`) made it straightforward to trace the causal chain from proxy → backend → SpiceDB
- SpiceDB's `finished call` logs include latency, peer address, and gRPC status, enabling precise diagnosis

**What went wrong:**
- No SpiceDB-specific latency or CPU saturation alerting — the issue persisted for hours without automated detection
- SpiceDB CPU limits were set at 1 core without accounting for the growth in permission-check volume from new SpiceDB-integrated services
- The N+1 permission check pattern in `diet-suggestions` amplifies SpiceDB pressure and was not identified during development

**Where we got lucky:**
- The incident occurred during business hours when engineers were available, though no alert fired
- SpiceDB never crashed or entered CrashLoopBackOff — it degraded gracefully (slow but responding), preventing a total outage

## 8. Investigation Notes

### Hypotheses investigated

| Hypothesis | Status | Evidence |
|------------|--------|----------|
| SpiceDB CPU saturation causing slow `CheckPermission` | **Confirmed** | CPU 0.83-0.96 of 1.0 limit; p50 latency 1042ms; 56% of calls >1000ms |
| Calendar failures caused by SpiceDB saturation | **Disproved** | Zero DEADLINE_EXCEEDED in calendar logs; calendar CPU low (0.06-0.42 cores); calendar errors are NoResultException (DB query) not gRPC timeout |
| Calendar failures caused by v1.194.0-rc.0 deployment | **Confirmed** | FluxCD rollout at 14:12:54; new ReplicaSet `86d467c6f5`; NoResultException in `mustFindUserByLegacyId` absent in old version |
| Deployment triggered SpiceDB issue | **Ruled out** | No SpiceDB deployment; SpiceDB DEADLINE_EXCEEDED errors predate calendar deployment (13:09 vs 14:12) |
| Database (CloudSQL) issue | **Ruled out** | CloudSQL logs show only routine replication events and occasional idle connection aborts — no errors, no latency anomalies |
| Node resource exhaustion | **Ruled out** | SpiceDB pods spread across 3 nodes; CPU saturation is container-level, not node-level |
| Traffic spike triggered SpiceDB issue | **Not confirmed** | No baseline comparison available; SpiceDB CPU was flat (no spike); condition is chronic |
| gRPC load imbalance | **Confirmed (contributing)** | 48% of calls from one caller pinned to one pod via single TCP connection |

### Confidence levels

- **Root cause 1 (SpiceDB CPU saturation):** High — directly measured via metrics, corroborated by latency data
- **Root cause 2 (Calendar deployment regression):** High — FluxCD events prove deployment at 14:12; NoResultException confirmed in new pods; zero SpiceDB dependency proven
- **Calendar independence from SpiceDB:** High — zero DEADLINE_EXCEEDED in calendar, low CPU, error types are database-layer not gRPC
- **N+1 amplification:** High — confirmed from stack trace (`findMealLogsWithPermissionCheck` → per-item `hasReadPermission`)
- **gRPC pinning:** High — confirmed from SpiceDB server logs (single peer.address:port → single pod)
- **Recovery time:** Low — not verified; last error at 16:59, no confirmed recovery signal
- **Exact incident start:** Medium — first SpiceDB `DEADLINE_EXCEEDED` at 13:09; calendar deployment at 14:12; coaches noticed at ~14:30

### Open questions

1. What is the normal (pre-incident) SpiceDB `CheckPermission` latency? Is 1s the new baseline, or was it previously faster?
2. How many total `DEADLINE_EXCEEDED` errors occurred? (Only sampled — full count not retrieved)
3. Did the incident self-resolve with traffic decrease, or was there manual intervention?
4. Are other SpiceDB consumers (beyond the ones identified) also affected?
5. What is the SpiceDB backing datastore, and is it contributing to latency? (Not investigated — SpiceDB logs show OK responses, suggesting the bottleneck is CPU, not I/O)
6. What changed in calendar v1.194.0-rc.0 that causes `mustFindUserByLegacyId` to fail for some users? Schema migration? Query change? Data dependency on a field not populated for all users?
7. Was the calendar v1.194.0-rc.0 deployment intentional for production, or was an RC version deployed by mistake?

### Investigation Path

**Decision tree:**
```
├─ ocs-proxy AH01102 timeouts to multiple backends (ocs-proxy stderr logs)
│  └─ Why are backends unresponsive?
│     ├─ Path A: diet-suggestions, devices-integration → DEADLINE_EXCEEDED from SpiceDB
│     │  └─ Why is SpiceDB slow?
│     │     ├─ ✗ SpiceDB errors (all grpc.code=OK)
│     │     ├─ ✗ Memory pressure (4.8MB evictable, stable)
│     │     ├─ ✗ Deployment (no SpiceDB rollout in window)
│     │     └─ ✓ CPU saturation: 0.83-0.96 cores vs 1.0 limit
│     │        └─ Amplified by: N+1 pattern + gRPC pinning
│     │           └─ Disconfirming checks: 2/2 pass → ROOT CAUSE 1 CONFIRMED
│     │
│     └─ Path B: backend-core → calendar "EOF reached while reading"
│        └─ Why is calendar failing?
│           ├─ ✗ SpiceDB dependency (zero DEADLINE_EXCEEDED in calendar; calendar CPU 0.06-0.42 cores)
│           ├─ ✗ Resource exhaustion (calendar CPU low, not saturated)
│           └─ ✓ FluxCD deployment v1.193.0 → v1.194.0-rc.0 at 14:12:54
│              Evidence: k8s_cluster events (ScalingReplicaSet), new pod NoResultException
│              └─ mustFindUserByLegacyId fails for some users → HTTP 500
│                 └─ Disconfirming check: errors only in new ReplicaSet (86d467c6f5) → ROOT CAUSE 2 CONFIRMED
│
├─ Recovery: not verified (errors persist through 16:59 UTC)
├─ Blast radius: 5+ backend services via ocs-proxy, all OCS coach-facing pages
└─ Disproved: initial hypothesis that calendar failures were SpiceDB-caused (contradicted by zero DEADLINE_EXCEEDED in calendar)
```

**Evidence steps:**

1. **Proximate cause** — ocs-proxy Apache `AH01102` timeout errors to `diet-suggestions:8080`, `backend-core:8080`, `calendar:8080` starting ~14:42 UTC.

2. **Backend errors** — `diet-suggestions` returns `DEADLINE_EXCEEDED` from SpiceDB `CheckPermission` after 3s. `devices-integration` same pattern. `backend-core` has a different path: fails calling `calendar` service (EOF).

3. **SpiceDB latency** — Server-side gRPC logs show p50=1042ms, 56% of calls >1s in a 1-minute sample at 14:30.

4. **SpiceDB CPU** — Metric query: 0.83-0.96 cores across all 3 pods. Request=0.5, limit=1.0. No spike — chronic.

5. **gRPC pinning** — `10.204.5.20:40834` sends 48% of calls, all to pod `vd4cn`. Single TCP connection, HTTP/2 multiplexing.

6. **SpiceDB disconfirming checks:**
   - "If SpiceDB is the cause, errors should span multiple SpiceDB-consuming services" → **confirmed** (diet-suggestions, devices-integration — both have DEADLINE_EXCEEDED)
   - "If CPU is the bottleneck, latency should correlate with CPU utilization, not time-of-day" → **confirmed** (CPU flat, latency consistently high, errors present from 13:09)

7. **Calendar independence from SpiceDB:**
   - DEADLINE_EXCEEDED search in calendar logs → **zero results**. Calendar does NOT call SpiceDB.
   - Calendar CPU at 0.06-0.42 cores → **not resource-constrained**
   - Calendar errors are `NoResultException` (DB query miss) and `ConstraintViolationException` (duplicate key) → **database-layer, not gRPC**
   - Hypothesis "calendar slow because of SpiceDB" → **disproved**

8. **Calendar deployment regression:**
   - FluxCD events prove deployment at 14:12:54 (v1.193.0 → v1.194.0-rc.0)
   - New pod ReplicaSet `86d467c6f5` matches all calendar error logs
   - `mustFindUserByLegacyId` NoResultException → data consistency bug in new version

**Reviewer takeaway:** Two independent P0 root causes — SpiceDB CPU saturation (increase limits + add HPA) AND calendar v1.194.0-rc.0 regression (investigate `mustFindUserByLegacyId`). Fixing only one leaves half the coach-facing impact unresolved. The initial assumption that calendar was SpiceDB-caused was disproved by examining calendar's own error logs — a reminder to investigate each failure path to its own evidence rather than attributing to the most visible root cause.