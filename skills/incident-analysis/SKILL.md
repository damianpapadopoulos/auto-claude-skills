---
name: incident-analysis
description: Use when investigating production symptoms — connection failures, pod crashes/restarts, SIGTERM/OOM errors, latency spikes, Cloud SQL/proxy issues, deployment-correlated errors, ImagePullBackOff, CreateContainerConfigError, or node NotReady events
---

# Incident Analysis

Tiered GCP log investigation with playbook-driven mitigation and structured validation. Stages: MITIGATE, CLASSIFY, INVESTIGATE, EXECUTE, VALIDATE, POSTMORTEM. Detects available tools at runtime and uses the best tier. Playbook YAML files define mitigation commands, safety invariants, and validation criteria.

## Quick Reference — Symptom to Playbook

| Symptom | Likely Playbook | Category |
|---------|----------------|----------|
| Error spike after deploy | bad-release-rollback | bad-release |
| CrashLoopBackOff / pod restarts | workload-restart | workload-failure |
| Multi-pod probe timeout on one node | node-resource-exhaustion | infra-failure |
| Node NotReady / kubelet down | infra-failure | infra-failure |
| CPU/memory saturation + traffic spike | traffic-scale-out | resource-overload |
| Config change correlated with errors | config-regression | bad-config |
| Upstream dependency errors | dependency-failure | dependency-failure |

**When NOT to use this skill:**
- Capacity planning or resource right-sizing without an active incident — use proactive monitoring tools instead
- Alert tuning or alert hygiene — use the `alert-hygiene` skill
- Non-production debugging (local dev, CI failures) — use `systematic-debugging`
- Performance optimization without user-facing symptoms — not an incident

## Behavioral Constraints (Always Active)

### 1. HITL Gate — No Autonomous Mutations

If a mutating action is identified (restart service, rollback deployment, scale pods, modify config), you MUST present the exact command you intend to run and HALT completely. Wait for explicit user confirmation before executing. You are a copilot, not an autopilot.

### 2. Scope Restriction — No Global Searches During Incidents

During active investigation, all application-level file reads, log queries, and code searches MUST be constrained to the specific service or trace ID identified in Stage 1 (MITIGATE). Global codebase searches (unbounded grep, recursive find) are forbidden. This prevents context window exhaustion and irrelevant noise during time-sensitive debugging.

**Infrastructure escalation exception:** When Step 3 (Single-Service Deep Dive) identifies multi-pod or multi-service failures that indicate a node-level or infrastructure-level root cause, the scope expands to the affected node(s) and their infrastructure signals (kubelet logs, serial console, audit logs, node-level metrics). This escalation is bounded — queries target the specific node(s) implicated by the application-level evidence, not the entire cluster. The completeness gate (Step 8, Q6) may require checking peer nodes for systemic risk; this is also permitted under this exception.

**Shared resource and error taxonomy exception:** When Step 2 identifies Tier 1 (anomalous) errors in services adjacent to the symptomatic one, or when Step 3 identifies a shared resource under pressure with evidence of multi-consumer impact, the scope expands to the shared resource's known consumer set (deployment history, connection metrics, error logs). This escalation is bounded to declared consumers of the identified resource, not the entire organization or cluster.

### 3. Temp-File Execution Pattern (Tier 2 Only)

For any LQL query longer than 5 words or containing quotes/regex, write the query to a session-scoped temp file via `mktemp` and execute via file read. This avoids escaping failures and concurrent-session race conditions:

```bash
LQL_FILE=$(mktemp /tmp/agent-lql-XXXXXX.txt)
cat > "$LQL_FILE" << 'QUERY'
resource.type="cloud_run_revision"
AND resource.labels.service_name="checkout-service"
AND severity>=ERROR
AND timestamp>="2026-03-19T10:00:00Z"
QUERY

gcloud logging read "$(cat "$LQL_FILE")" \
  --project=my-project --format=json --limit=50 ; rm -f "$LQL_FILE"
```

The `;` operator ensures cleanup runs regardless of whether `gcloud` succeeds or fails. `mktemp` with a random suffix prevents concurrent sessions from overwriting each other's queries.

### 4. Context Discipline on Stage Transitions

Claude cannot literally clear its context window mid-session. This constraint is enforced **behaviorally** through prompt instructions:

When transitioning from INVESTIGATE to POSTMORTEM:
1. Write a synthesized summary of the timeline and root cause as an explicit output block
2. From that point forward, you are **strictly forbidden from referencing the raw JSON log outputs** from earlier in the conversation
3. Draft the postmortem **ONLY from the synthesized summary**
4. No further log queries or source code reads are permitted during POSTMORTEM

### 5. Evidence Freshness Gate

If the user has not approved a mitigation proposal within the playbook's `freshness_window_seconds` of evidence collection, the proposal is retracted. Return to CLASSIFY with fresh queries. Stale evidence cannot be acted upon.

## Stage 1 — MITIGATE

### Step 1: Detect Available Tools

Run the shared observability preflight to check environment readiness:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/obs-preflight.sh"
```

Parse the JSON output to select the execution tier:

**Tier 1 — MCP (`@google-cloud/observability-mcp`):**
If you have access to `list_log_entries`, `search_traces`, `get_trace`, `list_time_series`, or `list_alert_policies` as MCP tools in this session, use Tier 1.

**Tier 2 — gcloud CLI via Bash:**
```bash
command -v gcloud && gcloud logging read --help >/dev/null 2>&1 && echo "gcloud: available" || echo "gcloud: not available"
```
If gcloud is available but not authenticated, guide through `gcloud auth login` and `gcloud auth application-default login`.

**Tier 3 — Guidance-only:**
If neither MCP tools nor gcloud are available, provide manual Cloud Console instructions (Logs Explorer URL patterns, filter syntax).

**Tier upgrade nudge:** If using Tier 2 (gcloud CLI) and Tier 1 MCP tools are not available, include a one-line note after reporting the tier:

> "Using gcloud CLI (Tier 2). For faster queries with autonomous trace correlation, run `/setup` to configure GCP Observability MCP (Tier 1)."

Do not repeat this nudge after the first mention.

### Step 2: Establish Scope

Identify:
- Which service?
- Which environment (production, staging)?
- What time window? (default: last 30-60 minutes). If the user provides a local time (e.g., "it broke at 2pm"), convert to UTC using the session's timezone (`date +%z`) before querying. If the session timezone cannot be determined, ask the user. All subsequent timestamps in the investigation and postmortem MUST be in UTC.

### Step 2b: Establish Inventory

Before querying logs, determine what you are investigating:
- How many replicas/instances exist? (query metrics or deployment spec — do not infer from logs)
- Where are they distributed? (nodes, zones, regions)
- What are the resource requests, limits, and probe configurations?
- For k8s workloads: scheduling constraints — pod affinity/anti-affinity rules, topologySpreadConstraints, node affinity, taints and tolerations. Query from the same deployment spec used for resource requests. If kubectl is unavailable, check GitOps manifests via `gh api` or `git show` as fallback.

This prevents scoping errors (investigating 4 pods when 7 exist) and reveals distribution risks (3 of 7 pods on one node) before they become surprises in the postmortem. For k8s, use `container/memory/request_bytes` grouped by pod name. For other platforms, use the equivalent inventory query.

Note: topologySpreadConstraints and podAntiAffinity both control pod distribution — if either is present, the workload has scheduling constraints. Distinguish enforcement level: soft (ScheduleAnyway, preferredDuringScheduling) vs hard (DoNotSchedule, requiredDuringScheduling).

When live cluster access is unavailable for inventory or action item verification, fall back to GitOps manifests (`gh api repos/ORG/REPO/contents/PATH` or `git show`) to check deployment configuration. If neither is available, flag affected inventory fields and action items as unverified.

### Step 2c: Quantify User-Facing Impact

Before diving into root cause, establish the impact magnitude from available sources:
- **From metrics (query):** HTTP 5xx error count/rate at the load balancer or ingress, SLI degradation (latency, availability), affected endpoint paths.
- **From alerts (check):** If an SLO burn rate alert fired for this service in the time
  window, note the alert name, burn rate value, and error budget remaining. This provides
  severity context before the deep dive. Check via `list_alert_policies` (Tier 1) or
  `gcloud alpha monitoring policies list` (Tier 2).
- **From user-provided context (do not query):** support tickets, user reports, business impact descriptions. Incorporate if provided but do not attempt to query external support/ticket systems.
- **If neither is available:** state "user-facing impact not quantified" and proceed. Do not estimate.

This frames severity before the deep dive — a 1,100-error incident gets different treatment than a 5-error incident.

### Step 3: Query Error Rate / Recent Errors

Scoped to the identified service + narrow time window.

**Tier 1:** Use `list_log_entries` with LQL filter scoped to service + severity + time window, `page_size` <= 50.

**Tier 2:** Use the temp-file execution pattern (see Constraint 3) with `gcloud logging read` and `--limit=50`.

### Step 4: Identify Failing Request Pattern

Extract: endpoint, error code, frequency.

### Step 5: Mitigation Routing

If mitigation is needed, transition to CLASSIFY for structured playbook selection. All mutating actions must go through the playbook framework — the agent cannot propose bare commands outside the safety contract. If no playbook matches, transition to INVESTIGATE or provide manual guidance.

### Step 6: Transition

If a code fix is needed (no mitigation required), transition to INVESTIGATE.

## CLASSIFY

Structured playbook selection. Entered from MITIGATE Step 5 when mitigation is needed. Evaluates signals against candidate playbooks, scores them, and routes to the appropriate confidence tier.

### Playbook Discovery

Load candidate playbooks from two sources:

1. **Bundled playbooks:** `skills/incident-analysis/playbooks/*.yaml` (shipped with the plugin)
2. **Repo-local overrides:** `playbooks/incident-analysis/*.yaml` (project-specific)

Resolution is by `id` — a repo-local playbook with the same `id` as a bundled playbook replaces the bundled version entirely. Repo-local playbooks with unique IDs are added to the candidate set.

### Signal Evaluation

For each signal referenced by candidate playbooks, evaluate against current evidence to produce a tri-state result:

| State | Meaning |
|-------|---------|
| `detected` | Signal is present in the collected evidence |
| `not_detected` | Signal was explicitly looked for and is absent |
| `unknown_unavailable` | Cannot evaluate (tool unavailable, data not collected, ambiguous) |

**Compound signal propagation:**
- `any_of`: detected if ANY child is detected; not_detected if ALL children are not_detected; unknown_unavailable otherwise
- `all_of`: detected if ALL children are detected; not_detected if ANY child is not_detected; unknown_unavailable otherwise

Signal definitions are loaded from `skills/incident-analysis/signals.yaml`.

### Scoring, Routing, and Decision Records

Scoring formula, confidence-gated routing (high/medium/low), loop termination, disambiguation anti-looping, and decision record templates are in `references/classify-scoring.md`.

**Quick summary:** Each playbook scores `confidence = clamp(0,100, round(base_score - contradiction_score) / evaluable_weight × 100)`. Veto signals disqualify immediately. Coverage gate requires evaluable_weight/max_possible ≥ 0.70. High confidence (≥85 with ≥15pt margin) → HITL gate. Medium (60-84) → disambiguation probes then re-rank. Low (<60) → INVESTIGATE Steps 1-5 then re-classify.

## Stage 2 — INVESTIGATE

**Re-entry from CLASSIFY (< 60 path):** When entered from the CLASSIFY low-confidence path, only Steps 1-5 run. Steps 6-9 (Flight Plan, Timeline Extraction, context synthesis, completeness gate, POSTMORTEM transition) are SKIPPED. Findings feed back to CLASSIFY for reclassification.

### Step 1: Query Logs with Narrowed Filter

Use LQL scoped to service + severity + time window identified in Stage 1.

### Step 2: Extract Key Signals

Stack traces, error messages, request IDs, trace IDs.

**Error taxonomy — prioritize by diagnostic value:**
Not all errors are equally informative. Classify extracted signals into three tiers:

| Tier | Type | Diagnostic value | Examples |
|------|------|-----------------|----------|
| 1 | **Anomalous** — unexpected exception types, application errors in unexpected services | Highest — often points to the **trigger** (why) | Template/parsing exceptions in message consumers, schema errors during read paths, application exceptions in services adjacent to the symptomatic one |
| 2 | **Infrastructure** — standard platform/network/resource errors | Medium — tells you **where** the system is breaking | `TimeoutException`, `ConnectionRefused`, `DeadlineExceeded`, `OOMKilled`, deadlocks |
| 3 | **Expected application** — known error types at baseline rates | Low — tells you **what** is normal | Authentication failures at typical rates, validation errors, 4xx responses |

**Investigate Tier 1 errors first**, even if they appear in services outside your current scope. A single anomalous error in an adjacent service is often more diagnostic than dozens of infrastructure errors in the symptomatic service. When Tier 1 errors are found in adjacent services, they are candidates for scope expansion — note them for Step 3.

**Container exit code guide** (when container termination status is available from pod describe or events):

| Exit Code | Signal | Meaning | Investigation Route |
|-----------|--------|---------|-------------------|
| 0 | Normal exit | Container completed successfully | Check if this is a long-running service that should not exit — possible entrypoint/command misconfiguration |
| 1 | Application error | Uncaught exception or assertion failure | Check previous container logs for stack trace → route to bad-release or config-regression |
| 137 | SIGKILL (OOMKilled) | Kernel OOM killer terminated the process | Check memory limits vs actual usage → route to resource-overload or node-resource-exhaustion. A restart will not help if limits are too low. |
| 139 | SIGSEGV | Segmentation fault in native code | Check recent deployment for native dependency changes → route to bad-release |
| 143 | SIGTERM | Graceful termination timeout exceeded | Check `terminationGracePeriodSeconds`, shutdown hooks, long-running connections. Not necessarily a failure — may indicate slow shutdown. |

Use exit codes to route investigation before proposing mitigation. Exit code 137 (OOMKilled) means restart is pointless — the pod will OOM again. Exit code 1 after a deploy points to bad-release, not workload-restart.

### Targeted Disambiguation Probes (Conditional — CLASSIFY Handoff)

When entered from the CLASSIFY low-confidence path with a SHORTLIST handoff artifact,
execute the disambiguation probes listed for each runner-up. Probes are read-only,
aggregate-first queries (max_results <= 10) that target signals specific to the runner-up
playbook. Each probe runs once per classification fingerprint.

**Scope exception:** Disambiguation probes may query declared/known dependencies of the
affected service, within the same time window as the primary investigation
(e.g., upstream APIs, backing datastores) even though those are technically
outside the single-service scope restriction. This is permitted because playbook
`disambiguation_probe` definitions are pre-authored and bounded — they cannot expand into
unbounded global searches.

After all probes complete, feed results back to CLASSIFY for reclassification.

### Step 3: Single-Service Deep Dive

- Error grouping (frequency, first/last occurrence)
- Recent deployment correlation (deploy timestamp vs. error spike?)
- Resource metrics (CPU, memory, latency) if available

**CrashLoopBackOff triage (conditional — when `crash_loop_detected` signal is present):**

Before proposing workload-restart, complete the diagnostic sequence defined in the `workload-restart` playbook's `investigation_steps`. The sequence requires: pod describe → scoped events → termination reason and exit code (see exit code guide in Step 2) → previous container logs → deployment/probe configuration → rollout history correlation. Each step may redirect to a different root-cause playbook:
- Exit code 137 (OOMKilled) → resource-overload or node-resource-exhaustion, not restart
- Exit code 1 with stack trace after recent deploy → bad-release investigation
- Events show ImagePullBackOff or CreateContainerConfigError → pod-start failure branch below
- Crash onset correlates with rollout timestamp → bad-release-rollback investigation
- Only if triage is inconclusive and no other playbook has higher confidence does workload-restart remain a candidate.

**Probe and startup-envelope checks (conditional — when `liveness_probe_failures` signal is present or pod restart count is high without clear application errors):**

Before attributing failures to application state, verify whether probe configuration is appropriate:
1. **Probe configuration review:** Extract `initialDelaySeconds`, `timeoutSeconds`, `periodSeconds`, `failureThreshold`, and `startupProbe` (if any) from the pod spec
2. **Startup time analysis:** Compare `initialDelaySeconds` to actual container startup time. If startup takes longer than the initial delay and no startupProbe is configured, liveness probes will kill the container before it is ready — this is a probe misconfiguration, not an application failure
3. **Timeout budget:** Is `timeoutSeconds` realistic for what the probe endpoint does? If the probe hits a database or external service, network latency may exceed the timeout under load
4. **Restart cadence:** Calculate time between restarts. If it matches `initialDelaySeconds + (failureThreshold x periodSeconds)`, the probe is killing the container during startup — fix probe config, not restart
5. **Dependency reachability:** Does the probe endpoint depend on services that are currently unavailable? (database, cache, upstream API). If so, the probe failure is a symptom of dependency failure — route to dependency-failure investigation

Routing from probe findings — **this branch is guidance-only (no autonomous mutations)**:
- Probe timing causes restarts during startup → record "probe misconfiguration" as root cause in the investigation synthesis and recommend a config fix (increase `initialDelaySeconds`, add `startupProbe`) as a **postmortem action item**. Do NOT propose workload-restart — a restart will hit the same probe wall. There is no commandable playbook for probe config changes; the fix is a code/manifest change tracked through the normal development workflow.
- Probe endpoint depends on unavailable dependency → route to dependency-failure investigation
- Probe config is reasonable and application genuinely fails health checks → continue with workload-failure classification

**Pod-start failure branch (conditional — when events show `ImagePullBackOff`, `ErrImagePull`, or `CreateContainerConfigError`):**

These symptoms indicate the pod cannot start at all — this is fundamentally different from a running application crashing. Investigate before classifying:

1. **ImagePullBackOff / ErrImagePull:**
   - Extract the exact error message from pod events: "unauthorized" (credential issue), "not found" or "manifest unknown" (wrong image/tag), "timeout" or "connection refused" (registry unreachable)
   - Verify the image reference (registry, repository, tag) in the deployment spec
   - Check `imagePullSecrets` configuration: does the Secret exist, is it type `kubernetes.io/dockerconfigjson`, are credentials valid and not expired?
   - If image tag was recently changed → route to bad-release (wrong tag pushed)
   - If `imagePullSecrets` were changed or Secret is missing → route to config-regression
   - If registry is unreachable and no config changed → route to dependency-failure (registry as external dependency)

2. **CreateContainerConfigError:**
   - Check for missing ConfigMap or Secret references in the pod spec
   - Check if a referenced ConfigMap or Secret was recently deleted or renamed
   - Check environment variable references that point to non-existent keys
   - Route to config-regression for further investigation

3. **Volume mount failures** (`FailedMount`, `FailedAttachVolume`):
   - Check PVC status (Pending, Lost, Bound) and StorageClass availability
   - Check if the volume or StorageClass was recently modified
   - Route to infra-failure if the storage backend is unhealthy

This branch is non-mutating — it gathers evidence that feeds back into CLASSIFY for root-cause playbook selection. Do not propose restart or rollback from this branch.

**Infrastructure escalation (conditional):** If Step 3 reveals that multiple pods or services are failing simultaneously — especially with `context deadline exceeded`, widespread probe timeouts, or errors localized to a single node — the root cause is likely at the node or infrastructure level, not the application level. Shift investigation to:
- Node resource metrics (memory/CPU allocatable utilization)
- kubelet logs (housekeeping delays, probe failures, eviction events)
- GCE serial console (kernel OOM, balloon driver, memory pressure)
- Audit logs (maintenance-controller, drain events)

If a `node-resource-exhaustion` playbook is available, transition to CLASSIFY for structured scoring.

**Shared resource escalation (mandatory when detected):** If the degraded service is used by multiple consumers (authorization service, database, message broker, cache cluster, shared API gateway), follow the caller investigation procedure in `references/caller-investigation.md`. This is mandatory, not optional. The procedure identifies dominant callers, checks their ERROR logs and deployment history, compares distribution to baseline, and checks for amplification loops. Bounded to the shared resource's known consumer set — no unbounded global searches.

### Step 4: Autonomous Trace Correlation (Tier 1 Only)

If Tier 1 MCP tools are NOT available, skip this step entirely. Proceed to Step 5.

**Prerequisite — exemplar trace selection:** If Stage 2 logs contain multiple failing requests (>1), select one exemplar trace from the dominant error group (most frequent pattern) or the most recent failure with a `trace` field. Analyze only this single exemplar in Step 4.

**Extract trace_id and project_id** from the exemplar log entry's `trace` field (format: `projects/PROJECT_ID/traces/TRACE_ID`). Strip the prefix to get the raw TRACE_ID. Preserve PROJECT_ID for `get_trace`.

If no `trace` field is present in the failing log entries, skip this step entirely.

**Retrieve the trace:**
Call `get_trace(trace_id, project_id)` to retrieve the span timeline. Do NOT use `search_traces` in this step.

**Inspect spans for cross-service boundaries:**

1. **All spans within Service A only:** Skip hop. Proceed to Step 5.
2. **Exactly one other service (Service B) meets EITHER evidence path below:** Execute the hop (continue below).
3. **Multiple services meet evidence criteria, or 3+ services with any failure signals:** Present trace timeline to user. Do NOT autonomously choose. Let user specify which service.
4. **Other services appear but none meet either evidence path:** Skip hop. Note services in synthesis.

**Failure evidence (MUST be present in Service B span data — any one sufficient):**
- Span status code != OK (gRPC error)
- HTTP status >= 500 in span attributes
- Exception stack trace in span events

**Timeout cascade (ALL conditions required):**
- Service A failed with explicit timeout/deadline-exceeded error
- Service B span duration >= 80% of root span duration (computed: `(B span end - B span start) / (root span end - root span start)`)
- No other non-Service-A span >= 40% of root span duration

Latency-only spans (slow but no error/timeout) do NOT justify the hop.

If evidence is ambiguous or borderline, do NOT hop — present trace timeline and let user decide.

**Query Service B logs** using `list_log_entries`:
- **project_id:** Service B's project ID (from span resource labels). Same as Service A's if same project.
- **filter:** Scoped to `trace="projects/<Service B project>/traces/<TRACE_ID>"` AND Service B's concrete resource labels from the span data (e.g., `resource.type` plus `resource.labels.service_name` or equivalent — not all services use `service_name`; use whatever label the span provides)
- **time range:** Service B span start minus 1 minute to span end plus 1 minute
- **page_size:** <= 50 entries
- If Service B's identity (resource labels or project) is ambiguous, STOP and present trace to user.
- **STRICT CONSTRAINT:** Do not execute a second hop. Do not follow the trace into a third service.

**Synthesize the causal path only:**
- Include only spans on the causal path linking Service B's failure to Service A's error. Do not dump the full trace tree.
- Present both services' log evidence in chronological order
- If Service B logs return no useful signal, note the gap and proceed to Step 5
- Feed this synthesized causal timeline into Step 4b or Step 5

### Step 4b: Source Analysis (Conditional)

Analyzes source code at the deployed version to identify regression candidates. Full procedure in `references/source-analysis.md`.

**Gate — either path required:** (1) Actionable stack frame from Step 2, (2) Resolvable deployed ref from Step 2b, (3a) Bad-release: deploy within incident window or 4h before, OR (3b) Config-change: `config_change_correlated_with_errors` detected AND repo-backed (has git ref). User override: bypasses gate 3 but not 1-2. If no gate met: `source_analysis.status: skipped`.

**Post-hop rule:** If Step 4 shifted to Service B, resolve its workload identity from trace/log labels (not deployment name). One bounded lookup. If ambiguous, skip.

**Output:** `source_analysis.status` = `reviewed_no_regression` | `candidate_found` | `skipped` | `unavailable`. If `candidate_found`, feeds into Step 5 hypothesis. Tool tiers: GitHub API → `git show` → manual URL. Fail-open on API unavailability. Full procedure including cross-reference and bounded expansion steps in `references/source-analysis.md`.

### Step 5: Formulate Root Cause Hypothesis

State the hypothesis in one sentence. Then:

1. **Contradiction test:** Identify the strongest piece of evidence that would DISPROVE this hypothesis. Query for it. If found, revise the hypothesis before proceeding.
2. **Symptom coverage:** List every observed symptom. Mark each as "explained" or "unexplained" by the hypothesis. If any symptom is unexplained, either expand the hypothesis or note it as an open question.
3. **Alternative hypotheses:** Name at least one alternative explanation. State why the primary hypothesis is preferred over it, citing specific evidence.
4. **Chronic-vs-acute test:** If the hypothesized root cause is a condition that existed before the incident (a background job, a known workload pattern, a long-standing configuration), it is a **contributing factor**, not a trigger. Ask: "This condition has existed for days/weeks — what acute change in the preceding 72 hours made it fatal *now*?" Candidates include:
   - A deployment to any service that interacts with the chronic stressor (not just the symptomatic service)
   - A traffic pattern change (weekday vs. weekend, batch job schedule, seasonal load)
   - A cache expiry, certificate rotation, or configuration reload with delayed effect
   - A concurrent failure in a different service that shares infrastructure (amplification loop — see Step 3)
   - A caller entering a failure/retry loop (check Step 3 shared resource escalation findings — if dominant callers were not yet checked, return to Step 3 and complete the caller investigation before accepting a chronic hypothesis)

   **Mandatory evidence for traffic-pattern hypotheses:** If the hypothesis attributes the trigger to a traffic pattern change (e.g., "afternoon peak traffic"), verify against a baseline from a **different day at the same time** (or the nearest comparable stable window if traffic patterns changed recently). Compare: caller distribution, call volume per caller, and method mix. If the pattern matches the baseline (same callers, same volume), the traffic hypothesis is supported. If one caller's volume is anomalously high, investigate that caller's health before accepting the hypothesis.

5. **Capacity headroom check (when resource-related signals are present):** Compare current resource utilization against the nearest stable baseline (different day, same time window). Record:
   - Current vs baseline: node CPU/memory allocatable utilization, pod count, sum of resource requests
   - Headroom drift: has available capacity been shrinking over days/weeks? (query 7-day trend if metrics available)
   - HPA/quota status: is HPA at maximum replicas? Are resource quotas near limits?
   If headroom has been chronically shrinking, note as a contributing factor even if an acute trigger is identified. The acute trigger may recur at lower thresholds — the chronic drift makes the system fragile. If headroom data is unavailable, state "capacity headroom not assessed" and flag as an open question.

   If no acute change is found after active search, the hypothesis is weaker — note it as "chronic contributing factor without identified trigger" rather than confirmed root cause.

### Step 6: Flight Plan

Before touching any code, output a bulleted list of:
- Files to modify
- Logic to change
- Expected outcome

Ask for explicit developer approval before proceeding.

### Step 6b: Timeline Extraction

Before synthesizing (Step 7), extract candidate timeline events from all evidence collected during Steps 1-5. This gives Step 7 a structured input rather than relying on attention-based reconstruction.

For each timestamped event found in collected evidence, extract:
- **timestamp_utc:** the event timestamp in UTC
- **time_precision:** `exact` (from log/metric timestamp with second-level or better granularity), `minute` (from deploy event, alert firing, or minute-resolution metric), or `approximate` (from user report, estimated from context)
- **event_kind:** one of `log_entry` | `metric_alert` | `deploy_event` | `probe_event` | `user_report` | `recovery_signal`
- **description:** one-sentence description of what happened
- **evidence_source:** where this was observed (e.g., "SpiceDB gRPC logs", "k8s events")

**Dedupe rules:**
- If two events describe the same occurrence at different precisions, keep the higher-precision entry. E.g., "~14:18 SpiceDB spike" (approximate, user report) is superseded by "14:18:23 CheckPermission 4335ms" (exact, gRPC log).
- If `log_entry` and `metric_alert` cover the same moment, keep both — they are different evidence types for the same event.
- Deploy events from deployment metadata and from audit logs are the same event; keep the one with more detail.

**Scope:** Steps 1-5 evidence only. Exclude Flight Plan items (Step 6) — those are proposed actions, not observed events.

Sort chronologically. Present the candidate list to Step 7 for curation into the final timeline.

### Step 7: Context Discipline — Synthesize

Write a synthesized summary as an explicit output block. The summary MUST include all of the following (not just timeline and root cause):

1. **Timeline:** Curate the candidate timeline from Step 6b into the final timeline. Remove noise, merge related events, verify chronological ordering. Each entry retains `time_precision` and `evidence_source` from Step 6b. Flag any candidate events removed during curation (and why) so the completeness gate can assess coverage.
2. **Root cause:** The primary hypothesis with supporting evidence
3. **ruled-out hypotheses:** Each alternative considered, the disconfirming evidence found, and why it was eliminated
4. **hypothesis revisions:** Where the investigation changed direction, what triggered the revision, and what the previous hypothesis was
5. **Completeness gate answers:** Responses to Step 8 questions (captured here so they survive the context boundary)
6. **Inventory and impact:** Pod/replica counts, distribution, user-facing error counts from Steps 2b/2c

From this point forward, reference ONLY this summary (not raw log JSON). See Constraint 4.

### Step 8: Investigation Completeness Gate

Before transitioning to POSTMORTEM, answer each question explicitly in the synthesis output. Any question answered "No" or "Unknown" becomes an **Open Question** in the postmortem — it MUST NOT be papered over with assumptions.

| # | Question | Required evidence |
|---|----------|-------------------|
| 1 | Does the root cause explain ALL observed symptoms? | List each symptom and whether the hypothesis accounts for it |
| 2 | What evidence would disprove this root cause? Did you look for it? | Name the disconfirming evidence sought and what was found |
| 3 | When did the incident start AND end? | Both timestamps in UTC from log/metric evidence, not estimation. If kernel timestamps (seconds since boot) were used, note the conversion. For end time: search for recovery signals (pod restarts, deployment events, manual scaling, error rate returning to baseline) at least 60 minutes past the last observed error — recovery often comes from human intervention, not self-healing. |
| 4 | How many instances/replicas/pods exist? How many were affected? | Verified from metrics or deployment spec, not inferred from log observation |
| 5 | Were other services or components affected? | Checked — list affected or state "checked, none found" |
| 6 | Is this condition systemic (other nodes/instances at similar risk)? | Checked or state "not assessed" |
| 7 | Did the alerting system detect this? How quickly? | Which alerts fired, time from incident start to first alert, which alerts should have fired but didn't |
| 8 | When did humans learn about it and what did they do? | First human awareness (alert, report, support ticket), first action taken, resolution action. Use user-provided context if available; state "not captured" if not. |
| 9 | For shared-dependency failures: was caller-side amplification investigated? | Describe how dominant callers were identified (logs, traces, metrics, broker stats), what evidence was checked, and whether any caller was amplifying the failure. If shared-dependency escalation was not triggered, state "N/A — not a shared-dependency failure". |

**Gate rule:** If questions 1-3 have confident answers, proceed to POSTMORTEM. Questions 4-9 may be "not assessed" if investigation time is constrained, but must be flagged as open items. If question 1, 2, or 3 is "No" or "Unknown," return to INVESTIGATE Step 1 — for questions 1-2 with a revised hypothesis, for question 3 with targeted recovery-evidence queries.

### Step 9: Transition to POSTMORTEM

**Investigation path (mandatory):** Always generate the investigation path appendix as a subsection under Investigation Notes (section 8). The investigation path is the most valuable part of the postmortem for future investigators — it shows not just what was found, but what was considered and ruled out, preventing others from re-exploring dead ends.

Generate using the format in the Investigation Notes template (question → decisive evidence → conclusion per step, explicit Ruled out: lines for dead ends, Hypothesis revised: markers where thinking changed, Reviewer takeaway at the end). For straightforward investigations with no hypothesis revisions, the path will be shorter but still documents the ruled-out alternatives and the evidence chain that confirmed the root cause.

## EXECUTE

Entered after the user approves a high-confidence CLASSIFY decision at the HITL gate. This stage applies the mitigation command with a fingerprint safety check.

**Tool availability check:** Before proceeding, verify that the playbook's required tools are available. If a playbook requires `kubectl` and it is not installed:

> "This playbook requires `kubectl` for execution, but it is not available. You can install it with `brew install kubectl` or `gcloud components install kubectl`. Alternatively, you can run the command manually in a terminal with cluster access, or skip to INVESTIGATE."

Do not attempt to execute kubectl commands without kubectl installed. Present the command for the user to run externally if needed.

### Step 1: Fingerprint Recheck

Before executing the approved command, re-query the signals that formed the playbook's fingerprint. Compare current state against the evidence captured during CLASSIFY.

If the fingerprint has drifted (signals changed materially since classification):
- **Do NOT execute.** The situation has changed since the user approved.
- Present the drift summary and return to CLASSIFY with fresh evidence.

### Step 1b: Persist Pre-Execution Evidence

Write the evidence bundle's `pre.json` to `docs/postmortems/evidence/<bundle-id>/pre.json`. Contents: signal states from CLASSIFY, fingerprint snapshot from Step 1, and the final log window (last N entries matching the playbook's signals). All payloads MUST pass through `redact-evidence.sh` before writing. See Evidence Bundle for format and redaction details.

If the playbook specifies `requires_pre_execution_evidence: true`, this step is mandatory — do not proceed to Step 2 without writing `pre.json`.

### Step 2: Execute Command

If the fingerprint matches, execute the approved command from the playbook (or confirm that the user has run it externally).

Record the execution timestamp and the exact command executed.

### Step 3: Transition to VALIDATE

Immediately transition to VALIDATE after execution completes.

## VALIDATE

Two-phase post-execution validation. Determines whether the mitigation was effective.

### Phase 1: Stabilization Grace Period

Wait for `stabilization_delay_seconds` (from the playbook). During this period, only `hard_stop_conditions` are active. If any hard stop condition triggers, immediately transition to ESCALATE (see exit paths below).

Do not evaluate `stop_conditions` or `post_conditions` during stabilization — transient recovery noise is expected.

### Phase 2: Observation Window

After stabilization, begin sampling every `sample_interval_seconds` for a total of `validation_window_seconds` (both from the playbook).

At each sample:
- Evaluate `hard_stop_conditions` — if any trigger, immediately exit to ESCALATE
- Evaluate `stop_conditions` — if any trigger, immediately exit to ESCALATE
- Evaluate `post_conditions` — record pass/fail for each

### Exit Paths

**Validated — Success:**
All `post_conditions` passed consistently across the observation window. No stop conditions triggered.
- Record `verification_status: verified`
- Write `validate.json` to the evidence bundle with validation sample results, post_condition evaluations, and timing data. All payloads MUST pass through `redact-evidence.sh`.
- Transition to POSTMORTEM

**Validated — Failed (ESCALATE):**
A `hard_stop_condition` or `stop_condition` triggered during validation. The mitigation made things worse or did not help.
- Record `verification_status: failed`
- Write `validate.json` to the evidence bundle with the failure evidence, stop_condition trigger details, and timing data. All payloads MUST pass through `redact-evidence.sh`.
- Transition to INVESTIGATE (full Stage 2, not the limited CLASSIFY < 60 path)
- Present the validation failure evidence to the user

**Inconclusive:**
The observation window completed but `post_conditions` results are mixed or unclear.
- Present the validation data to the user with three options:
- Regardless of which option the user chooses, write `validate.json` to the evidence bundle with the partial results and timing data. All payloads MUST pass through `redact-evidence.sh`.
  1. **Extend:** Run another observation window
  2. **Escalate:** Transition to INVESTIGATE
  3. **Accept as mitigated (unverified):** Record `verification_status: unverified` and transition to POSTMORTEM

## Evidence Bundle

Evidence is persisted for postmortem traceability and audit.

### Bundle Structure

Evidence bundle directory: `docs/postmortems/evidence/<bundle-id>/`

Where `<bundle-id>` is `YYYY-MM-DD-<playbook-id>-<short-hash>` (short-hash from the session or incident identifier).

| File | Contents | Captured When |
|------|----------|---------------|
| `pre.json` | Signal states, fingerprint snapshot, log excerpts before execution | Before EXECUTE Step 2 |
| `validate.json` | Validation sample results, post_condition evaluations, timing data | After VALIDATE completes |

### Redaction

All evidence payloads MUST pass through `skills/incident-analysis/scripts/redact-evidence.sh` before being written to disk. This script strips sensitive fields (credentials, tokens, PII patterns) from JSON evidence.

### Destructive Action Evidence Rule

If the playbook specifies `requires_pre_execution_evidence: true`, the `pre.json` file MUST include the final log window (last N entries matching the playbook's signals) captured immediately before the command is proposed. This ensures a complete before/after record exists for destructive mitigations.

## Stage 3 — POSTMORTEM

### Step 1: Template Discovery

Check in order:
1. `docs/templates/postmortem.md` (project convention)
2. `.github/ISSUE_TEMPLATE/postmortem.md` (GitHub-native)
3. Built-in default schema: `references/postmortem-template.md` (8 sections ordered for reviewer flow — decisions first, evidence after, with optional investigation path appendix)

### Step 2: Directory Discovery

Check for existing directory:
1. `docs/postmortems/` or `docs/incidents/` (check both)
2. Create `docs/postmortems/` if neither exists

### Step 3: Generate Postmortem

Generate from the synthesized summary (NOT raw logs). Follow the template section order:
- Summary: one sentence plain language, then one paragraph technical
- Impact: user-facing impact first (error count, affected users, business impact from user-provided context), then infrastructure scope
- Action items: ordered by priority, each with current state, suggested owner, and due date. "Current state" describes the relevant existing configuration or deployed state for the system the action item targets — what is there today, not what should be. Check for functionally equivalent configurations, not just exact field matches. If current state cannot be determined, state "⚠ Not verified against live config." Flag unassigned items with "⚠ Owner needed"
- Root cause: concise causal chain, include scheduling/resource math if relevant
- Timeline: infrastructure events interleaved with human actions (alerts fired, human response, manual intervention), all UTC with evidence sources
- Contributing factors: ordered by impact, most impactful first
- Lessons learned: went well, went wrong, got lucky
- Investigation notes: ruled-out hypotheses, confidence levels, open questions

**Recovery verification (mandatory):**
- Timeline MUST include a verified recovery timestamp with evidence source (e.g., "first successful DB connection at 13:54:09 per proxy logs")
- If recovery was not verified from evidence, state: "Recovery time not verified — estimated at X based on Y"
- Impact duration = verified recovery time minus incident start time. Do not estimate.

**Mitigation Applied (subsection under "Root Cause & Trigger"):**

If a playbook-driven mitigation was executed during this incident, include the following under the "Root Cause & Trigger" section of the postmortem:

| Field | Value |
|-------|-------|
| Playbook ID | The `id` of the playbook that was executed |
| Playbook Name | Human-readable name from the playbook |
| Command Executed | The exact interpolated command that was run |
| Execution Time | Timestamp when EXECUTE Step 2 completed |
| Verification Status | `verified`, `failed`, or `unverified` (from VALIDATE exit path) |
| Evidence Bundle | Relative path to `docs/postmortems/evidence/<bundle-id>/` |

Keep the 8 section headers (Summary, Impact, Action Items, Root Cause & Trigger, Timeline, Contributing Factors, Lessons Learned, Investigation Notes) intact. The mitigation details are a subsection within Root Cause & Trigger, not a new top-level section. If a project template overrides this structure (Step 1), follow the project template instead.

**Permalink formatting (apply to all references in the generated postmortem):**
- **Trace IDs:** Format as `[Trace TRACE_ID](https://console.cloud.google.com/traces/list?project=PROJECT_ID&tid=TRACE_ID)` using the project_id and trace_id from Stage 2. If cross-project trace correlation was used (Step 4), use the relevant project for each reference — Service A traces use Service A's project_id, Service B traces use Service B's project_id.
- **Git commits:** If a commit hash is referenced (e.g., a deployment trigger), derive the repo URL via `git remote get-url origin`. If GitHub-hosted, format as `[Commit SHORT_HASH](https://github.com/ORG/REPO/commit/FULL_HASH)`. If not GitHub-hosted or the command fails, use the raw commit hash without a link.

### Step 4: Write to Disk

Write to `docs/postmortems/YYYY-MM-DD-<kebab-case-summary>.md`

The summary portion MUST be lowercase kebab-case (e.g., `checkout-500s`, `auth-timeout-spike`). No spaces, no mixed casing.

### Step 5: Terminal Output

```
Postmortem saved to docs/postmortems/YYYY-MM-DD-<kebab-case-summary>.md.
Review the document and action items.
```

## Reference Tables

LQL filter patterns, Tier 1 MCP tool parameters, and Tier 2 gcloud CLI commands: see `references/query-patterns.md`.
