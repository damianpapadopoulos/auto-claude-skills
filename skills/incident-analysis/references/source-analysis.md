# Step 4b: Source Analysis — Reference Procedure

Conditional step within INVESTIGATE. Analyzes source code at the deployed version
when actionable stack traces are available and a bad-release or repo-backed
config-change scenario is plausible.

## Gate Conditions

All must be true (bad-release path):
1. **Bad-release gate:** `recent_deploy_detected` signal is detected, OR deploy timestamp
   falls within the incident window or within 4 hours before incident start.
2. **Actionable stack frame:** At least one stack frame from Step 2 resolves to a source file
   (not minified, compiled, or generated code). Skip frames from third-party libraries.
3. **Resolvable deployed ref:** Deployment metadata provides an image tag or SHA that can be
   mapped to a git ref.

OR all must be true (config-change path):
1. **Config-change gate:** `config_change_correlated_with_errors` signal is detected AND
   the config change is repo-backed (has a git ref — e.g., Helm chart in a config repo,
   application.yaml in the service repo). ConfigMap-only or console-applied changes without
   a git ref do NOT trigger this path.
2. **Actionable stack frame:** Same as above.
3. **Resolvable deployed ref:** Same as above.

When triggered via the config-change path, the procedure is identical but Step 4 (Check
Recent Commits) prioritizes config files (*.yaml, *.properties, *.json, *.toml, *.env)
alongside source files in the commit search.

**User override:** If the user explicitly requests source analysis (e.g., "check the changes
in the service code"), bypass the category gate (condition 1 in either path) but NOT the
other bounds. Conditions 2-3 remain enforced. The procedure, scope constraints, token budget,
and bounded-evidence rules are unchanged.

If no gate is met and no user override, skip with structured output:
```yaml
source_analysis:
  status: skipped
  skip_reason: "no actionable stack frame" | "deployed ref unresolvable" | "not bad-release or config-change category"
```

## Post-Hop Workload Resolution

If Step 4 (trace correlation) shifted the investigation to a different service (Service B),
resolve Service B's workload identity from trace/log resource labels before proceeding:

1. Extract workload identity from span resource labels (e.g., `k8s_container` resource type
   with `container_name`, `namespace_name`, `pod_name`)
2. Resolve the owning workload (Deployment, StatefulSet, DaemonSet, etc.) via one bounded
   deployment-metadata lookup for that workload identity
3. Extract the image tag from the resolved workload spec

If workload identity is ambiguous after one lookup attempt, skip with reason:
```yaml
source_analysis:
  status: unavailable
  skip_reason: "Service B workload identity ambiguous after trace hop"
```

## Procedure

### Step 1: Resolve Deployed Ref

Extract the git reference from deployment evidence:
- Image tag (e.g., `v2.3.1`) → use as `deployed_ref`
- Resolve to commit SHA via `gh api repos/{owner}/{repo}/git/ref/tags/{tag}` → `resolved_commit_sha`
- If the tag is not a semver tag, attempt direct SHA resolution
- If unresolvable, skip with `status: unavailable`

### Step 2: Map Stack Frames to Source Files

For each actionable stack frame (max 1-2 top frames):
- Java: `com.oviva.user.UserController` → `src/main/java/com/oviva/user/UserController.java`
- Python: `app/services/checkout.py` → direct path
- Go: `github.com/org/repo/pkg/handler.go` → `pkg/handler.go`

Verify file exists at deployed ref:
```bash
gh api repos/{owner}/{repo}/contents/{path}?ref={resolved_commit_sha}
```

If not found, try search as fallback:
```bash
gh api search/code -f q="class ClassName repo:org/repo"
```

### Step 3: Read Code at Error Location

For each mapped file (max 1-2), read the relevant hunk at the deployed ref (not HEAD):
- Error line +/- 20 lines of context
- Never dump full files or full diffs — bounded evidence only

Tool tiers:
- **Tier 1:** `gh api` or GitHub MCP tools
- **Tier 2:** `git show {ref}:{path}` if repo is checked out locally
- **Tier 3:** Guidance — provide GitHub URL for manual inspection

### Step 4: Check Recent Commits

For each affected file, fetch the last 3 commits within 48 hours of incident start:
```bash
gh api repos/{owner}/{repo}/commits?path={path}&per_page=3&sha={resolved_commit_sha}
```

Look for regression indicators:
- Removed safety checks or error handling
- Changed code paths at or near the error location
- Dependency version bumps
- Skip lockfiles and generated metadata (manifest-only review)

For monorepos: path-filter to service root if mapping is known.

### Step 4.5: Cross-Reference with Observed Errors

For each regression candidate from Step 4:
1. State which observed error pattern(s) from INVESTIGATE Step 2 this change could explain.
   Be specific: "removed null check → could produce the NPE in UserController:142 seen in
   logs at 14:18."
2. State which observed patterns it CANNOT explain. E.g., "this change only affects the
   /users endpoint, but errors were also seen on /diet-suggestions."
3. If no candidate explains the dominant error pattern, note: "no commit explains primary
   error pattern" — this weakens the bad-release hypothesis and should be reflected in
   Step 5 hypothesis formation.

### Step 4.5b: Bounded Expansion (conditional)

Gate: `source_analysis.status == reviewed_no_regression` after Step 4.5, AND no candidate's
`explains_patterns` includes the dominant error pattern from INVESTIGATE Step 2. This fires
when: (a) `regression_candidates` is empty, (b) candidates exist but all have empty
`explains_patterns`, OR (c) candidates explain secondary symptoms but not the dominant error.

Expand the search using commit and module proximity:

1. **Same-commit siblings:** Other files changed in the same candidate commits from Step 4
   (i.e., files that were part of the same commit as the analyzed file). Max 5 files,
   excluding lockfiles, generated code, test files, docs. If a candidate is found, stop —
   do not proceed to step 2.
2. **Same-package peers (only if step 1 found no candidate):** Check files in the same
   module/package as the mapped stack frame (e.g., same Java package, same Python module,
   same Go package) that were modified within the 48h window. Max 3 files.

For each expanded file, apply Step 4.5 cross-reference: can this change explain the observed
error patterns?

Output: update `source_analysis` with:
```yaml
  analysis_basis: "primary_frame" | "bounded_expansion_same_commit" | "bounded_expansion_same_package"
```

If expansion still yields no candidate, status remains `reviewed_no_regression` with
`analysis_basis: "bounded_expansion_same_package"` (indicating expansion was attempted).

### Step 5: Emit Structured Output

```yaml
source_analysis:
  status: reviewed_no_regression | candidate_found
  analysis_basis: "primary_frame"
  deployed_ref: "v2.3.1"
  resolved_commit_sha: "abc123def456..."
  source_files:
    - path: "src/main/java/com/oviva/user/UserController.java"
      line: 142
      code_context: |
        User user = userRepository.findById(id);
        return user.toDto();  // line 142 - NPE if null
      status: analyzed | not_found | access_denied
  regression_candidates:
    - commit_sha: "def456..."
      date: "2026-03-24T10:30:00Z"
      summary: "removed null check in getUser()"
      files: ["UserController.java"]
      explains_patterns: ["NPE in UserController:142", "null user in toDto()"]
      cannot_explain_patterns: ["DEADLINE_EXCEEDED on SpiceDB calls"]
```

When candidates were reviewed but none explain the dominant error (Step 4.5b depends
on this distinction from the empty-list case below):
```yaml
source_analysis:
  status: reviewed_no_regression
  analysis_basis: "primary_frame"
  deployed_ref: "v2.3.1"
  resolved_commit_sha: "abc123def456..."
  source_files:
    - path: "src/main/java/com/oviva/user/UserController.java"
      line: 142
      code_context: "user.toDto() — no obvious defect at deployed version"
      status: analyzed
  regression_candidates:
    - commit_sha: "def456..."
      date: "2026-03-24T10:30:00Z"
      summary: "removed null check in getUser()"
      files: ["UserController.java"]
      explains_patterns: []
      cannot_explain_patterns: ["DEADLINE_EXCEEDED on SpiceDB calls"]
  cross_reference_note: "no commit explains primary error pattern — bad-release hypothesis weakened"
```

When no candidates were found at all (empty list, no cross-reference possible):
```yaml
source_analysis:
  status: reviewed_no_regression
  analysis_basis: "primary_frame"
  deployed_ref: "v2.3.1"
  resolved_commit_sha: "abc123def456..."
  source_files:
    - path: "src/main/java/com/oviva/user/UserController.java"
      line: 142
      code_context: "user.toDto() — no obvious defect at deployed version"
      status: analyzed
  regression_candidates: []
  cross_reference_note: null
```

## Failure Handling

**Fail-open with explicit warning.** If any GitHub API call fails (timeout, 404, rate
limit, authentication error):

> "Step 4b: GitHub API unavailable ({error}), source analysis skipped. Investigation
> continues without source code context."

The user must know a data source was unavailable. Never silently degrade.

## Scope Constraints

- **Same service only.** No multi-repo traversal.
- **Bounded:** Max 1-2 top actionable stack frames, 1-2 primary files, last 3 commits within
  48h. Bounded expansion (Step 4.5b): max 5 same-commit siblings + 3 same-package peers.
- **Read-only.** No code modification suggestions (that's the Flight Plan in Step 6).
- **No blame analysis** or authorship tracking.

## Token Budget

This reference file is loaded only when Step 4b is active (gate conditions met).
SKILL.md holds ~15-20 lines inline pointing here.
