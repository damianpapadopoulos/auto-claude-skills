# Investigation Summary — Canonical YAML Schema

Emitted in Step 7 (Context Discipline — Synthesize). Referenced by the completeness gate (Step 8), POSTMORTEM stage, and eval fixtures.

```yaml
investigation_summary:
  scope:
    service: "<service name>"
    environment: "<environment>"
    time_window: "<ISO start>/<ISO end>"
    mode: "full" | "live-triage"
  dominant_errors:
    - bucket: "<error signature or class>"
      count: <N>
      percentage: <N>%
      aggregation_source: "error_reporting" | "metric" | "sample" | "unavailable"
  chosen_hypothesis:
    statement: "<one sentence>"
    confidence: "high" | "medium" | "low"
    supporting_evidence:
      - "<evidence reference>"
    contradicting_evidence_sought: "<what was looked for>"
    contradicting_evidence_found: "<what was found, or 'none'>"
    evidence_links:  # optional — present only when valid URLs were captured
      - type: "logs" | "baseline_logs" | "metrics" | "trace" | "deployment" | "source"
        label: "<display text>"
        url: "<https://...>"
  ruled_out:
    - hypothesis: "<alternative>"
      reason: "<disconfirming evidence>"
      evidence_links:  # optional — present only when valid URLs were captured
        - type: "..."
          label: "..."
          url: "..."
  evidence_coverage:
    logs: "complete" | "partial" | "unavailable"
    k8s_state: "complete" | "partial" | "unavailable"
    metrics: "complete" | "partial" | "unavailable"
    source_analysis: "complete" | "partial" | "skipped" | "unavailable"
    trace_correlation: "complete" | "partial" | "skipped" | "unavailable"
  gaps:
    - "<what could not be checked> (<reason>)"
  timeline_entries:
    - timestamp_utc: "<UTC>"
      time_precision: "exact" | "minute" | "approximate"
      event_kind: "<kind>"
      description: "<what happened>"
      evidence_source: "<where observed>"
  recovery_status:
    recovered: true | false | "unknown"
    recovery_time_utc: "<UTC or null>"
    recovery_evidence: "<source>"
    verification: "verified" | "estimated" | "not_verified"
  open_questions:
    - "<question>"
  service_attribution:  # optional — required when 2+ services evaluated in one causal narrative
    - service: "<service name>"
      status: "confirmed-dependent" | "independent" | "inconclusive" | "not-investigated"
      evidence: "<specific query result or 'not queried'>"
      independent_root_cause: "<one sentence, only when status=independent and cause known>"
  service_error_inventory:  # optional — required when Step 3c executes
    - service: "<name>"
      error_class: "<dominant error>"
      tier: 1|2|3
      count_incident: <N>
      count_baseline: <N>
      deployment_in_72h: true|false
      deployment_timestamp: "<UTC or null>"
      investigated: true|false
      infra_status: "assessed" | "not_applicable" | "unavailable" | "not_captured"
      infra_evidence: "<what was checked>"
      infra_reason: "<why not assessed, if status != assessed>"
      app_status: "assessed" | "not_applicable" | "unavailable" | "not_captured"
      app_evidence: "<what was checked>"
      app_reason: "<why not assessed, if status != assessed>"
      mechanism_status: "known" | "not_yet_traced" | "not_applicable"
      pool_exhaustion_type: "app-side" | "database-level" | "not_determined"  # conditional — when connection pool exhaustion detected
      evidence_links:  # optional — present only when valid URLs were captured
        - type: "..."
          label: "..."
          url: "..."
  root_cause_layer_coverage:
    infrastructure_status: "assessed" | "not_applicable" | "unavailable" | "not_captured"
    infrastructure_evidence: "<summary of what was checked for the root-cause service>"
    infrastructure_reason: "<why not assessed, if status != assessed>"
    application_status: "assessed" | "not_applicable" | "unavailable" | "not_captured"
    application_evidence: "<summary of what was checked for the root-cause service>"
    application_reason: "<why not assessed, if status != assessed>"
    mechanism_status: "known" | "not_yet_traced" | "not_applicable"
    mechanism_evidence: "<code path, cache/config state, retry behavior, or consumer mechanism identified>"
  tested_intermediate_conclusions:
    - conclusion: "<explicit statement>"
      used_in_causal_chain: true|false
      disconfirming_evidence_sought: "<query or check performed>"
      result: "supported" | "disproved" | "inconclusive"
      evidence: "<specific result>"
```
