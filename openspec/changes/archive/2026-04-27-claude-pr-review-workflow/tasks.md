# Tasks: Claude PR Review Workflow

## Completed

- [x] 1.1 Replace generic stub `.github/workflows/claude-code-review.yml` with hardened, plugin-tuned PR review workflow
- [x] 1.2 Add change-detection job extracting changed skill / hook / workflow paths and high-risk surface flag
- [x] 1.3 Add fork-PR refusal step in review job
- [x] 1.4 Pin `anthropics/claude-code-action` to peeled commit SHA `567fe954a4527e81f132d87d1bdbcc94f7737434`
- [x] 1.5 Add action-layer `--allowed-tools` allowlist (`Read Grep Glob` + read-only Bash patterns)
- [x] 1.6 Encode CLAUDE.md conventions in review prompt (frontmatter, fail-open hooks, jq-optional, US/SOH delimiters, 11,500-word ceiling, grep-`-F` gotchas)
- [x] 1.7 Add GitHub Actions security checklist to review prompt (peeled-SHA pinning carveout for `actions/` and `github/` orgs, lockstep, env-block pattern, fork-PR refusal, permission API gate, allowlist over denylist, concurrency)
- [x] 1.8 Add comment lifecycle (delete-prior, post-fresh, success-gated)
- [x] 1.9 Apply `core.quotePath=false` to change-detection git diff for path-with-whitespace robustness
- [x] 2.1 Replace generic stub `.github/workflows/claude.yml` with hardened `@claude` assistant
- [x] 2.2 Add `author_association` allow-list pre-filter
- [x] 2.3 Add permission API gate (`admin|write|maintain`)
- [x] 2.4 Add fork-PR refusal step covering all four event types
- [x] 2.5 Pin `claude-code-action` SHA to match (`567fe954…`)
- [x] 2.6 Drop unused `id-token: write` permission
- [x] 2.7 Funnel user-controlled inputs through `env:` blocks
- [x] 2.8 Add concurrency cancel-in-progress
- [x] 3.1 Bump `claude-code-action` SHA pin in `.github/workflows/skill-eval.yml` to keep all three workflows in lockstep
- [x] 4.1 Verify YAML parses on all three workflows (`yaml.safe_load`)
- [x] 4.2 Verify SHA alignment across all three workflows (`grep` confirms single SHA)
- [x] 4.3 Run `bash tests/run-tests.sh` (37 files passed, 0 failed)
- [x] 5.1 Iterate via human review (3 rounds): paths gap, OIDC, prompt/wc conflict; tag-object vs peeled SHA, prompt-only restrictions, missing GHA checklist; denylist leakiness, `actions/checkout@v4` self-condemnation
- [x] 5.2 Dispatch `superpowers:code-reviewer` subagent — 0 critical, 0 blocking, 2 important addressed (author_association comment, denylist remnant in prompt), cheap minors addressed (`core.quotePath`, security-model carveout)

## Follow-ups (parked, out of scope for this change)

- [ ] Add SHA drift-detection workflow that fails if the three workflows diverge on the `claude-code-action` pin
- [ ] Add deterministic bash-lint workflow for mechanical conventions (frontmatter present, kebab-case, `disable-model-invocation`, incident word limit, bash 3.2 compat) as a separate blocking gate
- [ ] Decide if/when to mark the new review workflow as Required in branch protection (recommend non-required for 2-3 PRs first to assess signal quality)
