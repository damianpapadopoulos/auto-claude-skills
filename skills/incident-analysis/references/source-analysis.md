# Step 4b: Source Analysis — Reference Procedure

Conditional step within INVESTIGATE. Analyzes source code at the deployed version to
identify regression candidates when actionable stack traces are available.

## Entry Conditions

All three required:
1. **Actionable stack frame** — at least one stack trace frame from Step 2 points to
   application source code. Skip minified, compiled, generated, or framework-internal frames.
2. **Resolvable deployed ref** — deployment metadata from Step 2b provides an image tag or
   SHA that maps to a Git ref. If the image tag is a semver tag (e.g., `v2.3.1`), use it
   directly. If it is a commit SHA prefix, resolve via `gh api`.
3. **Bad-release gate** — one of:
   - `recent_deploy_detected` signal is detected
   - Deploy timestamp falls within the incident window
   - Deploy timestamp falls within 4 hours before incident start

Config-regression, dependency-failure, and infra-failure categories do **not** trigger
Step 4b. This step is stack-frame/file-centric; config incidents rarely benefit from
code-at-line analysis.

If any condition is not met, set `source_analysis.status: skipped` with `skip_reason` and
proceed to Step 5.

## Post-Hop Workload Identity Resolution

If Step 4 (trace correlation) shifted investigation to Service B, the deployment metadata
from Step 2b belongs to Service A. Before proceeding:

1. Resolve Service B's workload identity from trace/log resource labels (e.g.,
   `resource.labels.container_name`, `resource.labels.namespace_name`, `resource.type`)
2. Find the owning workload (Deployment, StatefulSet, DaemonSet, Job) via label selector
   or resource labels — do not assume the workload name matches the service name
3. Extract image tag from the workload spec: one bounded deployment-metadata lookup
4. If workload identity is ambiguous (multiple candidates, no clear owner), set
   `source_analysis.status: skipped`, `skip_reason: "workload identity ambiguous for
   Service B"`, and proceed to Step 5

## Procedure

### 1. Resolve Deployed Ref

Extract the Git reference from deployment evidence:
- Image tag `v2.3.1` → `deployed_ref: "v2.3.1"`
- Resolve to commit SHA via `gh api repos/{owner}/{repo}/git/ref/tags/{tag}` or
  `git rev-parse {tag}` → `resolved_commit_sha: "abc123..."`
- If the image uses a commit SHA directly, set both fields to the same value
- If resolution fails, set `source_analysis.status: unavailable`,
  `skip_reason: "cannot resolve deployed ref to commit SHA"`, and proceed to Step 5

### 2. Map Stack Frames to Source Files

For the top 1-2 actionable stack frames only:
- Java: `com.example.user.UserController` → `src/main/java/com/example/user/UserController.java`
- Python: `app/services/checkout.py` → direct path
- Go: `github.com/org/repo/pkg/handler.go` → `pkg/handler.go`
- Kotlin/Scala: follow Java convention with `.kt`/`.scala` extension

Verify the file exists at the deployed ref:
```bash
gh api repos/{owner}/{repo}/contents/{path}?ref={resolved_commit_sha}
```

If the file is not found at the expected path, try search as fallback:
```bash
gh api search/code -f q="class ClassName repo:{owner}/{repo}"
```

If search also fails, record `status: not_found` for that file and continue with remaining
files. Do not attempt broad repo scanning.

**Monorepo path filter:** If the service-to-repo-root mapping is known (e.g., from build
config or deployment spec), restrict file resolution to that subtree.

### 3. Read Code at Error Location

For each mapped file (max 2), read the error line +/- 15 lines of context at the deployed
ref. Use `gh api` or `git show {ref}:{path}`.

**Bounded evidence:** Extract only the relevant hunk. Never dump full files or full diffs
into the investigation context.

**Tier fallback:**
- **Tier 1:** `gh api repos/{owner}/{repo}/contents/{path}?ref={sha}` (GitHub API)
- **Tier 2:** `git show {ref}:{path}` (local checkout)
- **Tier 3:** Provide GitHub URL for user to inspect manually:
  `https://github.com/{owner}/{repo}/blob/{ref}/{path}#L{line}`

### 4. Check Recent Commits

For each affected file, fetch the last 3 commits within 48 hours of incident start:
```bash
gh api "repos/{owner}/{repo}/commits?path={path}&per_page=3&sha={ref}&since={48h_before_incident}"
```

Identify regression candidates: commits that modified the error location or its immediate
callers. Check for removed safety checks, changed error handling, new code paths, or
dependency version bumps in manifest files (not lockfiles or generated metadata).

### 5. Emit Structured Output

```yaml
source_analysis:
  status: reviewed_no_regression | candidate_found | skipped | unavailable
  skip_reason: "..."  # when status is skipped or unavailable
  deployed_ref: "v2.3.1"
  resolved_commit_sha: "abc123def456..."
  source_files:
    - path: "src/main/java/com/example/user/UserController.java"
      line: 142
      code_context: "return user.toDto();  // NPE if null"
      status: analyzed | not_found | access_denied
  regression_candidates:
    - commit_sha: "def789..."
      date: "2026-03-24T10:30:00Z"
      summary: "refactor: removed null check in getUser()"
      files: ["UserController.java"]
```

When no regression is found, emit:
```yaml
source_analysis:
  status: reviewed_no_regression
  deployed_ref: "v2.3.1"
  resolved_commit_sha: "abc123..."
  source_files:
    - path: "src/main/java/com/example/user/UserController.java"
      line: 142
      code_context: "return user.toDto();"
      status: analyzed
  regression_candidates: []
```

This structured output feeds directly into Step 5 (hypothesis formation). If
`status: candidate_found`, the regression candidate becomes primary hypothesis input.

## Failure Handling

**Fail-open with explicit warning.** If any GitHub API call fails (timeout, 404, rate
limit, authentication error):

> "Step 4b: GitHub API unavailable ({error}), source analysis skipped. Investigation
> continues without source code context."

Set `source_analysis.status: unavailable` with `skip_reason` containing the error.
The user must know a data source was unavailable. Never silently degrade.

## Constraints

- **Read-only.** Never suggest code changes or create PRs from this step.
- **Bounded scope.** 1-2 top actionable stack frames, 1-2 files, last 3 commits within 48h.
- **One repo per service.** Do not follow cross-repo dependencies.
- **Deployed ref, not HEAD.** Always read code at the version that is running, not the
  latest commit on the default branch.
- **Same-service scope restriction.** Follows the INVESTIGATE scope constraint — only
  analyze the currently scoped service (which may be Service B after a trace hop).
