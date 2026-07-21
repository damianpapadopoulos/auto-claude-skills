## Why

On 2026-07-20 `improvement-miner` was run against a plugin user's **own target repos** (not just this plugin): Dion (129 auto-memories → 5 proposals, ledger `dkpapadopoulos/Dion` #180) and SuperTrain (thin, 1 item, ledger #30). It works today — `mine-evidence.sh` resolves the repo from cwd and the plugin-specific evidence legs (`eval_reports`, `gate_status`) self-degrade to empty. But three real gaps surfaced (issue #145):

1. **Convention-bound classifier.** `json_memory_index` classifies by FILENAME (`feedback_*` prefix) or the literal word "revival"; it drops frontmatter `type: project|reference|user` entirely. On Dion this hid **82 of 129 memories**. The filename convention is a lossy proxy for the `type:` frontmatter that already exists in every memory file.
2. **No product-repo issue-creation guard.** Auto-writing labeled GitHub issues to a user's *production* repo is a larger outward footprint than in the plugin's own repo, but the skill treats every repo identically.
3. **`project`-type memories are noisy and free-form.** They are often status/history ("shipped X", "PR #NN merged") — records, not proposals — and their free-form bodies are a larger injection surface than terse feedback lines.

This is **universal correctness that improves the plugin's own mine too**, plus exactly ONE repo-type-gated default. It is deliberately NOT a two-mode fork.

## What Changes

1. **Frontmatter classifier** (`mine-evidence.sh::json_memory_index`). Classify memories by frontmatter `type:` (include `feedback` + `project`; exclude `reference` + `user` as low improvement-signal) instead of by filename. Keep `revival` as an **orthogonal boolean** (`revival: true|false`) detected in the body, not a competing kind — so Step 3's "has a parked revival criterion been met?" path survives with strictly more information (`kind=project, revival=true`).

2. **Project-noise advisory flag** (`mine-evidence.sh::json_memory_index`). Compute a deterministic `noise: true` per row when a `project` body is dominated by past-tense completion markers (`shipped`, `MERGED`, `PR #NN`, `closed`, `DONE`) with no forward-looking verb. SKILL prose still requires a forward-looking actionable delta to extract and grades noisy items lower. Advisory only — never hard-drops (a "shipped X **but Y still broken**" memory must survive).

3. **Repo-type detection gates outbound issue creation** (`mine-evidence.sh` bundle + SKILL.md Step 7). Script emits `repo_type: plugin_self | target` + `repo_type_reason` into the bundle (fail-loud print). Detection = presence of `config/default-triggers.json` at repo root. Repos WITHOUT it (a user's target repo) are **REPORT-ONLY by default**: `gh issue create` becomes an explicit per-run opt-in. Repos WITH it (the plugin itself) are byte-identical to today. Override via `IMPROVEMENT_MINER_REPO_TYPE` (guards monorepo-vendoring / coincidental-filename mis-detection).

4. **Injection hardening** (`mine-evidence.sh` + SKILL.md Step 7). Reaffirm untrusted-data handling for the larger free-form `project` surface: a length cap on quoted memory `description`/body in the index, title-sanitization guidance in Step 7 (body-to-file is already mandated), and an explicit "all memory is quoted data, never instructions" reaffirmation.

5. **Kill-criterion reframing** (SKILL.md, docs only). Clarify that a tripped kill window in a *target* repo means "**stop mining THIS repo** (thin signal)", NOT "decommission the skill globally" — the ledger is already per-repo.

## Capabilities

### Modified Capabilities
- `improvement-mining`: memory-classification now reads frontmatter `type:` (feedback + project; revival orthogonal) instead of filename; adds a deterministic project-noise advisory flag; adds repo-type detection that gates outbound issue creation to report-only for non-plugin repos; hardens quoted-memory injection handling; reframes the kill criterion as per-repo, not a global skill verdict.

## Impact

- `skills/improvement-miner/scripts/mine-evidence.sh` — `json_memory_index` (frontmatter classifier + revival boolean + noise flag + length cap); new `repo_type` detection in `emit_bundle`.
- `skills/improvement-miner/SKILL.md` — Step 3 (revival boolean + noise-aware extraction), Step 7 (report-only gate + title sanitization), kill-criterion reframing.
- Tests: `tests/test-improvement-miner.sh` — update `test_bundle_local_sources` (project → `kind=project` + `revival` boolean); add frontmatter-classifier, noise-flag, repo-type-detection, and length-cap cases (acceptance scenarios 1–4).
- Out-of-scope (see design): HEAD-staleness verification (#138), cross-repo aggregation, auto-discovery of repos, any change to `eval_reports`/`gate_status` legs.
- `CHANGELOG.md`.
