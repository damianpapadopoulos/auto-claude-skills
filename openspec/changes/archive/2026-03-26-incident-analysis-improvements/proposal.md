## Why
The incident-analysis skill's CLASSIFY → INVESTIGATE handoff had a cascade stall risk: CLASSIFY could commit to a high-confidence wrong hypothesis (false clarity), causing 30-40 seconds of wrong-lane investigation before the contradiction test caught it. Additionally, the skill lacked a source code analysis capability and a dedicated entry-point command.

Identified via review of oviva-ag/claude-code-plugin PR #38 and a multi-agent design debate (architect, critic, pragmatist — 2 rounds).

## What Changes
Four improvement areas shipped on `feat/incident-analysis-improvements`:

1. **`/investigate` command + SLO signal** — Thin entry-point wrapper pre-populating MITIGATE scope inputs, plus `slo_burn_rate_alert` context signal with MITIGATE integration and routing triggers.

2. **Bounded disambiguation probes** — CLASSIFY shortlist artifact in medium/low-confidence output, Step 2b in INVESTIGATE for targeted probe execution, `disambiguation_probe` schema on 3 playbooks (dependency-failure, config-regression, infra-failure), one-round anti-looping with pre-probe fingerprint, scope exception for dependency probes.

3. **Eval infrastructure** — SLO burn rate routing trigger in production and fallback registries, fixture schema validator with real-incident-only authoring guidelines.

4. **Step 4b source analysis** — Conditional code analysis within INVESTIGATE (between trace correlation and hypothesis formation), bad-release gate only, post-hop workload identity resolution, structured output contract (`deployed_ref` + `resolved_commit_sha`), fail-open with explicit warning.

## Capabilities

### Modified Capabilities
- `incident-analysis`: Added disambiguation probes to CLASSIFY, Step 2b to INVESTIGATE, Step 4b source analysis, /investigate command, SLO signal, eval infrastructure

## Impact
- `skills/incident-analysis/SKILL.md` — +83 lines (CLASSIFY shortlist, Step 2b, Step 4b, anti-looping, scope exception)
- 3 playbook YAML files extended with `queries` + `disambiguation_probe`
- `signals.yaml` — 1 new signal
- `config/default-triggers.json` + `config/fallback-registry.json` — SLO routing trigger
- 5 test files extended (+329 lines of assertions)
- New files: `commands/investigate.md`, `references/source-analysis.md`, `tests/test-incident-analysis-output.sh`, `tests/fixtures/incident-analysis/README.md`
