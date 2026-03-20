# Incident Analysis v1.2: Postmortem Permalinks

**Date:** 2026-03-20
**Status:** Draft
**Phase:** DESIGN
**Parent:** `docs/superpowers/specs/2026-03-19-incident-analysis-design.md` (v1.0)

## Problem Statement

The v1.0/v1.1 incident-analysis skill generates postmortem documents with raw text references (trace IDs as plain strings, commit hashes as text). These are not clickable, forcing the reader to manually copy-paste into Cloud Console or GitHub. The Palladius postmortem-generator pattern explicitly mandates "USE PERMALINKS" for all external references.

## Scope

Add two permalink formatting rules to Stage 3, Step 3 (Generate Postmortem) in the incident-analysis SKILL.md. Both use data already available from Stage 2 — zero extra tool calls. No routing, hook, phase doc, or test changes needed.

**Not in scope:**
- Log entry permalinks — Cloud Console Logs Explorer URLs require query parameters that are not stable across sessions. Deferred until a stable URL pattern is confirmed.
- Non-GitHub git providers (GitLab, Bitbucket, self-hosted) — fallback to raw hash, no link.
- Action item taxonomy (Mitigate/Detect/Prevent) — separate feature, not part of v1.2.

## Design

### Trace Permalinks

Whenever the postmortem references a trace ID (in timeline, root cause, or summary sections), format as a clickable Markdown link:

```
[Trace TRACE_ID](https://console.cloud.google.com/traces/list?project=PROJECT_ID&tid=TRACE_ID)
```

- `PROJECT_ID`: The GCP project used during Stage 2 investigation. If Stage 2 Step 4 (trace correlation) queried a cross-project Service B, use the relevant project for each trace reference.
- `TRACE_ID`: The raw trace identifier (already extracted in Stage 2).
- This URL pattern is the standard Cloud Console deep-link documented by Google, based on OpenTelemetry trace exporters.

### Commit Permalinks

If the postmortem references a specific git commit (e.g., a deployment that triggered the incident), format as a clickable Markdown link:

```
[Commit SHORT_HASH](https://github.com/ORG/REPO/commit/FULL_HASH)
```

**Derive `ORG/REPO` at runtime:**
```bash
git remote get-url origin | sed 's|.*github.com[:/]||; s|\.git$||'
```

**Fallback:** If the remote URL is not GitHub-hosted (does not contain `github.com`), or if `git remote get-url origin` fails (no remote, no git repo), print the raw commit hash without a link. Do not guess URL patterns for other providers.

### Placement in SKILL.md

Embed the permalink rules directly into Stage 3, Step 3 (Generate Postmortem) as formatting instructions after the existing content bullet list. This avoids renumbering steps.

Add after `skills/incident-analysis/SKILL.md:207` (after the "Action items" bullet):

```markdown
**Permalink formatting (apply to all references in the generated postmortem):**
- **Trace IDs:** Format as `[Trace TRACE_ID](https://console.cloud.google.com/traces/list?project=PROJECT_ID&tid=TRACE_ID)` using the project_id and trace_id from Stage 2. If cross-project trace correlation was used, use the relevant project for each reference.
- **Git commits:** If a commit hash is referenced (e.g., a deployment trigger), derive the repo URL via `git remote get-url origin`. If GitHub-hosted, format as `[Commit SHORT_HASH](https://github.com/ORG/REPO/commit/FULL_HASH)`. If not GitHub, use the raw hash without a link.
```

### Example Output

With these rules, a generated postmortem timeline would look like:

```markdown
| Time (UTC) | Component | Event | Evidence |
|------------|-----------|-------|----------|
| 10:00:15 | checkout-service | Deployment initiated | [Commit a1b2c3d](https://github.com/acme/checkout/commit/a1b2c3d4e5f6) |
| 10:02:11 | payment-gateway | 504 Deadline Exceeded | [Trace 9f8e7d](https://console.cloud.google.com/traces/list?project=acme-prod&tid=9f8e7d) |
```

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `skills/incident-analysis/SKILL.md:207` | **Modify** | Insert permalink formatting rules after the "Action items" bullet in Stage 3, Step 3 (existing lines 200-206 unchanged) |
| `docs/superpowers/specs/2026-03-19-incident-analysis-design.md` | **Modify** | Insert v1.2 entry in evolution path: `v1.2  Postmortem permalinks: trace IDs + commit hashes as clickable Markdown links [SHIPPED]` and update "What's NOT in v1" if applicable |

## Test Plan

Behavioral verification scenarios (structured document review, same model as v1.1):

| Scenario | Expected Behavior |
|----------|-------------------|
| Trace ID referenced in timeline | Formatted as clickable Cloud Console link with correct project_id |
| Cross-project trace (Service B in different project) | Uses Service B's project_id in the link, not Service A's |
| Git commit referenced as deployment trigger | Agent runs `git remote get-url origin`, formats as GitHub link |
| Non-GitHub remote (e.g., GitLab) | Raw commit hash printed without link |
| No trace IDs in postmortem (Tier 2/3 investigation) | No trace links generated (nothing to link) |
| No commit references in postmortem | No commit links generated |
| Cross-project trace with both services in postmortem | Service A trace references use Service A's project_id; Service B trace references use Service B's project_id |
| `git remote get-url origin` fails (no remote/no repo) | Raw commit hash printed without link |

## Assumptions

- `https://console.cloud.google.com/traces/list?project=PROJECT_ID&tid=TRACE_ID` is the stable Cloud Console trace permalink pattern
- `git remote get-url origin` is available in the working directory
- GitHub is the default provider; all others fall back to raw hash
- The agent already has project_id and trace_id from Stage 2 — no additional tool calls needed

## Decision

Small, high-polish enhancement. Inspired by Palladius postmortem-generator "USE PERMALINKS" pattern. Trace + commit permalinks only; log entry permalinks deferred until stable URL pattern is confirmed.
