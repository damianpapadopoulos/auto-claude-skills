# Evidence Links — URL Construction Reference

URL templates, encoding rules, required parameters, and worked examples for the 6 evidence link types defined in Constraint 12.

## URL Templates

| Type | URL Pattern | Notes |
|------|-------------|-------|
| `logs` | `https://console.cloud.google.com/logs/query;query={ENCODED_LQL};timeRange={START}%2F{END}?project={PROJECT}` | Canonical base URL only — no UI extras like `summaryFields` |
| `baseline_logs` | Same as `logs` with the baseline time window | Same construction, different timestamps |
| `metrics` | `https://console.cloud.google.com/monitoring/metrics-explorer?project={PROJECT}&pageState=...` | `pageState` is a best-effort deeplink; exact JSON structure in examples below, not normative |
| `trace` | Reuses the existing postmortem permalink formatting rule (SKILL.md § POSTMORTEM Step 3): `https://console.cloud.google.com/traces/list?project={PROJECT}&tid={TRACE_ID}` | No new construction rule needed |
| `deployment` | Cloud Run: `https://console.cloud.google.com/run/detail/{REGION}/{SERVICE}/revisions?project={PROJECT}` / GKE: `https://console.cloud.google.com/kubernetes/deployment/{ZONE}/{CLUSTER}/{NAMESPACE}/{DEPLOYMENT}/overview?project={PROJECT}` / Other platforms: omit link | Platform-specific construction under one link type |
| `source` | Reuses the existing postmortem permalink formatting rule (SKILL.md § POSTMORTEM Step 3): `https://github.com/{ORG}/{REPO}/commit/{FULL_SHA}` or `https://github.com/{ORG}/{REPO}/blob/{REF}/{FILE_PATH}` | Derive org/repo from `git remote get-url origin`. If not GitHub-hosted, omit link |

## Encoding Rules

- **LQL filters:** URL-encode spaces (`%20`), quotes (`%22`), `>=` (`%3E%3D`), newlines (`%0A`). Timestamps in ISO 8601 UTC.
- **Metrics Explorer `pageState`:** JSON object URL-encoded as a query parameter value. Structure varies by metric type — use examples as guidance, not as a byte-for-byte contract.
- **Tier independence:** Tier 1 (MCP) and Tier 2 (gcloud CLI) produce the same URL output — the link always points to the Cloud Console view, regardless of which tool executed the query.

## Required Parameters and Fallback

| Type | Required Parameters | When Missing |
|------|-------------------|-------------|
| `logs` | project_id, LQL filter, start timestamp, end timestamp | Omit link, describe query in prose |
| `baseline_logs` | project_id, LQL filter, baseline start, baseline end | Omit link |
| `metrics` | project_id, metric_type, metric filter, start, end | Omit link |
| `trace` | project_id, trace_id | Omit link |
| `deployment` | project_id, service/deployment name, region or zone+cluster+namespace | Omit link, state deployment checked in prose |
| `source` | org, repo (from git remote), commit SHA or file path + ref | If not GitHub-hosted or remote unavailable, omit link |

## Validation Rule

Before emitting a link, verify the URL retains its filter and time range. If the constructed URL would open a generic landing page (Logs Explorer with no query, Metrics Explorer with no filter, Cloud Run with only the project), omit it and describe the evidence in prose. A bad link is worse than no link.

## Label Normalization

Use stable, human-readable labels. Labels must not contain raw LQL, full SHAs, or URL fragments.

| Type | Label Pattern | Example |
|------|--------------|---------|
| `logs` | "{Service} incident logs" | "checkout-service incident logs" |
| `baseline_logs` | "{Service} baseline logs" | "checkout-service baseline logs" |
| `metrics` | "{Service} {metric_name}" | "checkout-service error_count" |
| `trace` | "Trace {first_8_chars}" | "Trace a1b2c3d4" |
| `deployment` | "{Service} deploy history" | "checkout-service deploy history" |
| `source` | "Commit {first_7_chars}" or "{file_name}" | "Commit f4e8a12" or "CheckoutHandler.java" |

## Worked Examples

### logs

**Input:** project_id=`my-project`, LQL=`resource.type="k8s_container" AND resource.labels.container_name="checkout-service" AND severity>=ERROR`, start=`2026-03-09T14:00:00Z`, end=`2026-03-09T15:00:00Z`

**URL:** `https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%20AND%20resource.labels.container_name%3D%22checkout-service%22%20AND%20severity%3E%3DERROR;timeRange=2026-03-09T14:00:00Z%2F2026-03-09T15:00:00Z?project=my-project`

**Formatted:** `[checkout-service incident logs](https://console.cloud.google.com/logs/query;query=...?project=my-project)`

### baseline_logs

**Input:** Same LQL as above, baseline window: start=`2026-03-08T14:00:00Z`, end=`2026-03-08T15:00:00Z`

**URL:** Same pattern as `logs`, with baseline timestamps substituted.

**Formatted:** `[checkout-service baseline logs](https://console.cloud.google.com/logs/query;query=...?project=my-project)`

### metrics

**Input:** project_id=`my-project`, metric_type=`logging.googleapis.com/log_entry_count`, filter=`resource.type="k8s_container" AND resource.labels.container_name="checkout-service"`, start/end as above

**URL:** `https://console.cloud.google.com/monitoring/metrics-explorer?project=my-project&pageState=%7B%22timeSeriesFilter%22%3A%7B%22filter%22%3A%22metric.type%3D%5C%22logging.googleapis.com%2Flog_entry_count%5C%22%20AND%20resource.labels.container_name%3D%5C%22checkout-service%5C%22%22%7D%7D`

**Formatted:** `[checkout-service error_count](https://console.cloud.google.com/monitoring/metrics-explorer?project=my-project&pageState=...)`

**Note:** `pageState` JSON structure is best-effort. The exact encoding may vary by browser and Console version. If the URL does not resolve to the intended metric view, omit it.

### trace

**Input:** project_id=`my-project`, trace_id=`a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6`

**URL:** `https://console.cloud.google.com/traces/list?project=my-project&tid=a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6`

**Formatted:** `[Trace a1b2c3d4](https://console.cloud.google.com/traces/list?project=my-project&tid=a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6)`

### deployment (Cloud Run)

**Input:** project_id=`my-project`, region=`europe-west6`, service=`checkout-service`

**URL:** `https://console.cloud.google.com/run/detail/europe-west6/checkout-service/revisions?project=my-project`

**Formatted:** `[checkout-service deploy history](https://console.cloud.google.com/run/detail/europe-west6/checkout-service/revisions?project=my-project)`

### deployment (GKE)

**Input:** project_id=`my-project`, zone=`europe-west6-a`, cluster=`prod-cluster`, namespace=`default`, deployment=`checkout-service`

**URL:** `https://console.cloud.google.com/kubernetes/deployment/europe-west6-a/prod-cluster/default/checkout-service/overview?project=my-project`

**Formatted:** `[checkout-service deploy history](https://console.cloud.google.com/kubernetes/deployment/europe-west6-a/prod-cluster/default/checkout-service/overview?project=my-project)`

### source

**Input:** org=`my-org`, repo=`checkout-service`, commit=`f4e8a12b9c3d5e6f7a8b9c0d1e2f3a4b5c6d7e8f`

**URL:** `https://github.com/my-org/checkout-service/commit/f4e8a12b9c3d5e6f7a8b9c0d1e2f3a4b5c6d7e8f`

**Formatted:** `[Commit f4e8a12](https://github.com/my-org/checkout-service/commit/f4e8a12b9c3d5e6f7a8b9c0d1e2f3a4b5c6d7e8f)`
