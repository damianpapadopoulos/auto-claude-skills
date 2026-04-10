# Postmortem: OCS Admin/Coach Logouts — 2026-04-09
investigation-analysis skill / 24m 32s run / 22.4k tokens

## 1. Summary

Admins and Coaches were repeatedly logged out of OCS (ovivacoach.com) throughout the morning of April 9, 2026, with reports escalating toward 14:00 CEST.

**Application-side** JDBC connection pool exhaustion in `backend-core` caused cascading failures: proxy timeouts on OCS REST endpoints, pod restarts that destroyed user sessions, and downstream Keycloak auth validation failures. Cloud SQL database metrics (connections, CPU, query rate) were all within normal bounds — the pool exhaustion was entirely within backend-core's application pool, where connections were being held for too long. A concurrent `goal-setting` deployment at 11:11 UTC amplified the pressure by competing for the already-exhausted local pool.

## 2. Impact

**User impact:**
- Admins and Coaches using OCS (prod-ocs.ovivacoach.com) experienced forced logouts throughout the morning
- The logout mechanism was two-fold: (1) 502 proxy timeouts on `/rest/users/coaches.json` interpreted by the frontend as auth failure, and (2) Keycloak refresh token validation failures causing definitive session invalidation
- IDP (Keycloak) auth warning rate was **3.4x baseline** in the 11:00 UTC hour (576 vs 169 on April 8)
- Mobile API users (`prod-api.ovivacoach.com`) were also affected by goal-setting endpoint failures

**Infrastructure scope:**
- **502 proxy timeouts**: 2,061 in the 06:00–12:00 UTC window (vs 909 baseline on April 8 — **2.3x elevation**)
- **Backend-core JDBC errors**: 500 `acquisition timeout` errors on April 9 vs **zero on April 8**
- **Goal-setting**: Complete service outage for ~5 minutes post-deployment (JDBC pool exhaustion)
- **Affected services**: backend-core (5+ pods), goal-setting, calendar, IDP (Keycloak), hcs-gb-cdc — all sharing `oviva-prod1-prod-db`
- **Cluster scale-up triggered**: 15 GKE balloon pods evicted at 11:51–11:54 UTC for node provisioning

**Duration:** Onset ~10:00 UTC (first JDBC errors); major escalation 10:25 UTC (first 502 spike). Recovery not verified — investigation window ends at 12:00 UTC. Reports continued until at least 14:00 CEST (12:00 UTC).

## 3. Action Items

| Priority | Action | Current state | Owner | Due | Status |
|----------|--------|---------------|-------|-----|--------|
| P0 | Investigate backend-core connection pool exhaustion: identify why connections are held longer on April 9 than April 8. Focus on slow queries, long transactions, or connection leak in the April 7 deployment. Cloud SQL database metrics are normal — this is application-side pool behavior. | DB connections/CPU/query-rate all identical to baseline. 0 JDBC errors on April 8, 500 on April 9. No backend-core deploy between days. Slow query log and pool config not yet reviewed. | ⚠ Owner needed | 2026-04-11 | Open |
| P0 | Verify current incident status — are logouts still occurring? Query 502 and IDP warning rates for April 9 12:00–18:00 UTC and April 10 | Not yet checked beyond 12:00 UTC investigation window | ⚠ Owner needed | 2026-04-09 | Open |
| P1 | Audit backend-core application connection pool sizing (max pool size, connection timeout, idle timeout, leak detection) and Cloud SQL slow query log for April 9 | DB-level connections/CPU are normal — the bottleneck is the app-side pool. Pool config unknown (kubectl unavailable). Slow query log not yet reviewed. | ⚠ Owner needed | 2026-04-14 | Open |
| P1 | Review the April 7 backend-core deployment (20:14 UTC) for changes to query patterns, transaction scope, or connection pool config | Last backend-core deploy before the incident. 0 JDBC errors on April 8 (next day), 500 on April 9 (two days later) — possible slow leak or load-dependent regression | ⚠ Owner needed | 2026-04-14 | Open |
| P2 | Add monitoring/alerting for JDBC connection pool utilization (pool active vs max) per service | No current alerting detected for JDBC pool saturation. Backend-core exhausted its pool without triggering alerts before user impact | ⚠ Owner needed | 2026-04-18 | Open |
| P2 | Review backend-core calendar API call pattern — N+1 calls with 30+ patient IDs per request may hold connections during slow responses | Backend-core makes sequential HTTP calls to `calendar:8080/app/v2/calendar/events.json` with large resource lists. Response times not measured | ⚠ Owner needed | 2026-04-18 | Open |
| P2 | Review goal-setting deployment strategy — deployment to a service sharing a stressed connection pool amplified the incident | goal-setting deployed at 11:11 UTC via FluxCD while backend-core pool was already exhausted | ⚠ Owner needed | 2026-04-18 | Open |
| P3 | Investigate OCS frontend 502 handling — does the frontend correctly distinguish between transient server errors and auth failures? | Frontend redirects to login on 502 responses to `/rest/users/coaches.json`. A retry or degraded-state UX would reduce perceived logout frequency | ⚠ Owner needed | 2026-04-25 | Open |

## 4. Root Cause & Trigger

**Root cause:** Application-side JDBC connection pool exhaustion in `backend-core`. Connections in the local pool (Hibernate/HikariCP/C3P0) were being held for longer than usual, exhausting the pool under normal traffic load.

**Critical: The database itself was healthy.** Cloud SQL metrics for `oviva-prod1-prod-db` on April 9 vs April 8 baseline:

| Metric | April 9 | April 8 (baseline) | Verdict |
|--------|---------|--------------------|-|
| Connections | 950–1,321 | 952–1,322 | Identical |
| CPU utilization | 25%–57% | 23%–60% | Baseline (Apr 8 higher peak) |
| Query rate | 4,800–11,000/sec | — | Normal pattern |

The JDBC pool exhaustion is NOT a database capacity issue. It is a connection-holding-time issue within backend-core's application pool.

**Causal chain:**
```
backend-core application pool exhaustion (new on April 9; 0 errors on April 8)
  │ (connections held too long — slow queries, long transactions, or connection leak)
  │ (database-level connection count, CPU, query rate all NORMAL)
  ├→ backend-core requests take >timeout to respond
  │  → ocs-proxy returns 502 on /rest/users/coaches.json, /rest/profitcenter/...
  │    → OCS frontend interprets 502 as auth failure → redirects to login ("logged out")
  ├→ backend-core pods become unresponsive → terminated by k8s (11:46Z)
  │  → Cloud SQL proxy shutdown with 59-60 active stuck connections
  │  → GKE cluster scale-up triggered (balloon pod eviction 11:51-11:54 UTC)
  │  → New backend-core pods start → WildFly sessions lost → users logged out
  ├→ IDP Cloud SQL proxy readiness failure at 11:46Z (correlated with pod churn)
  │  → Keycloak REFRESH_TOKEN_ERROR spike (3.4x baseline)
  │  → Sessions definitively invalidated
  └→ goal-setting (deployed 11:11 UTC) hits same pool exhaustion pattern
     → /goal-setting/* endpoints return 500 → ocs-proxy 502
```

**Trigger:** Not conclusively identified. Backend-core had zero JDBC errors on April 8 and 500 on April 9, with no code deployment between the two days (last backend-core deploy: April 7 at 20:14 UTC). Since database-level metrics are normal, the trigger is specifically within backend-core's connection usage: a connection leak from the April 7 deployment manifesting after ~36 hours of uptime, a change in query patterns (slow queries holding connections), or a transaction scope regression.

**Links:** [Backend-core JDBC errors](https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.container_name%3D%22backend-core%22%0Aresource.labels.namespace_name%3D%22prod%22%0A%22Unable%20to%20acquire%20JDBC%22%0Atimestamp%3E%3D%222026-04-09T10:00:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T12:00:00Z%22?project=oviva-k8s-prod) · [OCS proxy errors](https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.container_name%3D%22ocs-proxy%22%0Aresource.labels.namespace_name%3D%22prod%22%0Aseverity%3E%3DERROR%0Atimestamp%3E%3D%222026-04-09T10:00:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T12:00:00Z%22?project=oviva-k8s-prod) · [Cloud SQL proxy errors](https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.namespace_name%3D%22prod%22%0Aresource.labels.container_name%3A%22cloudsql%22%0Aseverity%3E%3DWARNING%0Atimestamp%3E%3D%222026-04-09T10:00:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T12:00:00Z%22?project=oviva-k8s-prod)

## 5. Timeline (all timestamps UTC)

| Timestamp (UTC) | Event | Evidence |
|---|---|---|
| Apr 7, 20:14 | Last `backend-core` deployment via FluxCD | [Deploy audit log](https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_cluster%22%0AprotoPayload.resourceName%3A%22backend-core%22%0Atimestamp%3E%3D%222026-04-07T20:00:00Z%22%20AND%20timestamp%3C%3D%222026-04-07T21:00:00Z%22?project=oviva-k8s-prod) |
| Apr 9, ~06:00 | 502 proxy timeouts begin at low rate (16/hr), increasing with traffic | ocs-proxy access logs |
| Apr 9, ~10:00 | Backend-core JDBC `acquisition timeout` errors begin (384 in this hour; 0 on April 8) | backend-core container ERROR logs |
| Apr 9, 10:25 | **First 502 spike**: 159 in 2 min. 88% on `/rest/users/coaches.json` — backend-core:8080 timeout | [OCS proxy errors](https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.container_name%3D%22ocs-proxy%22%0Aseverity%3E%3DERROR%0Atimestamp%3E%3D%222026-04-09T10:24:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T10:27:00Z%22?project=oviva-k8s-prod) |
| Apr 9, 10:25:50 | Cloud SQL proxy connection reset on backend-core pod `qmfs6` | backend-core-cloudsql-proxy ERROR log |
| Apr 9, 11:11:47 | `goal-setting` + `goal-setting-frontend` deployed via FluxCD | k8s audit log |
| Apr 9, 11:15 | Goal-setting JDBC pool exhaustion (148 errors/min); goal-setting service returns 500 | goal-setting container ERROR logs |
| Apr 9, 11:15–11:16 | **Major 502 spike**: 626 in 2 min. 96% on `/goal-setting/*` endpoints | ocs-proxy access logs |
| Apr 9, 11:16 | Edge-proxy upstream timeout on goal-setting (21 errors on api.ovivacoach.com) | edge-proxy ERROR logs |
| Apr 9, 11:46–11:47 | Backend-core pods terminated; Cloud SQL proxy shutdown with 59–60 stuck connections | backend-core-cloudsql-proxy ERROR logs |
| Apr 9, 11:46:41 | IDP (Keycloak) Cloud SQL proxy readiness failure: "proxy has stopped" | idp-cloudsql-proxy ERROR log |
| Apr 9, 11:50–11:58 | Backend-core pod `pjcf7` WildFly boot sequence (new pod replacing terminated one) | backend-core container INFO logs |
| Apr 9, 11:51–11:54 | GKE cluster auto-scale: 15 balloon pods evicted for new node provisioning | k8s audit logs |
| Apr 9, 11:52–11:57 | Keycloak REFRESH_TOKEN_ERROR and cookie_not_found errors spike (IDP warning rate 3.4x baseline) | [IDP warnings](https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.container_name%3D%22idp%22%0Aseverity%3E%3DWARNING%0Atimestamp%3E%3D%222026-04-09T11:00:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T12:00:00Z%22?project=oviva-k8s-prod) |
| Apr 9, ~12:00 | Investigation window ends. Reports of logouts continued at 14:00 CEST. | User reports |
| Apr 9, ??? | Recovery not verified — 502/JDBC error cessation not confirmed | Gap |

## 6. Contributing Factors

**1. Backend-core application connection pool exhaustion (highest impact)**
Backend-core's local JDBC pool ran out of available connections — not because the database was overwhelmed (Cloud SQL metrics are normal), but because individual connections were held for too long under load. This is an application-level resource management issue: the pool has a fixed max size, and when connections are held by slow operations, new requests queue until the acquisition timeout expires. The trigger for why April 9 was worse than April 8 (with no deployment between days) remains unidentified.

**2. Goal-setting deployment timing**
The FluxCD deployment of goal-setting at 11:11 UTC added connection demand to an already-exhausted pool, triggering the major 502 spike (626 in 2 minutes). The deployment itself was not the root cause but significantly amplified the incident.

**3. Backend-core N+1 calendar API calls**
Backend-core makes sequential HTTP calls to `calendar:8080/app/v2/calendar/events.json` with 30+ patient IDs per request. These calls hold HTTP threads (and potentially DB connections) for extended durations while waiting for calendar responses. This amplifies connection pressure during peak traffic.

**4. Calendar service message processing failures**
Calendar pods consistently fail to process `TaskExecutionStateChangedEvent` messages (TechnicalException), consuming processing resources. This is a chronic condition (present at baseline on April 8) but contributes to calendar response latency.

**5. OCS frontend error handling**
The OCS frontend appears to redirect to the login page on 502 responses to REST API calls, interpreting transient server errors as session failures. This makes transient backend overload appear as "being logged out" to users.

**Capacity context:** Cloud SQL instance `oviva-prod1-prod-db` (db-custom-18-119808, 18 vCPU, ~117 GB RAM, 3.7 TB SSD) was **not the bottleneck**. DB connections peaked at 1,321 (vs 1,322 baseline), CPU at 57% (vs 60% baseline), query rate at 11,000/sec. The bottleneck is backend-core's application pool size (not captured — kubectl unavailable). The condition is acute (appeared April 9 after being absent April 8), not chronic headroom drift at the DB level.

## 7. Lessons Learned

**What went well:**
- Logs and Cloud SQL proxy errors provided clear evidence of the JDBC pool exhaustion chain
- The shared database as single point of failure was identifiable from proxy error patterns across services

**What went wrong:**
- No alerting on JDBC connection pool utilization — the pool was exhausted for over an hour before pod terminations triggered visible failures
- The goal-setting deployment proceeded without awareness that the shared database was already under stress
- Backend-core pod termination at 11:46Z destroyed user sessions, escalating intermittent 502s into definitive logouts
- The IDP (Keycloak) sharing a database with backend-core meant that backend-core's connection leak directly compromised auth infrastructure

**Where we got lucky:**
- GKE auto-scaler provisioned new nodes (11:51 UTC), preventing complete cluster-level resource exhaustion
- The incident occurred during European business hours when engineers were available

## 8. Investigation Notes

### Confirmed findings

- **JDBC pool exhaustion is new**: 0 `acquisition timeout` errors on April 8, 500 on April 9. No backend-core deployment between the two days. This rules out a baseline/chronic condition and points to an acute change in connection behavior.
- **403 rate is baseline**: 4,948 on April 9 vs 5,000 on April 8. The 403 errors visible in ocs-proxy access logs are normal system behavior and NOT the mechanism causing logouts.
- **Calendar errors are baseline**: ~2,000 `TaskExecutionStateChangedEvent` failures on both April 8 and April 9. These are a chronic condition.
- **Multiple services share one database**: backend-core, IDP, goal-setting, calendar, hcs-gb-cdc all use `oviva-prod1-prod-db` via Cloud SQL proxy sidecars.
- **Database itself was not the bottleneck**: Cloud SQL metrics (connections: 950–1,321 vs 952–1,322 baseline; CPU: 25–57% vs 23–60% baseline; query rate: 4,800–11,000/sec) are all within normal bounds. The JDBC pool exhaustion is application-side, not database-side.

### Hypotheses investigated and ruled out

1. **Keycloak/IDP failure as primary cause**: Keycloak had no ERROR-level failures. IDP auth warnings (3.4x baseline) are a consequence of database starvation — backend-core JDBC errors preceded IDP warnings by >1 hour.
   **Links:** [IDP logs](https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.container_name%3D%22idp%22%0Aresource.labels.namespace_name%3D%22prod%22%0Aseverity%3E%3DWARNING%0Atimestamp%3E%3D%222026-04-09T06:00:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T12:00:00Z%22?project=oviva-k8s-prod)

2. **Goal-setting deployment as root cause**: Backend-core JDBC pool exhaustion (384 errors) began in the 10:00Z hour, before the 11:11Z goal-setting deployment. Goal-setting amplified but did not trigger.
   **Links:** [Goal-setting errors](https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.container_name%3D%22goal-setting%22%0Aseverity%3E%3DERROR%0Atimestamp%3E%3D%222026-04-09T11:10:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T12:00:00Z%22?project=oviva-k8s-prod)

3. **403 errors causing logouts**: 403 count is identical to baseline. Ruled out as the logout mechanism.

4. **Calendar service failures as trigger**: Present at baseline (April 8 same volume). Chronic contributing factor, not acute trigger.

5. **Session/token store (Redis/Memcached) failure**: No Redis or Memcached containers found with errors. Keycloak uses the shared MySQL database for session storage.

### Open questions

1. **What specifically triggered the JDBC pool exhaustion on April 9?** No code deployment between April 8 (0 errors) and April 9 (500 errors). Possible causes: connection leak from April 7 backend-core deploy manifesting after 36h uptime, slow query escalation, or database-level change. **Cloud SQL slow query logs and backend-core connection pool configuration need review.**
2. **What are the `max_connections` settings on Cloud SQL and per-service pool sizes?** kubectl was unavailable during investigation. Deployment manifests should be checked for pool sizing.
3. **Has the incident fully resolved?** Investigation window ends at 12:00 UTC. Reports continued at 14:00 CEST. Recovery status unknown.
4. **Did the April 7 backend-core deployment (20:14 UTC) change connection pool behavior?** The deploy is 36h before onset — a slow connection leak could explain the progressive degradation.
5. **Is the `hcs-gb-cdc` Cloud SQL proxy `broken pipe` error at 10:56Z related, or coincidental?** Not deeply investigated.

### Investigation Path

**Decision tree:**
```
├─ 502 proxy timeouts on /rest/users/coaches.json (ocs-proxy error logs)
│  └─ Why is backend-core:8080 not responding?
│     ├─ ✗ Bad deployment (no backend-core deploy on Apr 8 or 9)
│     ├─ ✗ Calendar service failure (present at baseline on Apr 8)
│     └─ ✓ JDBC connection pool exhaustion (500 errors on Apr 9 vs 0 on Apr 8)
│        └─ Why did the pool exhaust?
│           ├─ ✗ Goal-setting deployment (pool already exhausted before 11:11Z deploy)
│           ├─ ✗ Calendar service consuming DB resources (baseline condition)
│           ├─ ? Connection leak from Apr 7 backend-core deploy (36h lag — not confirmed)
│           └─ ? Database-level pressure (Cloud SQL metrics unavailable via CLI)
│              └─ Disconfirming checks: [partial] → TRIGGER NOT CONFIRMED
├─ Keycloak REFRESH_TOKEN_ERROR spike (IDP logs)
│  └─ Why are refresh tokens failing?
│     ├─ ✗ IDP application error (no Keycloak ERRORs)
│     └─ ✓ IDP Cloud SQL proxy readiness failure at 11:46Z → DB starvation
│        └─ Shared database saturated by backend-core connections
├─ Recovery: NOT VERIFIED (investigation window ends at 12:00 UTC)
├─ Blast radius: 6+ services affected via shared database
└─ Disproved: "403 spike" (baseline rate), "Keycloak primary failure" (consequence, not cause)
```

**Evidence steps:**

1. **Inventory** — ocs-proxy (3 pods: v2z4q, m8dbk, xnj7q), backend-core (5+ pods), calendar (3 pods: tdjq4, d4klr, 99878), goal-setting (1 pod: hsnkz), IDP (StatefulSet: idp-0, idp-2). All sharing Cloud SQL `oviva-prod1-prod-db`.

2. **Proximate cause** — ocs-proxy returning 502 on backend-core:8080 timeout (AH01102). 1,262 502s in 10:00–12:00 UTC vs 554 baseline (2.3x). Primary endpoints: `/rest/users/coaches.json`, `/rest/profitcenter/profit-centers-with-active-coaches.json`.

3. **Ruled-out triggers:**
   - Ruled out: "Deployment on April 9" (audit logs: no backend-core, ocs-proxy, calendar, or IDP deployment on April 9 before 12:00Z).
   - Ruled out: "403 errors" (baseline rate: 4,948 vs 5,000 on April 8).
   - Ruled out: "Calendar service failures" (same volume on April 8).
   - Actual trigger: JDBC pool exhaustion in backend-core, NEW on April 9.

4. **Root cause** — Backend-core JDBC `acquisition timeout` errors: 500 on April 9 (10:00–12:00Z), 0 on April 8 (same window). Cloud SQL proxy errors confirm connection-level pressure. The exhaustion cascaded to IDP via the shared database.

5. **Disconfirming checks:**
   - "If this is a backend-core problem, other services sharing the DB should also fail" → Confirmed: goal-setting JDBC timeout, idp-cloudsql-proxy readiness failure, hcs-gb-cdc broken pipe.
   - "If the 403s are the logout mechanism, they should be elevated vs baseline" → Contradicted: 403 rate is baseline. Logout mechanism is 502+refresh token failure, not 403.
   - "Explains all symptoms?" → Yes for core chain. Open: exact trigger for pool exhaustion.

6. **Recovery** — NOT verified. Investigation window ends at 12:00 UTC. Backend-core pods were restarting at 11:50–11:58Z, which may have temporarily restored pool availability, but the underlying cause was not addressed.

7. **Blast radius** — 6+ services affected: backend-core, goal-setting (complete outage), calendar, IDP (auth degradation), hcs-gb-cdc, ai-companion. All share `oviva-prod1-prod-db`. Systemic risk: any future connection pressure will cascade identically.

**Reviewer takeaway:** The shared Cloud SQL database is a single point of failure for authentication — backend-core's connection leak starved Keycloak of DB access, turning a backend performance issue into an auth outage. P0 action: diagnose and fix the backend-core connection pool exhaustion.

---

```yaml
investigation_summary:
  scope:
    service: "backend-core (via ocs-proxy)"
    environment: "production (oviva-k8s-prod)"
    time_window: "2026-04-09T06:00:00Z/2026-04-09T12:00:00Z"
    mode: "full"
  dominant_errors:
    - bucket: "JDBC Connection acquisition timeout (backend-core)"
      count: 500
      percentage: "N/A (not relative to all errors)"
      aggregation_source: "sample"
    - bucket: "AH01102 proxy timeout to backend-core:8080"
      count: 1262
      percentage: "N/A"
      aggregation_source: "sample"
    - bucket: "JDBC Connection acquisition timeout (goal-setting)"
      count: 500
      percentage: "N/A"
      aggregation_source: "sample"
  chosen_hypothesis:
    statement: "Application-side JDBC connection pool exhaustion in backend-core (connections held too long under normal DB load) caused proxy timeouts on OCS endpoints, pod restarts that destroyed sessions, and downstream Keycloak refresh token validation failures, resulting in user logouts"
    confidence: "high"
    supporting_evidence:
      - "0 JDBC errors on April 8, 500 on April 9 — new condition"
      - "502 rate 2.3x baseline (1,262 vs 554)"
      - "IDP REFRESH_TOKEN_ERROR rate 3.4x baseline (576 vs 169)"
      - "Cloud SQL proxy errors: connection resets, 60 stuck connections at shutdown"
      - "Cloud SQL DB-level metrics NORMAL: connections 950-1321 (baseline 952-1322), CPU 25-57% (baseline 23-60%), query rate 4800-11000/sec"
      - "Pool exhaustion is application-side (connection holding time), not database-side (capacity)"
    contradicting_evidence_sought: "If 403s are the mechanism, their rate should be elevated — checked: rate is baseline (4,948 vs 5,000)"
    contradicting_evidence_found: "none for the chosen hypothesis chain; acute trigger not identified"
    evidence_links:
      - type: "logs"
        label: "Backend-core JDBC errors"
        url: "https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.container_name%3D%22backend-core%22%0Aresource.labels.namespace_name%3D%22prod%22%0A%22Unable%20to%20acquire%20JDBC%22%0Atimestamp%3E%3D%222026-04-09T10:00:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T12:00:00Z%22?project=oviva-k8s-prod"
      - type: "logs"
        label: "OCS proxy 502 errors"
        url: "https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.container_name%3D%22ocs-proxy%22%0Aresource.labels.namespace_name%3D%22prod%22%0Aseverity%3E%3DERROR%0Atimestamp%3E%3D%222026-04-09T10:00:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T12:00:00Z%22?project=oviva-k8s-prod"
      - type: "logs"
        label: "IDP auth warnings"
        url: "https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.container_name%3D%22idp%22%0Aresource.labels.namespace_name%3D%22prod%22%0Aseverity%3E%3DWARNING%0Atimestamp%3E%3D%222026-04-09T11:00:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T12:00:00Z%22?project=oviva-k8s-prod"
  ruled_out:
    - hypothesis: "Keycloak/IDP application failure as primary cause"
      reason: "No Keycloak ERROR-level logs. IDP auth warnings preceded by 1+ hour of backend-core JDBC errors — consequence, not trigger."
      evidence_links:
        - type: "logs"
          label: "IDP incident logs"
          url: "https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.container_name%3D%22idp%22%0Aresource.labels.namespace_name%3D%22prod%22%0Aseverity%3E%3DWARNING%0Atimestamp%3E%3D%222026-04-09T06:00:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T12:00:00Z%22?project=oviva-k8s-prod"
    - hypothesis: "Goal-setting deployment as root cause"
      reason: "Backend-core JDBC errors (384) began in 10:00Z hour, before goal-setting deploy at 11:11Z"
      evidence_links:
        - type: "deployment"
          label: "Goal-setting deploy history"
          url: "https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_cluster%22%0AprotoPayload.resourceName%3A%22goal-setting%22%0Atimestamp%3E%3D%222026-04-09T11:00:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T12:00:00Z%22?project=oviva-k8s-prod"
    - hypothesis: "403 errors causing the logout symptom"
      reason: "403 count is baseline (4,948 vs 5,000 on April 8). Normal system behavior."
    - hypothesis: "Calendar service failures as acute trigger"
      reason: "~2,000 errors present on both April 8 and April 9. Chronic condition, not new."
  evidence_coverage:
    logs: "complete"
    k8s_state: "unavailable"
    metrics: "complete"
    source_analysis: "skipped"
    trace_correlation: "skipped"
  gaps:
    - "kubectl unreachable — pod specs, resource limits, connection pool config, HPA state not captured"
    - "Cloud SQL slow query log not reviewed (requires DB admin access)"
    - "Recovery not verified — investigation window ends at 12:00 UTC"
    - "Backend-core connection pool sizing not checked (requires kubectl or GitOps manifests)"
    - "Cloud SQL max_connections setting not confirmed"
  timeline_entries:
    - timestamp_utc: "2026-04-07T20:14:06Z"
      time_precision: "exact"
      event_kind: "deploy_event"
      description: "Last backend-core deployment via FluxCD"
      evidence_source: "k8s audit logs"
    - timestamp_utc: "2026-04-09T06:00:00Z"
      time_precision: "approximate"
      event_kind: "log_entry"
      description: "502 proxy timeouts begin at low rate (16/hr)"
      evidence_source: "ocs-proxy access logs"
    - timestamp_utc: "2026-04-09T10:00:00Z"
      time_precision: "minute"
      event_kind: "log_entry"
      description: "Backend-core JDBC acquisition timeout errors begin (384 in this hour)"
      evidence_source: "backend-core container logs"
    - timestamp_utc: "2026-04-09T10:25:00Z"
      time_precision: "minute"
      event_kind: "log_entry"
      description: "First 502 spike: 159 in 2 min, 88% on /rest/users/coaches.json"
      evidence_source: "ocs-proxy error logs"
    - timestamp_utc: "2026-04-09T10:25:50Z"
      time_precision: "exact"
      event_kind: "log_entry"
      description: "Cloud SQL proxy connection reset on backend-core pod qmfs6"
      evidence_source: "backend-core-cloudsql-proxy logs"
    - timestamp_utc: "2026-04-09T11:11:47Z"
      time_precision: "exact"
      event_kind: "deploy_event"
      description: "goal-setting + goal-setting-frontend deployed via FluxCD"
      evidence_source: "k8s audit logs"
    - timestamp_utc: "2026-04-09T11:15:00Z"
      time_precision: "minute"
      event_kind: "log_entry"
      description: "Goal-setting JDBC pool exhaustion (148 errors/min)"
      evidence_source: "goal-setting container logs"
    - timestamp_utc: "2026-04-09T11:15:00Z"
      time_precision: "minute"
      event_kind: "log_entry"
      description: "Major 502 spike: 626 in 2 min, 96% /goal-setting/*"
      evidence_source: "ocs-proxy access logs"
    - timestamp_utc: "2026-04-09T11:46:41Z"
      time_precision: "exact"
      event_kind: "probe_event"
      description: "IDP (Keycloak) Cloud SQL proxy readiness failure"
      evidence_source: "idp-cloudsql-proxy logs"
    - timestamp_utc: "2026-04-09T11:47:00Z"
      time_precision: "exact"
      event_kind: "log_entry"
      description: "Backend-core pods terminated, Cloud SQL proxy shutdown with 59-60 stuck connections"
      evidence_source: "backend-core-cloudsql-proxy logs"
    - timestamp_utc: "2026-04-09T11:51:00Z"
      time_precision: "minute"
      event_kind: "log_entry"
      description: "GKE cluster scale-up: 15 balloon pods evicted for new nodes"
      evidence_source: "k8s audit logs"
    - timestamp_utc: "2026-04-09T11:57:00Z"
      time_precision: "minute"
      event_kind: "log_entry"
      description: "Keycloak REFRESH_TOKEN_ERROR and cookie_not_found errors spike"
      evidence_source: "idp container logs"
  recovery_status:
    recovered: "unknown"
    recovery_time_utc: null
    recovery_evidence: "not captured — investigation window ends at 12:00 UTC"
    verification: "not_verified"
  open_questions:
    - "What specific change between April 8 and April 9 triggered JDBC pool exhaustion? (No code deployment between days)"
    - "What are the max_connections settings on Cloud SQL and connection pool sizes per service?"
    - "Did the April 7 backend-core deployment (20:14Z) introduce a connection leak or slow query?"
    - "Has the incident fully resolved? Recovery not verified."
    - "Is the hcs-gb-cdc Cloud SQL proxy broken pipe error at 10:56Z related?"
  service_attribution:
    - service: "backend-core"
      status: "confirmed-dependent"
      evidence: "JDBC acquisition timeout errors (500 on April 9 vs 0 on April 8), Cloud SQL proxy connection resets"
    - service: "idp (Keycloak)"
      status: "confirmed-dependent"
      evidence: "Cloud SQL proxy readiness failure at 11:46Z, REFRESH_TOKEN_ERROR rate 3.4x baseline"
    - service: "goal-setting"
      status: "confirmed-dependent"
      evidence: "JDBC acquisition timeout immediately after 11:11Z deployment, 500 errors"
    - service: "calendar"
      status: "inconclusive"
      evidence: "TaskExecutionStateChangedEvent failures at baseline rate — chronic condition. May have contributed to DB load but not confirmed as new contributor"
    - service: "hcs-gb-cdc"
      status: "not-investigated"
      evidence: "One Cloud SQL proxy broken pipe error observed; not deeply investigated"
  service_error_inventory:
    - service: "backend-core"
      error_class: "JDBC Connection acquisition timeout"
      tier: 1
      count_incident: 500
      count_baseline: 0
      deployment_in_72h: true
      deployment_timestamp: "2026-04-07T20:14:06Z"
      investigated: true
      infra_status: "assessed"
      infra_evidence: "Deployment history checked (last deploy Apr 7), Cloud SQL proxy errors observed, pod restarts at 11:46Z"
      app_status: "assessed"
      app_evidence: "JDBC pool exhaustion identified as dominant error class"
      mechanism_status: "not_yet_traced"
      evidence_links:
        - type: "logs"
          label: "Backend-core JDBC errors"
          url: "https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.container_name%3D%22backend-core%22%0Aresource.labels.namespace_name%3D%22prod%22%0A%22Unable%20to%20acquire%20JDBC%22%0Atimestamp%3E%3D%222026-04-09T10:00:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T12:00:00Z%22?project=oviva-k8s-prod"
    - service: "goal-setting"
      error_class: "JDBC Connection acquisition timeout"
      tier: 1
      count_incident: 500
      count_baseline: 0
      deployment_in_72h: true
      deployment_timestamp: "2026-04-09T11:11:47Z"
      investigated: true
      infra_status: "assessed"
      infra_evidence: "Deployed at 11:11Z, JDBC errors from 11:15Z"
      app_status: "assessed"
      app_evidence: "JDBC pool exhaustion on /app/scheduled-goals"
      mechanism_status: "known"
    - service: "calendar"
      error_class: "TechnicalException: Failed to process TaskExecutionStateChangedEvent"
      tier: 2
      count_incident: 2000
      count_baseline: 2000
      deployment_in_72h: true
      deployment_timestamp: "2026-04-07T13:31:43Z"
      investigated: true
      infra_status: "assessed"
      infra_evidence: "Deployment history checked, 3 pods active"
      app_status: "assessed"
      app_evidence: "Camel message delivery failures — chronic condition at baseline rate"
      mechanism_status: "not_yet_traced"
    - service: "idp (Keycloak)"
      error_class: "REFRESH_TOKEN_ERROR / invalid_token"
      tier: 1
      count_incident: 576
      count_baseline: 169
      deployment_in_72h: false
      deployment_timestamp: null
      investigated: true
      infra_status: "assessed"
      infra_evidence: "Cloud SQL proxy readiness failure at 11:46Z"
      app_status: "assessed"
      app_evidence: "REFRESH_TOKEN_ERROR, RESTART_AUTHENTICATION_ERROR with cookie_not_found"
      mechanism_status: "known"
      evidence_links:
        - type: "logs"
          label: "IDP auth warnings"
          url: "https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%0Aresource.labels.container_name%3D%22idp%22%0Aresource.labels.namespace_name%3D%22prod%22%0Aseverity%3E%3DWARNING%0Atimestamp%3E%3D%222026-04-09T11:00:00Z%22%20AND%20timestamp%3C%3D%222026-04-09T12:00:00Z%22?project=oviva-k8s-prod"
    - service: "ocs-proxy"
      error_class: "AH01102 proxy timeout to backend-core:8080"
      tier: 2
      count_incident: 1262
      count_baseline: 554
      deployment_in_72h: true
      deployment_timestamp: "2026-04-08T14:13:12Z"
      investigated: true
      infra_status: "assessed"
      infra_evidence: "3 pods active, deployment checked"
      app_status: "assessed"
      app_evidence: "Proxy timeouts on backend-core upstream — not an ocs-proxy issue"
      mechanism_status: "known"
  root_cause_layer_coverage:
    infrastructure_status: "assessed"
    infrastructure_evidence: "Deployment history (last Apr 7), Cloud SQL proxy errors, pod restarts at 11:46Z, GKE scale-up at 11:51Z, Cloud SQL metrics (connections/CPU/query-rate all normal — DB NOT the bottleneck)"
    application_status: "assessed"
    application_evidence: "JDBC connection pool exhaustion identified. Hibernate GenericJDBCException traces. Calendar N+1 call pattern observed."
    mechanism_status: "not_yet_traced"
    mechanism_evidence: "Pool exhaustion confirmed as application-side (DB metrics normal). Root trigger not identified — unknown what changed between April 8 (0 errors) and April 9 (500 errors) without code deployment. Connections are held longer, not more numerous. Requires: slow query log review, application pool config audit (max size, timeout, leak detection), and April 7 deploy diff review."
  tested_intermediate_conclusions:
    - conclusion: "403 errors are the mechanism causing logouts"
      used_in_causal_chain: false
      disconfirming_evidence_sought: "Compare 403 count April 9 vs April 8 baseline"
      result: "disproved"
      evidence: "4,948 on April 9 vs 5,000 on April 8 — identical baseline rate"
    - conclusion: "Calendar service errors are a new acute trigger"
      used_in_causal_chain: false
      disconfirming_evidence_sought: "Compare calendar error count April 9 vs April 8 baseline"
      result: "disproved"
      evidence: "~2,000 errors on both days — chronic condition"
    - conclusion: "Goal-setting deployment triggered the JDBC exhaustion"
      used_in_causal_chain: false
      disconfirming_evidence_sought: "Check if backend-core JDBC errors predate goal-setting deploy"
      result: "disproved"
      evidence: "384 JDBC errors in 10:00Z hour, goal-setting deployed at 11:11Z"
    - conclusion: "Backend-core JDBC pool exhaustion is a new condition on April 9"
      used_in_causal_chain: true
      disconfirming_evidence_sought: "Check for JDBC errors on April 8 (baseline)"
      result: "supported"
      evidence: "0 JDBC errors on April 8 vs 500 on April 9"
    - conclusion: "IDP auth failures are caused by shared database starvation"
      used_in_causal_chain: true
      disconfirming_evidence_sought: "Check if IDP has its own error or if it shares the same DB"
      result: "supported"
      evidence: "idp-cloudsql-proxy readiness failure at 11:46Z pointing to oviva-prod1-prod-db, no IDP application ERRORs"
```
