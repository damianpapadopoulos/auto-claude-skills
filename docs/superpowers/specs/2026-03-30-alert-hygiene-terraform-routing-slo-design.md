# Alert Hygiene: Terraform, Routing & SLO Refinements

**Date:** 2026-03-30
**Status:** Approved
**Scope:** alert-hygiene skill — SKILL.md + compute-clusters.py + new Stage 4/5 enrichments

## Problem

The alert-hygiene skill produces actionable reports but has three gaps that reduce the actionability of its findings:

1. **IaC Location is manual.** The skill asks for a GitHub org and constructs search URLs, but never attempts to locate the actual Terraform file. Engineers must search manually before they can open a PR.
2. **Routing gaps are data, not findings.** The skill computes `unlabeled_ranking` and surfaces it as a table, but doesn't promote high-impact routing problems to Investigate items with prescribed actions.
3. **SLO coverage is opaque.** The skill identifies SLO-redesign candidates from alert patterns, but has no visibility into which services actually have SLO definitions, producing generic recommendations instead of targeted coverage gap analysis.

## Design Constraints

- **No new runtime dependencies.** Python scripts remain stdlib-only. Ruby (stdlib yaml/json, available on macOS) is used for YAML parsing only.
- **Optional enrichment.** All GitHub-dependent features degrade gracefully when `gh` is unavailable or `github_org` is not provided. Core analysis (Stages 1-3, 5) runs unchanged.
- **Fail-loud, not fail-open.** Every data-fetching step checks exit codes explicitly. Errors produce structured status artifacts, not silent empty files.
- **Entity consistency.** Policy-level checks produce policy-level findings. Cluster-level checks produce cluster-level findings. No mixing.
- **Conservative matching.** `service_key` matching is normalize → exact-match only. Unmatched keys stay unmatched — no fuzzy guessing.
- **SLO cross-reference produces "review candidate" language, not proof of overlap.** `slo-services.json` only carries service names, not signal coverage metadata.
- **Confirmed IaC Location remains out of scope** for this iteration. GitHub search can upgrade to Likely, not Confirmed. Confirmed requires opening the file and verifying match context.
- **This change requires script updates + spec updates + test updates**, not just SKILL.md edits.

## External Context

**Monitoring IaC structure** (discovered via GitHub exploration):
- Central repo: `oviva-ag/monitoring`
- Two-tier Terraform: reusable modules in `tf/modules/` + per-squad instantiations in `tf/squads/<name>/`
- Two patterns: module invocations (standardized) and inline `google_monitoring_alert_policy` resources (custom PromQL)
- All alerts use `condition_prometheus_query_language` — no MQL or log-based conditions
- Routing via `user_labels.squad` on each policy
- SLO definitions in `tf/slo-config.yaml`
- Reference: `oviva-ag/claude-code-plugin/plugins/oviva-skills/skills/monitoring/` (external monitoring skill used for cross-reference)

**Decision: NewRelic is no longer used.** The GCP-only pipeline assumption is correct, not a limitation.

## Changes

### Section 1: Stage 1 — SLO Config Data Pull (Optional Enrichment)

Stage 1 gains an optional GitHub enrichment step after pulling policies and incidents. It is not a peer data source — the core analysis runs without it.

**Flow:**
1. Short-circuit if `github_org` is empty → `{"status":"unavailable","reason":"github_org_not_provided","count":0}`
2. Short-circuit if `gh` not available or not authenticated → `{"status":"unavailable","reason":"gh_not_available","count":0}`
3. Fetch `slo-config.yaml` via `gh api` to `$WORK_DIR/slo-raw-b64.txt` (checked — error to sidecar `slo-fetch-err.txt`)
4. Decode base64 to `$WORK_DIR/slo-config.yaml` (checked — separate step, no pipes)
5. Extract service names via Ruby stdlib YAML (checked — parse failure to sidecar `slo-parse-err.txt`)

**On-disk artifacts (always written, every branch):**
- `slo-services.json` — `["service-a", "service-b", ...]` or `[]` — **names are normalized** using the same function as `service_key`: lowercase, strip environment suffixes (`-prod`, `-staging`, `-pta`), replace separators (`_`, `.`) with `-`
- `slo-source-status.json` — `{"status": "ok|empty|unavailable", "reason": "...", "count": N}`

**Ruby extraction (stdlib only, no PyYAML):**
```ruby
cfg = YAML.safe_load(File.read(ARGV[0])) || {}
services = (cfg["services"] || []).map { |s| s["name"] }.compact
  .map { |n| n.downcase.gsub(/[_.]/, '-').gsub(/-(prod|staging|pta)$/, '') }
```

Parses only `services[].name` from expected YAML shape. Missing `name` fields are skipped (`.compact`), not hard failures. Names are normalized with the same rules as `service_key` to ensure exact-match works across both sides.

**Repo path convention:** Uses existing `{github_org}`, assumes repo name `monitoring` and path `tf/slo-config.yaml`. No extra Stage 0 prompt. If fetch fails, reason is logged and Stage 4 skips SLO cross-referencing.

**Stage 1 report line:** `"{M} services with SLO definitions"` when `ok`, `"SLO config: {reason}"` otherwise.

### Section 2a: Stage 4 — Routing Validation

Extends Stage 4 with two policy-level checks and one cluster-level check. All use data already in `$WORK_DIR`.

#### Zero-channel policies (policy-level)

Scan policies where `notification_channels` is empty AND `enabled` is true. These fire but notify nobody — invisible failures.

- `raw_incidents > 10` → promote to **Investigate** with action: "add notification channel or disable"
- Low/zero-incident → surface in **Systemic Issues > Dead/Orphaned Config** (section exists, gains zero-channel specificity)

#### Unlabeled high-noise policies (policy-level)

Existing `unlabeled_ranking` table stays in Systemic Issues unchanged. Additionally:

- Top entries with `raw_incidents > 10` → promote to **Investigate** with generic ownership language: *"No squad/team/owner label — ownership is implicit and unauditable. {N} incidents in {days}d have no traceable owner."*
- No org-specific routing fallback language (e.g., no "Unknown Alerts channel" reference). The skill is generic.
- Suggested owner: left as "⚠ assign" (unchanged from current behavior). The skill does not attempt to infer squad ownership from service names — that mapping is org-specific and outside the skill's scope.

#### Label inconsistency (cluster-level, stays cluster-level)

`compute-clusters.py` already computes `label_inconsistency`. When true AND `raw_incidents > 5`:

- Promote to **Investigate** as a cluster-level finding
- Does NOT merge into the policy-level unlabeled table — entity types stay separate

### Section 2b: Stage 4 — SLO Coverage Cross-Reference

Only runs when `slo-source-status.json` has `status: "ok"`. Requires new fields from `compute-clusters.py`.

#### New script fields in `compute-clusters.py`

**`service_key`** — deterministic service identity:
- Parsed from `condition_query` / `condition_filter` (not incident payload — incident data only has raw `resourceLabels` and `metricType`)
- Priority chain: `container_name` → `container` → `application` label → `service` label → `null` (both `container_name` and `container` are checked — PromQL conditions commonly use the short form `container="diet-suggestions"`)
- No `project_id` fallback — one project hosts many services, would collapse unrelated alerts
- `null` means "not extractable" — excluded from SLO cross-reference
- **Normalization:** lowercase, strip environment suffixes (`-prod`, `-staging`, `-pta`), replace separators (`_`, `.`) with `-`. Only exact-match after normalization. Unmatched keys stay unmatched.

**`signal_family`** — alert signal classification:
- Four values: `error_rate` | `latency` | `availability` | `other`
- Derived from `condition_query` + `condition_filter` + `metric_type`, in priority:
  1. Query/filter contains status match (`5xx`, `error`, `status>=500`) → `error_rate`
  2. Query/filter contains percentile aggregation or metric matches `*latency*` / `*duration*` / `*response_time*` → `latency`
  3. Metric type matches `*uptime*` / `*probe*` / `*health*` → `availability`
  4. Everything else → `other`
- Classification is a deterministic function in the script, not prompt-time reasoning

#### Stage 4 cross-reference logic

- Group clusters by `service_key` (skip `null`)
- **SLO migration candidate:** service_key with `total_raw_incidents > 20` across clusters with `signal_family IN (error_rate, latency, availability)` AND NOT in `slo-services.json` → Coverage Gaps: *"SLO review candidate — {N} noisy user-facing threshold alerts, no SLO definition"*
- **SLO review candidate:** service_key IS in `slo-services.json` AND has noisy user-facing threshold alerts → Needs Decision: *"Service has an SLO definition and also {N} noisy user-facing threshold alerts; review for redundancy or intentional overlap"*
- `other` signal family excluded from SLO cross-reference entirely
- No claim about same-signal overlap — `slo-services.json` doesn't carry signal coverage metadata

### Section 3: Stage 5 — IaC Location Resolution via GitHub Search

During Do Now gate evaluation, runs `gh search code` to upgrade IaC Location tier for candidates that would otherwise be Search Required or Unknown.

**When it runs:** Only for items that pass all other Do Now gate requirements (config diff, owner, outcome DoD, evidence basis, rollback signal). No point searching if the item fails on other grounds.

**Preconditions:** `github_org` provided AND `gh` available AND authenticated (same check as Section 1: `gh auth status`). Otherwise skip entirely — report identical to today's. This prevents avoidable fallback churn on private repos where `gh` exists but lacks auth.

**Search strategy:**
1. Primary token: policy ID (most unique identifier)
2. Secondary token (if primary returns 0): the identifying fragment already captured in Stage 3 — PromQL fragment, condition filter string, label key — per existing Search Required spec in SKILL.md
3. No display_name search (too generic, noisy)

**Result interpretation:**
- 1+ plausible results → IaC Location = **Likely**, include top `repo:path` match. *"Search match — verify before applying."*
- 0 results after both tokens → IaC Location **preserves original tier** (Search Required stays Search Required, Unknown stays Unknown). A failed search does not upgrade Unknown to Search Required — that would incorrectly make a Do-Now-ineligible item eligible.
- **Confirmed is not achievable from search alone.** Would require opening the file and verifying match context — out of scope for this iteration.

**Rate limit handling:** `gh search code` allows 10 requests/minute. Prioritize by raw incident count descending. Cap at top 10 candidates per analysis. Remaining items keep their existing IaC Location tier.

**Fallback:** If GitHub search adds nothing, the report is identical to today's output. Pure enrichment.

## Files Changed

| File | Change |
|------|--------|
| `skills/alert-hygiene/SKILL.md` | Stage 1 SLO enrichment, Stage 4 routing validation + SLO cross-reference, Stage 5 IaC search |
| `skills/alert-hygiene/scripts/compute-clusters.py` | Add `service_key` and `signal_family` fields to cluster output |
| `tests/` | Tests for new script fields, SLO enrichment flow, routing validation |

## Out of Scope

- **Confirmed IaC Location** from automated search (requires file content verification)
- **HCL diff generation** (couples skill to Terraform syntax, fragile)
- **SLO design or target recommendations** (skill boundary — identifies candidates only)
- **Multi-source alerting** (NewRelic no longer used, GCP-only is correct)
- **Org-specific routing language** (skill stays generic, no "Unknown Alerts" references)
- **Fuzzy service_key matching** (conservative exact-match only)
