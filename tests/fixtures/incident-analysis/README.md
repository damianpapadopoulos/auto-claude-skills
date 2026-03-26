# Incident Analysis Test Fixtures

Fixtures for output quality testing of the incident-analysis skill.

## Authoring Rules

1. **Real incidents only.** Every fixture must come from an actual production incident
   postmortem. No synthetic cases authored by the skill developer.
2. **Ground truth is human-authored.** Expected outputs are written by the incident
   responder or postmortem author, not derived from running the skill.
3. **Minimal fixture structure:**

```json
{
  "id": "2026-03-15-checkout-oom",
  "description": "OOMKilled pods on checkout-service after memory limit change",
  "source_postmortem": "docs/postmortems/2026-03-15-checkout-oom.md",
  "input": {
    "service": "checkout-service",
    "environment": "hb-prod",
    "symptoms": "pods OOMKilled, 500 errors on /api/checkout",
    "time_window": "2026-03-15T14:00:00Z/2026-03-15T15:00:00Z"
  },
  "expected": {
    "root_cause_contains": ["OOMKilled", "memory limit"],
    "timeline_has_entries": true,
    "playbook_classification": "node-resource-exhaustion",
    "signals_detected": ["memory_pressure_detected", "crash_loop_detected"]
  }
}
```

4. **One file per incident.** Name: `YYYY-MM-DD-<kebab-summary>.json`
5. **No PII.** Redact service names, IPs, and user data if needed.
