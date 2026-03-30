# Design: Alert Hygiene Terraform, Routing & SLO Refinements

## Architecture
Three independent enrichment paths integrated into the existing alert-hygiene analysis pipeline:
- **Stage 1 enrichment:** GitHub API → base64 decode → Ruby YAML parse → normalized service list on disk
- **Stage 4 extensions:** Policy-level routing checks + cluster-level label checks + SLO cross-reference using deterministic script output
- **Stage 5 extension:** gh search code per Do-Now candidate → IaC Location tier upgrade

All paths are optional — core analysis (Stages 1-3, 5 report production) runs unchanged when GitHub is unavailable.

## Dependencies
- Ruby stdlib (yaml, json) — available on macOS, no new install
- `gh` CLI — already in environment for IaC search and SLO fetch
- No new Python dependencies (stdlib only)

## Decisions & Trade-offs
1. **Ruby over PyYAML for SLO parsing** — PyYAML is not in the repo's baseline. Ruby stdlib YAML is available on macOS and avoids a new dependency. A two-sided normalization contract test ensures Python and Ruby produce identical output.
2. **Likely, not Confirmed from GitHub search** — `gh search code` proves a token exists somewhere in indexed code, but doesn't verify the match context. Confirmed requires opening the file, which is out of scope.
3. **Conservative service_key matching** — Normalize → exact-match only. No fuzzy guessing. Unmatched keys are excluded rather than risk false SLO gap reports.
4. **Signal family reduced to 4 values** — error_rate, latency, availability, other. Saturation and custom collapsed into `other` because SLO cross-reference only applies to user-facing signal families.
5. **Entity consistency enforced** — Policy-level findings (zero-channel, unlabeled) and cluster-level findings (label inconsistency) are never mixed in the report.
