# Design: Claude PR Review Workflow

## Architecture

Three GitHub Actions workflows share a uniform security architecture, modeled on the existing well-hardened `skill-eval.yml`:

```
PR opened/synced ──► claude-code-review.yml (always-on review)
                           │
                           ├─ Job 1: detect-changes
                           │   ├─ git -c core.quotePath=false diff --name-only
                           │   ├─ Extract changed_skill_paths
                           │   ├─ Extract changed_hook_paths
                           │   ├─ Extract changed_workflow_paths
                           │   ├─ Compute touched_high_risk flag
                           │   └─ Compute touched_workflows flag
                           │
                           └─ Job 2: review
                               ├─ Refuse fork-PR (head.repo != base.repo)
                               ├─ Checkout @ pull_request.head.sha
                               ├─ Run claude-code-action @ peeled commit SHA
                               │     • --allowed-tools allowlist
                               │     • --json-schema for structured output
                               │     • plugin-dev + skill-creator loaded
                               ├─ Reap prior PR Review comments (success-gated)
                               └─ Post fresh review comment

Comment on PR / issue with @claude ──► claude.yml (assistant)
                                            │
                                            ├─ if: author_association ∈ allow-list
                                            ├─ Step 1: authoritative permission gate
                                            │     • admin / write / maintain only
                                            │     • fork-PR refusal for PR triggers
                                            └─ Run claude-code-action @ peeled commit SHA

Comment "@claude run eval" / label run-eval ──► skill-eval.yml (advisory eval)
                                                    │
                                                    └─ (existing hardened pipeline,
                                                       SHA pin bumped only)
```

The two new workflows mirror `skill-eval.yml`'s security primitives:

1. **`pull_request`, never `pull_request_target`** — fork PRs run without secrets, so an exfil attempt fails at the action step.
2. **Pinned peeled commit SHA** — not the floating `@v1` tag, not the tag-object SHA. The `git/refs/tags/v1` lookup returns the annotated tag object, which is then peeled via `git/tags/<obj>` to the actual commit.
3. **Fork-PR refusal step** — defense-in-depth check before any step that touches secrets, comparing `pull_request.head.repo.full_name` against `github.repository`.
4. **Permission API gate** (claude.yml only) — `gh api /repos/.../collaborators/<actor>/permission` requires `admin|write|maintain`. `author_association` alone is insufficient because triage-role users may surface as COLLABORATOR.
5. **All user-controlled inputs through `env:` blocks** — never direct `${{ github.event.* }}` substitution into `run:` shell.
6. **Concurrency cancel-in-progress** — avoids stale-comment races on force-push.
7. **Comment lifecycle gated on success** — failed/injected runs cannot silently wipe prior legitimate review comments.
8. **Action-layer tool allowlist** (`claude-code-review.yml` only) — `--allowed-tools 'Read Grep Glob Bash(wc:*) Bash(git diff:*) Bash(git log:*) Bash(git status:*) Bash(git rev-parse:*)'`. Allowlist beats denylist because new Bash entrypoints (`bash`, `sh`, `perl`, `bun`, `npx`, `env`) cannot be omitted by oversight.

## Dependencies

- `anthropics/claude-code-action@567fe954a4527e81f132d87d1bdbcc94f7737434` (peeled commit of v1).
- GitHub-published actions (`actions/checkout@v4`) on major-version tags — intentionally not SHA-pinned per the threat model (no secret access).
- `CLAUDE_CODE_OAUTH_TOKEN` repo secret — already present, used by `skill-eval.yml`.
- `anthropics/claude-plugins-official` marketplace (`plugin-dev`, `skill-creator`) loaded into the review action's runtime for plugin-domain knowledge.

## Decisions & Trade-offs

| Decision | Rationale |
|---|---|
| **Allowlist over denylist** for tool restrictions | Denylist is leaky — `Bash(gh:*) Bash(curl:*)` left `Bash(bash:*) Bash(sh:*) Bash(perl:*) Bash(bun:*) Bash(npx:*) Bash(env:*)` unrestricted. Allowlist enumerates exactly what's needed; everything else fails at the action layer. |
| **Peeled commit SHA, not tag-object SHA** | `git/refs/tags/v1` returns the annotated tag object; using it as `uses: action@<obj>` works in some GitHub contexts but is not the recommended pin. The peeled commit (`git/tags/<obj>` → `.object.sha`) is the actual code GitHub will execute. |
| **GitHub-published actions exempt from SHA-pinning rule** | `actions/checkout@v4` doesn't receive Claude/OAuth secrets and is published by GitHub directly. SHA-pinning it adds maintenance burden without reducing the threat model. The review prompt's checklist explicitly carves this out so it doesn't condemn its own workflow. |
| **Backstop, not replacement** | The composition chain's in-session `requesting-code-review` retains full session context (plan reference, prior decisions, working tree). The CI workflow only sees the diff. They catch different issues. The CI workflow is explicitly framed as "advisory backstop, not primary SDLC gate" so a future PR cannot mark this check as Required and use it to skip in-session review. |
| **Fork PRs blocked, not allowlisted** | Fork-PR review without secrets is possible via `pull_request_target` patterns, but those patterns are dangerous (well-documented "pwn" route). Trade-off: external contributors get no automated review until a maintainer pulls the branch into the base repo. Acceptable for solo / small-team operation; documented as a known limitation. |
| **Lockstep enforcement is documentation, not tooling** | The `claude-code-action` SHA must be identical across three workflows. Currently enforced by comments. A drift-detection job would close the gap; parked as follow-up to keep this PR's scope small. |
| **Extending `auto-claude-skills` capability vs new capability** | This is plugin-level safety infrastructure (CI-time enforcement of plugin conventions). `auto-claude-skills` already covers preflight scripts, REVIEW-Before-SHIP guard, and other plugin-level safety. Extending avoids capability proliferation. |

## Rejected Alternatives

1. **Replace in-session `requesting-code-review` with the CI workflow.** Rejected: the in-session reviewer has full conversation context and plan reference; the CI workflow only has the diff. They are complementary fidelities. Confirmed by user feedback: "Do not use the GitHub Action to replace the in-session requesting-code-review SDLC step."
2. **Add deterministic bash-lint workflow now.** Rejected for this PR's scope: mechanical checks (frontmatter present, kebab-case, `disable-model-invocation`) are best done deterministically; semantic checks (description quality, scope duplication) need an LLM. Bash lint belongs in a follow-up PR with its own threat model and shipping cadence.
3. **Skip `claude.yml` (`@claude` assistant) entirely.** Considered: solo dev rarely uses `@claude` mentions, and the surface is high-risk. Rejected because the user wanted hardening rather than removal — the workflow now requires `admin|write|maintain` and refuses fork-PRs, materially reducing the risk surface vs the prior unhardened stub.
4. **Use floating `@v1` for `claude-code-action`.** Rejected: floating tags can silently move; pinning is GitHub's recommended hardening for actions that receive secrets.
