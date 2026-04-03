# Query Patterns and Tool Reference

LQL filter patterns, Tier 1 MCP tools, and Tier 2 gcloud CLI commands used during investigation.

## LQL Reference Patterns

| Pattern | LQL Filter |
|---------|-----------|
| Recent errors | `severity>=ERROR AND timestamp>="YYYY-MM-DDTHH:MM:SSZ"` |
| Cloud Run service | `resource.type="cloud_run_revision" AND resource.labels.service_name="X"` |
| GKE pod errors | `resource.type="k8s_container" AND resource.labels.cluster_name="X"` |
| HTTP 5xx | `httpRequest.status>=500` |
| Trace correlation | `trace="projects/PROJECT/traces/TRACE_ID"` |
| Text search | `textPayload=~"pattern"` |
| JSON payload field | `jsonPayload.fieldName="value"` |

## Tier 1 MCP Tool Reference

| Investigation Step | MCP Tool | Parameters |
|-------------------|----------|------------|
| Query logs | `list_log_entries` | filter (LQL), project_id, page_size |
| Search traces | `search_traces` | filter, project_id (not used in Step 4; retained for future versions) |
| Get trace detail | `get_trace` | trace_id, project_id |
| Check metrics | `list_time_series` | filter, interval |
| Check alerts | `list_alert_policies` | project_id |

## Aggregate Error Fingerprinting

Prefer aggregate queries to identify the dominant error class before reading raw logs. Availability varies — use the best source available and label the result.

| Tier | Method | Command/Tool | Identifies Error Signatures? | Notes |
|------|--------|-------------|------------------------------|-------|
| Tier 1 | Error group stats | `list_group_stats` with project_id, time_range | **Yes** — groups by recurring stack trace/message | Best source. Not always available (requires Error Reporting API enabled on project). Check availability before relying on it. |
| Tier 2 | Error reporting CLI | `gcloud beta error-reporting events list --service=X --format=json --limit=20` | **Yes** — groups by error signature with counts | Beta command. Same backend as `list_group_stats`. Requires Error Reporting API. |
| Tier 1/2 | Severity-level counts | `list_time_series` with `metric.type="logging.googleapis.com/log_entry_count"` | **No** — counts by severity/container only | Tells you "200 ERRORs on service X" but not which error classes. Useful for magnitude, not fingerprinting. |
| Tier 2 | Client-side bucketing | `gcloud logging read ... --limit=100` piped through jq `group_by(.jsonPayload.message[:80])` | **Partial** — groups within a capped sample | ⚠ Sample-biased. Label as `aggregation_source: sample`. Better than no grouping but still over-represents recent entries. |

## Tier 2 gcloud CLI Reference

| Investigation Step | Bash Command |
|-------------------|-------------|
| Query logs | `gcloud logging read "$(cat "$LQL_FILE")" --project=X --format=json --limit=50` (see temp-file pattern) |
| List traces | `gcloud traces list --project=X --format=json` |
| Error events | `gcloud beta error-reporting events list --service=X --format=json` (beta) |
| Metrics | `gcloud monitoring metrics list --project=X --format=json` (limited) |
