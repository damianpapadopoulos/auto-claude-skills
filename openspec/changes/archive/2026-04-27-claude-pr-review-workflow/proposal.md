## Why

The composition chain enforces `requesting-code-review` in-session, but PRs created outside an active session (push from another machine, scheduled agents, future contributors) bypass that gate entirely. Convention-level issues — bad descriptions, missing `disable-model-invocation`, scope duplication, hook fail-open regressions — silently misroute every future session that should have triggered the affected skill. A CI-layer review backstop is needed to catch these on every PR, not just sessions where the dev remembered to dispatch the reviewer.

The existing `claude-code-review.yml` was a generic stub from the action template; `claude.yml` was an unhardened `@claude` assistant trigger with broad write permissions and no actor gating; `skill-eval.yml` was already well-hardened. The threat model: PR diffs may be adversarial, secrets must not leak, fork PRs must hit the no-secrets baseline.

## What Changes

Hardened all three Claude Code Action workflows to a uniform security posture matching the existing `skill-eval.yml`:

- **`claude-code-review.yml`** — replaced the generic stub with an auto-claude-skills-tuned PR review. Path filter (`skills/**`, `commands/**`, `hooks/**`, `config/**`, `scripts/**`, `.claude-plugin/**`, `.github/workflows/**`, `CLAUDE.md`, `AGENTS.md`, `docs/eval-pack-schema.md`). Two-job structure: `detect-changes` extracts changed skill / hook / workflow paths and a `touched_high_risk` flag; `review` runs the action with peeled commit-SHA pin (`567fe954…`), action-layer `--allowed-tools` allowlist (`Read Grep Glob` + read-only Bash), structured JSON output, fork-PR refusal, and a comment lifecycle that deletes the previous review before posting the new one (gated on review success). Prompt encodes CLAUDE.md conventions: bash 3.2 compat, fail-open routing hooks, jq-optional, US/SOH delimiters, the 11,500-word `incident-analysis` ceiling, `disable-model-invocation` rule, scope duplication, grep-`-F` literal-vs-regex traps, and a GHA security checklist.
- **`claude.yml`** — replaced the unhardened `@claude` stub. Same security architecture as `skill-eval.yml`: `author_association` allow-list pre-filter, authoritative permission API gate (`admin|write|maintain`), fork-PR refusal step covering all four event types, peeled commit-SHA pin, env-quoted user inputs, concurrency cancel-in-progress. Dropped `id-token: write` (unused with `claude_code_oauth_token`).
- **`skill-eval.yml`** — bumped `claude-code-action` SHA pin to `567fe954…` to keep all three workflows in lockstep.

## Capabilities

### Modified Capabilities
- `auto-claude-skills`: Added CI-time PR review enforcement and `@claude` assistant hardening as new requirements within the plugin-level safety infrastructure capability. The in-session `requesting-code-review` step remains the primary REVIEW gate; this is a backstop for PRs that bypass it.

## Impact

- **Affected files:** `.github/workflows/claude-code-review.yml`, `.github/workflows/claude.yml`, `.github/workflows/skill-eval.yml`.
- **Affected systems:** GitHub Actions; secrets surface (`CLAUDE_CODE_OAUTH_TOKEN`, `GITHUB_TOKEN`); PR comment timeline.
- **Behavior change:** every PR touching plugin code now receives an automated review comment. Fork PRs receive a fork-PR-refusal notice and no review. `@claude` mentions now require admin/write/maintain permission.
- **No code changes** to skills, hooks, commands, or routing logic. Composition chain unchanged. In-session SDLC review remains mandatory.
