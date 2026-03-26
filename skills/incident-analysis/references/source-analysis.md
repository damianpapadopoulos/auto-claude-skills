# SOURCE_ANALYSIS — Reference Procedure

Conditional stage between INVESTIGATE and EXECUTE. Analyzes source code at the
deployed version when stack traces are available.

## Entry Condition

Both must be true:
1. INVESTIGATE evidence contains stack traces (extracted in Step 2)
2. Deployment info is available (image tag or SHA from k8s/metrics evidence)

If either is missing, skip this stage. Log the skip reason explicitly:
- "SOURCE_ANALYSIS skipped: no stack traces in evidence"
- "SOURCE_ANALYSIS skipped: no deployment info (image tag/SHA) available"

## Procedure

### Step 1: Resolve Deployed SHA

Extract the Git reference from deployment evidence:
- Image tag (e.g., `v2.3.1`) → Git tag
- Image SHA → Git commit SHA
- If the image tag is a semver tag, use it directly as the Git ref
- If ambiguous, log and skip: "SOURCE_ANALYSIS skipped: cannot resolve deployed SHA"

### Step 2: Map Stack Frames to Source Files

For each stack trace frame:
- Java: `com.oviva.user.UserController` → `src/main/java/com/oviva/user/UserController.java`
- Python: `app/services/checkout.py` → direct path
- Go: `github.com/org/repo/pkg/handler.go` → `pkg/handler.go`

Use `gh api repos/{owner}/{repo}/contents/{path}?ref={sha}` to verify the file exists at
the deployed version. If the file is not found, try `gh api` search as fallback:
```
gh api search/code -f q="class ClassName repo:org/repo"
```

### Step 3: Read Code at Error Location

For each mapped file, read the relevant lines (error line +/- 20 lines of context) at the
deployed SHA using:
```bash
gh api repos/{owner}/{repo}/contents/{path}?ref={sha} | jq -r '.content' | base64 -d
```

### Step 4: Check Recent Commits

For each affected file, fetch the last 3 commits:
```bash
gh api repos/{owner}/{repo}/commits?path={path}&per_page=3&sha={sha}
```

Identify regression candidates: commits within 48 hours of the incident start time that
modified the error location or its immediate callers.

### Step 5: Annotate Evidence

Add to the investigation evidence:
```yaml
source_analysis:
  deployed_sha: "v2.3.1"
  source_files:
    - path: "src/main/java/com/oviva/user/UserController.java"
      line: 142
      code_context: |
        User user = userRepository.findById(id);
        return user.toDto();  // line 142 - NPE if null
  regression_candidates:
    - commit_sha: "abc123def"
      date: "2026-03-24T10:30:00Z"
      author: "developer@example.com"
      message: "refactor: simplify user lookup"
      files_changed: ["UserController.java"]
```

## Failure Handling

**Fail-open with explicit warning.** If any GitHub API call fails (timeout, 404, rate
limit, authentication error):

> "SOURCE_ANALYSIS: GitHub API unavailable ({error}), source analysis skipped. Investigation
> continues without source code context."

The user must know a data source was unavailable. Never silently degrade.

## Token Budget

This reference file is loaded only when SOURCE_ANALYSIS is active (entry conditions met).
SKILL.md contains only the stage header and reference pointer.

## Constraints

- **Read-only.** Never suggest code changes or create PRs from this stage.
- **Bounded scope.** Only analyze files referenced in stack traces. No broad repo scanning.
- **One repo per service.** Do not follow cross-repo dependencies from source analysis.
