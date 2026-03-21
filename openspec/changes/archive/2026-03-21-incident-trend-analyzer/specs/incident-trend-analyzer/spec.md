# Incident Trend Analyzer — Delta

## ADDED Requirements

### Requirement: Non-Recursive Corpus Scanning
The skill SHALL read only `docs/postmortems/*.md` (non-recursive) and MUST NOT descend into subdirectories.

#### Scenario: Saved reports not re-ingested
Given `docs/postmortems/trends/2026-03-21-trend-report.md` exists
When the skill scans the corpus in Step 1
Then the trends subdirectory file is NOT included in the corpus

#### Scenario: Missing directory
Given `docs/postmortems/` does not exist
When the skill starts Step 1
Then it reports "No postmortem corpus found" and stops

### Requirement: Tiered Eligibility Classification
The skill SHALL classify each postmortem into eligibility tiers based on available headings, allowing partial data to contribute to recurrence analysis even without timeline data.

#### Scenario: Postmortem with Summary and Root Cause only
Given a postmortem has `## 1. Summary` and `## 4. Root Cause & Trigger` but no `## 3. Timeline`
When the skill classifies eligibility
Then it is recurrence-eligible but NOT timeline-eligible, MTTR-eligible, or MTTD-eligible

#### Scenario: Postmortem with all required headings
Given a postmortem has Summary, Root Cause & Trigger, and Timeline with parseable timestamps
When the skill classifies eligibility
Then it is recurrence-eligible AND timeline-eligible (MTTR/MTTD eligibility depends on identifiable events)

### Requirement: Minimum Corpus Threshold
The skill SHALL require at least 3 recurrence-eligible postmortems. Below this threshold, the entire report is skipped.

#### Scenario: Fewer than 3 eligible
Given only 2 postmortems are recurrence-eligible
When the skill evaluates the corpus
Then it reports "not enough data for trend analysis" and does NOT produce any metrics

### Requirement: Confidence-Aware Service Extraction
The skill SHALL extract service names with explicit confidence levels, preferring `unknown-service` over low-confidence guesses.

#### Scenario: Explicit service name in Summary
Given the Summary section contains "auth-service experienced repeated timeouts"
When the skill extracts the service name
Then it assigns `auth-service` with high confidence

#### Scenario: No identifiable service
Given neither the Summary nor the filename clearly identifies a service
When the skill extracts the service name
Then it assigns `unknown-service` with low confidence

### Requirement: Vocabulary-Based Failure Mode Grouping
The skill SHALL use a fixed 8-key failure mode vocabulary for grouping, never free text.

#### Scenario: Two postmortems with different wording but same failure mode
Given one postmortem says "request timed out" and another says "deadline exceeded on the downstream call"
When the skill groups by failure mode
Then both are classified as `timeout` and grouped together

### Requirement: Unknown Clusters Excluded from Headline
The skill SHALL exclude `unknown-service / unknown` clusters from the headline recurrence output.

#### Scenario: Unknown cluster exists
Given 3 postmortems are classified as `unknown-service / unknown`
When the skill generates the Recurrence Patterns section
Then the unknown cluster appears in a separate Uncategorized section, not the headline

### Requirement: Correct Metric Definitions
MTTR SHALL be computed as `recovered_at - detected_at`. MTTD SHALL be computed as `detected_at - incident_start`. Headline stat SHALL be median.

#### Scenario: MTTR computation
Given detected_at is 10:00 and recovered_at is 10:47
When the skill computes MTTR
Then the result is 47 minutes

### Requirement: Cited Insights
Each insight bullet SHALL cite supporting count or rate. Insights SHALL be observations, not prescriptions.

#### Scenario: Recurrence insight
Given auth-service/timeout recurred 3 times in 63 days
When the skill generates insights
Then the insight cites "3x in 63 days"

### Requirement: Persist on Request Only
The skill SHALL write trend reports only when explicitly requested, with collision-safe filenames.

#### Scenario: User requests save
Given the user says "save this report"
When the skill persists
Then it writes to `docs/postmortems/trends/YYYY-MM-DD-trend-report.md` and does NOT auto-commit

#### Scenario: Same-day collision
Given `docs/postmortems/trends/2026-03-21-trend-report.md` already exists
When the user requests save
Then it writes to `docs/postmortems/trends/2026-03-21-trend-report-2.md`

### Requirement: Routing Integration
The skill SHALL be routable via the plugin's activation hook with domain role and explicit triggers.

#### Scenario: Trend prompt triggers skill
Given the user prompt contains "what keeps breaking"
When the activation hook scores skills
Then `incident-trend-analyzer` appears as a domain skill

#### Scenario: Investigation prompt does not trigger
Given the user prompt is "investigate this production incident"
When the activation hook scores skills
Then `incident-trend-analyzer` does NOT have a trigger match (only name-boost)

#### Scenario: Trend-analyzer outscores incident-analysis on trend prompts
Given both `incident-trend-analyzer` and `incident-analysis` are registered
When the user prompt contains "recurring failure patterns"
Then `incident-trend-analyzer` scores higher than `incident-analysis`
