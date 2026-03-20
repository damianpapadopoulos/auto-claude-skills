# Incident Analysis v1.2 — Delta

## MODIFIED Requirements

### Requirement: Postmortem Permalink Formatting
The skill SHALL format trace IDs and commit hashes as clickable Markdown links in generated postmortem documents.

#### Scenario: Trace ID in postmortem
Given the postmortem references a trace_id and project_id from Stage 2
When the agent generates the postmortem document
Then the trace reference MUST be formatted as `[Trace TRACE_ID](https://console.cloud.google.com/traces/list?project=PROJECT_ID&tid=TRACE_ID)`

#### Scenario: Cross-project trace references
Given Stage 2 Step 4 correlated Service A and Service B in different projects
When the postmortem references traces from both services
Then Service A trace links MUST use Service A's project_id and Service B trace links MUST use Service B's project_id

#### Scenario: Git commit in postmortem
Given the postmortem references a deployment commit hash
When the agent generates the postmortem document
Then it MUST derive the repo URL via `git remote get-url origin` and format as `[Commit SHORT_HASH](https://github.com/ORG/REPO/commit/FULL_HASH)` if GitHub-hosted

#### Scenario: Non-GitHub remote
Given `git remote get-url origin` returns a non-GitHub URL
When the agent formats a commit reference
Then it MUST use the raw commit hash without a link

#### Scenario: Git remote command failure
Given `git remote get-url origin` fails (no remote, no repo)
When the agent formats a commit reference
Then it MUST use the raw commit hash without a link
