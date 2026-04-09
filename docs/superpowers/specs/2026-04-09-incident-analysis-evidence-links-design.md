# Design: Incident Analysis — Evidence Links

**Date:** 2026-04-09
**Skill:** incident-analysis (SKILL.md)
**Prerequisite:** Investigation hardening (Constraints 10-11, dual-layer fields, Step 3c escalation, anti-anchoring, gate tightening) — shipped 2026-04-08.
**Motivation:** Investigation synthesis references evidence by prose description only. An investigator reading "helper-service had 1,147 HandlebarsException errors" cannot click through to verify — they must reconstruct the LQL filter manually. alert-hygiene already solves this with contextual action links (SKILL.md line 765). This change brings the same discipline to incident-analysis.

## Scope

**In scope (v1):**
- Constraint 12 (Evidence Links) in SKILL.md
- New reference file `references/evidence-links.md` with URL templates and encoding rules
- `evidence_links` YAML arrays on three synthesis blocks
- `**Links:**` line in Step 7 prose
- Static content tests + 1 behavioral eval fixture

**Out of scope (follow-up):**
- Postmortem reuse of synthesis links (the postmortem already has trace/commit permalink rules; extending it to consume `evidence_links` is a separate change)
- `verification_commands` for kubectl or other non-URL evidence
- Links in timeline entries, completeness gate, or `root_cause_layer_coverage`

## Changes

### 1. Behavioral Constraint 12 — Evidence Links

**Location:** `SKILL.md` § Behavioral Constraints, after Constraint 11, before `## Investigation Modes`

**Purpose:** Ensure investigator-facing claims in the synthesis include clickable verification links when URL parameters are available.

**Text:**

> ### 12. Evidence Links
>
> For each of the three claim surfaces in the Step 7 synthesis — the chosen root-cause statement, each ruled-out hypothesis, and each `service_error_inventory` entry — include clickable verification links when the required URL parameters were captured at query time. This constraint is active across Steps 2-7.
>
> **Allowed link types:**
>
> | Type | Label pattern | When |
> |------|--------------|------|
> | `logs` | "{Service} incident logs" | LQL query during Steps 2, 3, 3c |
> | `baseline_logs` | "{Service} baseline logs" | Baseline comparison supporting a claim (Step 3c tier classification, Step 5 recurring-workload check) |
> | `metrics` | "{Service} {metric_name}" | `list_time_series` or Metrics Explorer data supporting a claim (Steps 2c, 3, 5) |
> | `trace` | "Trace {first_8_chars}" | Step 4 trace correlation in the evidence chain |
> | `deployment` | "{Service} deploy history" | Deployment correlation (Steps 3, 3c) |
> | `source` | "Commit {first_7_chars}" or "{file_name}" | Step 4b source analysis candidate |
>
> **Where links appear:**
> - **Prose synthesis (Step 7):** One `**Links:** [label](url) · [label](url)` line after each root cause statement (max 3 links) and each ruled-out hypothesis (max 2 links). Separator ` · `.
> - **YAML schema:** `evidence_links` arrays on `chosen_hypothesis`, each `ruled_out` entry, and each `service_error_inventory` entry.
>
> **YAML item shape:**
> ```yaml
> evidence_links:
>   - type: "logs" | "baseline_logs" | "metrics" | "trace" | "deployment" | "source"
>     label: "<display text>"
>     url: "<https://...>"
> ```
>
> **Omission rules:**
> - If the required parameters to build a trustworthy URL are missing, omit the link and describe the evidence source in prose. Never emit placeholder, reconstructed, or guessed URLs.
> - If a constructed URL would open a generic landing page (losing its filter or time range), omit it.
> - Omit the `evidence_links` field entirely when no valid URL was captured for that block. Do not emit empty arrays.
>
> **Where links do NOT appear:** timeline entries, completeness gate answers, `tested_intermediate_conclusions`, `root_cause_layer_coverage`, `service_attribution`.
>
> **Capture rule:** Record link inputs (project_id, LQL filter, time window, trace_id, commit SHA, metric_type, metric filter) at query time. Do not reconstruct URLs retroactively from prose summaries — parameters may be lost.
>
> **Exclusion:** kubectl commands and MCP tool invocations are not evidence links. Only clickable URLs that open a verification view in a browser.
>
> **Label normalization:** Use stable, human-readable labels: `{Service} incident logs`, `{Service} baseline logs`, `{Service} {metric_name}`, `Trace {first_8_chars}`, `{Service} deploy history`, `Commit {first_7_chars}`. Labels must not contain raw LQL, full SHAs, or URL fragments.
>
> URL construction templates and encoding rules: `references/evidence-links.md`.

---

### 2. Reference file — `references/evidence-links.md`

**Location:** New file `skills/incident-analysis/references/evidence-links.md`

**Purpose:** URL templates, encoding rules, required parameters, and worked examples for each link type. Keeps SKILL.md focused on behavioral rules.

**Contents:**

#### URL templates

| Type | URL pattern | Notes |
|------|-------------|-------|
| `logs` | `https://console.cloud.google.com/logs/query;query={ENCODED_LQL};timeRange={START}%2F{END}?project={PROJECT}` | Canonical base URL only — no UI extras like `summaryFields` |
| `baseline_logs` | Same as `logs` with the baseline time window | Same construction, different timestamps |
| `metrics` | `https://console.cloud.google.com/monitoring/metrics-explorer?project={PROJECT}&pageState=...` | `pageState` is a best-effort deeplink; exact JSON structure documented in examples, not normative |
| `trace` | Reuses the existing postmortem permalink formatting rule (SKILL.md § POSTMORTEM Step 3): `https://console.cloud.google.com/traces/list?project={PROJECT}&tid={TRACE_ID}` | No new rule needed |
| `deployment` | Cloud Run: `https://console.cloud.google.com/run/detail/{REGION}/{SERVICE}/revisions?project={PROJECT}` / GKE: `https://console.cloud.google.com/kubernetes/deployment/{ZONE}/{CLUSTER}/{NAMESPACE}/{DEPLOYMENT}/overview?project={PROJECT}` / Other platforms: omit link | Platform-specific construction under one link type |
| `source` | Reuses the existing postmortem permalink formatting rule (SKILL.md § POSTMORTEM Step 3): `https://github.com/{ORG}/{REPO}/commit/{FULL_SHA}` or `https://github.com/{ORG}/{REPO}/blob/{REF}/{FILE_PATH}` | Derive org/repo from `git remote get-url origin`. If not GitHub-hosted, omit link |

#### Encoding rules

- LQL filters: URL-encode spaces (`%20`), quotes (`%22`), `>=` (`%3E%3D`), newlines (`%0A`). Timestamps in ISO 8601 UTC.
- Metrics Explorer `pageState`: JSON object URL-encoded as a query parameter value. Structure varies by metric type — use examples as guidance, not as a byte-for-byte contract.
- Tier 1 vs Tier 2 produces the same URL output: the link always points to the Console view, regardless of which tool executed the query.

#### Required parameters and fallback

| Type | Required parameters | When missing |
|------|-------------------|-------------|
| `logs` | project_id, LQL filter, start timestamp, end timestamp | Omit link, describe query in prose |
| `baseline_logs` | project_id, LQL filter, baseline start, baseline end | Omit link |
| `metrics` | project_id, metric_type, metric filter, start, end | Omit link |
| `trace` | project_id, trace_id | Omit link |
| `deployment` | project_id, service/deployment name, region or zone+cluster+namespace | Omit link, state deployment checked in prose |
| `source` | org, repo (from git remote), commit SHA or file path + ref | If not GitHub-hosted or remote unavailable, omit link |

#### Validation rule

Before emitting a link, verify the URL retains its filter and time range. If the constructed URL would open a generic landing page (Logs Explorer with no query, Metrics Explorer with no filter, Cloud Run with only the project), omit it and describe the evidence in prose. A bad link is worse than no link.

#### Worked examples

One example per link type showing input parameters → constructed URL → formatted label. (Examples to be written in the implementation plan, not specified here.)

---

### 3. YAML schema extensions

**Location:** `SKILL.md` § Step 7 investigation_summary YAML

**3a. `chosen_hypothesis`** — add `evidence_links` after `contradicting_evidence_found`:

```yaml
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
```

**3b. `ruled_out` entries** — add `evidence_links` per entry:

```yaml
ruled_out:
  - hypothesis: "<alternative>"
    reason: "<disconfirming evidence>"
    evidence_links:  # optional — present only when valid URLs were captured
      - type: "..."
        label: "..."
        url: "..."
```

**3c. `service_error_inventory` entries** — add `evidence_links` per service:

```yaml
service_error_inventory:
  - service: "<name>"
    # ... existing fields through mechanism_status ...
    evidence_links:  # optional — present only when valid URLs were captured
      - type: "..."
        label: "..."
        url: "..."
```

**Max links per block:** 3 per `chosen_hypothesis`, 2 per `ruled_out` entry, 3 per `service_error_inventory` entry.

**Field presence rule:** `evidence_links` is present only when at least one valid URL was captured. Do not emit empty arrays.

---

### 4. Step 7 prose placement

**Location:** `SKILL.md` § Step 7, after the synthesis content list (item 7)

**Text:**

> 8. **Evidence links (Constraint 12):** After the root cause statement in the prose synthesis, include a `**Links:**` line with up to 3 verification links. After each ruled-out hypothesis, include a `**Links:**` line with up to 2 verification links. Use markdown link syntax with ` · ` separator. Omit the `**Links:**` line entirely when no valid URLs are available for that block.

---

### 5. Testing

**Static content assertions** (`tests/test-incident-analysis-content.sh`):

1. Constraint 12 exists: `"Evidence Links"` in SKILL.md
2. Constraint 12 defines allowed types: `"logs.*baseline_logs.*metrics.*trace.*deployment.*source"` in SKILL.md
3. Constraint 12 has omission rule: `"Omit the.*evidence_links.*field entirely"` in SKILL.md
4. Constraint 12 enforces max links: `"Max 3 links"` in SKILL.md
5. Constraint 12 excludes timeline/gate: `"timeline entries.*completeness gate"` in SKILL.md
6. `evidence_links` in `chosen_hypothesis` YAML: `"evidence_links:"` appears in the investigation_summary YAML block
7. Reference file exists: `references/evidence-links.md`
8. Reference file has Logs Explorer pattern: `"console.cloud.google.com/logs/query"` in reference file
9. Reference file reuses postmortem rules: `"postmortem permalink"` in reference file
10. Reference file has label normalization: `"stable.*human-readable"` in reference file
11. Omission rule for missing parameters: `"Never emit placeholder.*reconstructed.*guessed"` in SKILL.md

**Eval coverage** (`tests/test-incident-analysis-evals.sh`):

Add one pattern to the behavior coverage loop: `"evidence.link\|Links:.*\\·\|verification.*link"`

**Behavioral eval fixture** (`tests/fixtures/incident-analysis/evals/behavioral.json`):

One new fixture: `evidence-links-in-synthesis` — multi-service incident where the synthesis should include `**Links:**` lines and `evidence_links` YAML entries for the root cause and at least one inventory service.

---

### 6. Postmortem reuse (follow-up, not v1)

The postmortem already has trace and commit permalink rules. A follow-up change could extend the POSTMORTEM stage to consume `evidence_links` from the synthesis YAML, adding Logs Explorer and Metrics Explorer links to the Timeline section. This is explicitly out of scope for this change to keep the implementation focused on the investigator workflow.

---

## Files Modified

| File | Change |
|------|--------|
| `skills/incident-analysis/SKILL.md` | Constraint 12, YAML schema extensions, Step 7 prose placement rule |
| `skills/incident-analysis/references/evidence-links.md` | New file: URL templates, encoding, parameters, examples |
| `tests/test-incident-analysis-content.sh` | 11 static content assertions |
| `tests/test-incident-analysis-evals.sh` | 1 coverage pattern addition |
| `tests/fixtures/incident-analysis/evals/behavioral.json` | 1 new fixture |
