# Incident Trend Analyzer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement on-demand postmortem trend analysis as a standalone skill (`incident-trend-analyzer` v2.0)

**Architecture:** New skill at `skills/incident-trend-analyzer/SKILL.md` reads canonical `docs/postmortems/*.md` (non-recursive), builds normalized incident records with confidence-aware extraction, and outputs recurrence patterns + trigger distribution + MTTR/MTTD metrics. Terminal-first output with optional persist-to-file flow.

**Tech Stack:** Pure SKILL.md (prompt-driven), routing via `default-triggers.json`, Bash 3.2 compatible test scripts

**Spec:** `docs/superpowers/specs/2026-03-21-incident-trend-analyzer-design.md`

---

### Task 1: Add routing entry to `default-triggers.json`

**Files:**
- Modify: `config/default-triggers.json:381-395` (insert after `incident-analysis` entry)

- [ ] **Step 1: Write the routing test — trigger matching**

Add to `tests/test-routing.sh` after the existing incident-analysis test invocation lines (after line 1623). First, create a helper that extends the registry with both incident-analysis AND incident-trend-analyzer:

```bash
# Helper: install registry with incident-analysis + incident-trend-analyzer
install_registry_with_incident_trend() {
    install_registry_with_incident_analysis
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"
    jq '.skills += [{
      "name": "incident-trend-analyzer",
      "role": "domain",
      "phase": "DEBUG",
      "triggers": ["(incident.trend|postmortem.trend|what.keeps.breaking|recurring.incident|failure.pattern|incident.pattern|analyze.postmortems)"],
      "trigger_mode": "regex",
      "priority": 20,
      "precedes": [],
      "requires": [],
      "invoke": "Skill(auto-claude-skills:incident-trend-analyzer)",
      "keywords": ["postmortem trends", "recurring incidents", "incident patterns", "what keeps breaking"],
      "available": true,
      "enabled": true
    }]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"
}
```

- [ ] **Step 2: Write the routing test — trigger matching assertions**

Add test section "32. Incident-trend-analyzer routing tests" to `tests/test-routing.sh`:

```bash
# ---------------------------------------------------------------------------
# 32. Incident-trend-analyzer routing tests
# ---------------------------------------------------------------------------
test_trend_analyzer_trigger_matching() {
    echo "-- test: incident-trend-analyzer fires on trend keywords --"
    setup_test_env
    install_registry_with_incident_trend

    local output context

    for prompt in \
        "show me the incident trends across our postmortems" \
        "what keeps breaking in production" \
        "analyze postmortems for recurring incidents" \
        "are there any failure patterns in our incidents"; do
        output="$(run_hook "${prompt}")"
        context="$(extract_context "${output}")"
        assert_contains "trend-analyzer fires on: ${prompt}" "incident-trend-analyzer" "${context}"
    done

    teardown_test_env
}
```

- [ ] **Step 3: Write the routing test — non-overlap with incident-analysis**

```bash
test_trend_analyzer_no_false_positive() {
    echo "-- test: incident-trend-analyzer does NOT fire on pure investigation prompts --"
    setup_test_env
    install_registry_with_incident_trend

    local output context

    output="$(run_hook "investigate this production incident in the auth service")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires" "incident-analysis" "${context}"

    # incident-trend-analyzer should NOT appear — no trend/pattern/recurring triggers
    if printf '%s' "${context}" | grep -q "incident-trend-analyzer"; then
        _record_fail "trend-analyzer should not fire on investigation prompt"
    else
        _record_pass "trend-analyzer correctly absent on investigation prompt"
    fi

    teardown_test_env
}
```

- [ ] **Step 4: Write the routing test — outscoring on trend prompts**

Use `SKILL_EXPLAIN=1` to capture raw scores and compare:

```bash
test_trend_analyzer_outscores_incident_analysis() {
    echo "-- test: trend-analyzer outscores incident-analysis on trend prompts --"
    setup_test_env
    install_registry_with_incident_trend

    local stderr_file="${TEST_TMPDIR}/stderr_trend_scores.txt"

    for prompt in \
        "what keeps breaking" \
        "show me postmortem trends" \
        "any recurring incidents this quarter"; do
        jq -n --arg p "${prompt}" '{"prompt":$p}' | \
            CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
            SKILL_EXPLAIN=1 \
            bash "${HOOK}" 2>"${stderr_file}" >/dev/null

        local stderr_content
        stderr_content="$(cat "${stderr_file}")"

        # Extract scores: incident-trend-analyzer=NN and incident-analysis=NN
        # NOTE: grep for 'incident-analysis=' would also match 'incident-trend-analyzer='
        # because it's a substring. Use a leading space or start-of-field anchor to disambiguate.
        local trend_score ia_score
        trend_score="$(printf '%s' "${stderr_content}" | grep -oE 'incident-trend-analyzer=[0-9]+' | head -1 | cut -d= -f2)"
        ia_score="$(printf '%s' "${stderr_content}" | grep -oE '(^| )incident-analysis=[0-9]+' | head -1 | sed 's/.*=//')"

        # trend_score may be empty if skill didn't score — that's a failure
        if [ -z "${trend_score}" ]; then
            _record_fail "trend-analyzer has no score on: ${prompt}"
        elif [ -z "${ia_score}" ] || [ "${trend_score}" -gt "${ia_score}" ]; then
            _record_pass "trend-analyzer outscores incident-analysis on: ${prompt}"
        else
            _record_fail "trend-analyzer (${trend_score}) should outscore incident-analysis (${ia_score}) on: ${prompt}"
        fi
    done

    teardown_test_env
}
```

- [ ] **Step 5: Write the routing test — co-firing verification**

Spec test strategy item 4: both skills must appear when both triggers match.

```bash
test_trend_analyzer_cofires_with_incident_analysis() {
    echo "-- test: trend-analyzer and incident-analysis co-fire on trend+incident prompts --"
    setup_test_env
    install_registry_with_incident_trend

    local output context

    output="$(run_hook "analyze postmortems for recurring incidents")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis co-fires" "incident-analysis" "${context}"
    assert_contains "trend-analyzer co-fires" "incident-trend-analyzer" "${context}"

    teardown_test_env
}
```

- [ ] **Step 6: Write the routing test — trigger source correctness**

```bash
test_trend_analyzer_trigger_source() {
    echo "-- test: default-triggers.json contains incident-trend-analyzer entry --"

    local invoke_path
    invoke_path="$(jq -r '.. | objects | select(.name == "incident-trend-analyzer") | .invoke // empty' config/default-triggers.json)"
    assert_equals "invoke path correct" "Skill(auto-claude-skills:incident-trend-analyzer)" "${invoke_path}"

    local phase
    phase="$(jq -r '.. | objects | select(.name == "incident-trend-analyzer") | .phase // empty' config/default-triggers.json)"
    assert_equals "phase is DEBUG" "DEBUG" "${phase}"
}
```

- [ ] **Step 7: Add test invocation lines**

After the function definitions, add the invocation block (following the existing pattern where each section defines functions then calls them):

```bash
test_trend_analyzer_trigger_matching
test_trend_analyzer_no_false_positive
test_trend_analyzer_outscores_incident_analysis
test_trend_analyzer_cofires_with_incident_analysis
test_trend_analyzer_trigger_source
```

Place this block after line 1623 (the last invocation line of section 31), before the next section separator.

- [ ] **Step 8: Run tests to verify they fail**

Run: `bash tests/test-routing.sh 2>&1 | tail -20`
Expected: New tests FAIL (routing entry doesn't exist yet; trigger source test fails)

- [ ] **Step 9: Add the routing entry to `default-triggers.json`**

Insert after the `incident-analysis` skill entry (after line 395), before the `phase_guide` section:

```json
    ,{
      "name": "incident-trend-analyzer",
      "role": "domain",
      "phase": "DEBUG",
      "triggers": [
        "(incident.trend|postmortem.trend|what.keeps.breaking|recurring.incident|failure.pattern|incident.pattern|analyze.postmortems)"
      ],
      "keywords": ["postmortem trends", "recurring incidents", "incident patterns", "what keeps breaking"],
      "trigger_mode": "regex",
      "priority": 20,
      "precedes": [],
      "requires": [],
      "description": "On-demand postmortem trend analysis: recurrence grouping, trigger categorization, MTTR/MTTD from canonical docs/postmortems/ corpus.",
      "invoke": "Skill(auto-claude-skills:incident-trend-analyzer)"
    }
```

- [ ] **Step 10: Run tests to verify they pass**

Run: `bash tests/test-routing.sh 2>&1 | tail -20`
Expected: All new tests PASS. All existing tests still PASS.

- [ ] **Step 11: Commit**

```bash
git add config/default-triggers.json tests/test-routing.sh
git commit -m "feat: add incident-trend-analyzer routing entry and tests"
```

---

### Task 2: Add fallback parity test to `test-registry.sh`

**Files:**
- Modify: `tests/test-registry.sh` (add assertion inside existing `test_fallback_registry_skill_coverage`)

**Important caveat:** The existing `test_fallback_registry_skill_coverage` (line 457) checks that every **fallback** skill exists in default-triggers (fallback ⊆ defaults), NOT the reverse. This means adding `incident-trend-analyzer` to `default-triggers.json` without regenerating the fallback will NOT be caught by the existing parity test. The fallback must be regenerated (Task 4) for the entry to appear.

The existing `test_fallback_auto_regenerated` (line 1216) verifies the session-start hook can regenerate the fallback. Combined with Task 4's explicit regeneration step, parity is covered without new test code.

- [ ] **Step 1: Verify current registry tests pass**

Run: `bash tests/test-registry.sh 2>&1 | tail -20`
Expected: All tests PASS. The fallback does not yet contain `incident-trend-analyzer` but the parity test only checks the fallback→defaults direction, so it passes.

- [ ] **Step 2: No new test code needed**

The parity gap (defaults→fallback direction) is addressed by Task 4's mandatory fallback regeneration. After regeneration, the existing parity test covers both entries.

---

### Task 3: Create `skills/incident-trend-analyzer/SKILL.md`

**Files:**
- Create: `skills/incident-trend-analyzer/SKILL.md`

This is the core deliverable. The SKILL.md teaches Claude how to read postmortems, build incident records, and output trend analysis.

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p skills/incident-trend-analyzer
```

- [ ] **Step 2: Write the SKILL.md**

Create `skills/incident-trend-analyzer/SKILL.md` with the full skill content. Structure:

```markdown
---
name: incident-trend-analyzer
description: On-demand postmortem trend analysis — recurrence grouping, trigger categorization, MTTR/MTTD from canonical docs/postmortems/ corpus
---

# Incident Trend Analyzer

On-demand analysis of historical postmortems from `docs/postmortems/`. Reads canonical postmortems generated by the incident-analysis skill, extracts normalized incident records, and surfaces recurrence patterns, trigger distributions, and timing metrics.

## Step 1: Scan Corpus

Read files matching `docs/postmortems/*.md` (non-recursive — do NOT descend into subdirectories like `docs/postmortems/trends/`).

Filter to files with filenames matching `YYYY-MM-DD-*.md`. Report total files found.

**Minimum corpus:** If fewer than 3 files pass the recurrence-eligibility check (Step 2), stop and report:

> Not enough data for trend analysis. Found N postmortems, M recurrence-eligible. Minimum 3 recurrence-eligible postmortems required.

List the files found and their eligibility status.

## Step 2: Parse and Classify Eligibility

For each file, extract raw section text by heading boundaries. Classify eligibility:

| Tier | Required headings | Enables |
|------|-------------------|---------|
| **Recurrence-eligible** | `## 1. Summary` + `## 4. Root Cause & Trigger` | Recurrence grouping, trigger categorization |
| **Timeline-eligible** | Recurrence-eligible + `## 3. Timeline` with parseable timestamps | Timing metric candidates |
| **MTTR-eligible** | Timeline-eligible + identifiable detection and recovery events | MTTR computation |
| **MTTD-eligible** | Timeline-eligible + identifiable trigger and detection events | MTTD computation |

**Parseable timestamps:** Absolute only — ISO 8601 (`2026-03-15T10:32:00Z`), `HH:MM` or `HH:MM:SS` (date from filename), or `YYYY-MM-DD HH:MM`. Relative timestamps ("5 minutes later", "+10m") are NOT parseable.

Files that lack the required headings for recurrence-eligibility are listed in the coverage report but excluded from analysis.

## Step 3: Build Normalized Incident Records

For each recurrence-eligible postmortem, build one record:

### Service Extraction (from Summary)
- **high confidence:** Service name appears explicitly (e.g., "auth-service experienced...", "The checkout-service returned...")
- **medium confidence:** Derived from filename slug (e.g., `2026-03-15-auth-timeout-spike.md` → `auth`). Use only the first segment before a failure-mode word.
- **low confidence → `unknown-service`:** Neither source is clear. Prefer `unknown-service` over guessing.

### Failure Mode (from Root Cause & Trigger)

Match against this vocabulary. Use the key with the most signal word matches. Show the raw Root Cause sentence as evidence, but group ONLY on the vocabulary key.

| Key | Signal patterns |
|-----|----------------|
| `timeout` | timeout, deadline exceeded, context cancelled |
| `oom` | OOM, out of memory, memory limit, killed |
| `config-change` | config, misconfiguration, feature flag, env var |
| `dependency-failure` | upstream, downstream, third-party, provider outage |
| `deploy-regression` | deploy, release, regression, rollback, bad merge |
| `traffic-overload` | spike, load, burst, capacity, scaling, rate limit |
| `infra-failure` | node, disk, network, DNS, certificate, zone |
| `unknown` | No confident match (0 signal words, or tie between categories) |

**Confidence:** high (2+ signal words match one key), medium (1 signal word), low → `unknown`.

### Trigger Category (from Root Cause & Trigger)

| Category | Signal patterns |
|----------|----------------|
| `deployment` | deploy, release, rollout, version, merge |
| `config-change` | config, feature flag, env var, parameter |
| `dependency` | upstream, downstream, third-party, provider, API |
| `traffic` | spike, load, burst, capacity, scaling |
| `infrastructure` | node, disk, network, DNS, certificate |
| `unknown` | No clear match, or tie |

If multiple categories match, pick the one with the most signal words. If tied, use `unknown`.

### Timing Extraction (from Timeline)

For timeline-eligible records only. Extract:
- **incident_start:** Row containing "deployed", "pushed", "config changed", "traffic spike", or first row if it describes a causal event
- **detected_at:** Row containing "alert", "page", "noticed", "reported", "detected"
- **recovered_at:** Row containing "resolved", "recovered", "mitigated", "restored"

**timing_confidence:** high (3/3 timestamps), medium (2/3), low (0–1).

## Step 4: Compute Metrics

### Recurrence Grouping
- Group records by `(service, failure_mode)` — vocabulary keys only
- Groups with count >= 2 are recurrences, sorted by count descending
- Per cluster, note the dominant `trigger_category` as an annotation
- **Exclude `unknown-service / unknown` clusters from the headline recurrence section.** Show them in a separate "Uncategorized" line.

### Trigger Distribution
- Count each `trigger_category` across all recurrence-eligible records
- Show as count and percentage, sorted by count descending

### MTTR (detection → recovery)
- Formula: `recovered_at - detected_at`
- Include only records where both timestamps have timing_confidence >= medium
- Report: **median** (headline), mean, range

### MTTD (incident start → detection)
- Formula: `detected_at - incident_start`
- Include only records where both timestamps have timing_confidence >= medium
- Report: **median** (headline), mean, range

## Step 5: Generate Output

### Terminal Summary (default)

Print the following structure:

```
## Incident Trend Analysis

Corpus: N files scanned, X recurrence-eligible, Y MTTR-eligible, Z MTTD-eligible
Period: YYYY-MM-DD to YYYY-MM-DD (N days)

### Recurrence Patterns
  service / failure_mode  — N incidents (dates) | trigger: category
  ...
  N incidents showed no recurrence

### Trigger Distribution
  category  — N (PP%)
  ...

### MTTR (Y of X eligible)
  Median: Xm | Mean: Xm | Range: Xm – Xm

### MTTD (Z of X eligible)
  Median: Xm | Mean: Xm | Range: Xm – Xm

### Coverage Gaps
  (Report any metric with < 60% eligibility)

### Insights
- (2–4 cited observations — see rules below)
```

### Insights Rules

Generate 2–4 bullets. Each MUST cite a supporting count or rate:
- Top recurrence cluster + its dominant trigger (e.g., "3x in 63 days — all dependency-triggered")
- Dominant trigger category if > 40% of incidents (e.g., "4/9 incidents, 44%")
- MTTD outliers > 2x median (e.g., "incident X had 45 min MTTD vs 8 min median")
- Coverage gaps < 60% for any metric (e.g., "MTTD available for only 5/9 incidents")

Insights are **observations with citations, not prescriptions**. Do NOT recommend fixes.

## Step 6: Persist (on request only)

If the user requests saving ("save this", "save report", "persist"):

1. Create `docs/postmortems/trends/` if it doesn't exist
2. Write to `docs/postmortems/trends/YYYY-MM-DD-trend-report.md`
3. If a same-day report already exists, append `-2`, `-3`, etc.
4. Content: full terminal summary + per-incident record table
5. Do NOT auto-commit — user decides

Output: `Trend report saved to docs/postmortems/trends/YYYY-MM-DD-trend-report.md`
```

The exact wording above is the full SKILL.md content to write. Adjust formatting as needed but preserve all semantic content from the spec.

- [ ] **Step 3: Verify the skill file is well-formed**

```bash
head -5 skills/incident-trend-analyzer/SKILL.md
```

Expected: YAML frontmatter with `name: incident-trend-analyzer` and `description:` fields.

- [ ] **Step 4: Commit**

```bash
git add skills/incident-trend-analyzer/SKILL.md
git commit -m "feat: create incident-trend-analyzer skill (v2.0)"
```

---

### Task 4: Sync fallback registry and run full test suite

**Files:**
- Verify: `config/fallback-registry.json` (auto-regenerated)
- Run: all test suites

- [ ] **Step 1: Run session-start hook to regenerate fallback**

```bash
echo '{}' | CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start-hook.sh 2>/dev/null | head -5
```

This triggers the fallback auto-regeneration (Step 10c of session-start-hook.sh).

- [ ] **Step 2: Verify incident-trend-analyzer in fallback registry**

```bash
jq '.skills[] | select(.name == "incident-trend-analyzer")' config/fallback-registry.json
```

Expected: Entry with `invoke: "Skill(auto-claude-skills:incident-trend-analyzer)"`, `phase: "DEBUG"`, `role: "domain"`.

- [ ] **Step 3: Run full test suite**

```bash
bash tests/run-tests.sh
```

Expected: All tests PASS, including:
- New routing tests (trigger matching, non-overlap, outscoring, trigger source)
- Existing incident-analysis tests (no regression)
- Existing fallback parity test (auto-picks up new entry)
- All other test suites

- [ ] **Step 4: Commit fallback if changed**

```bash
git add config/fallback-registry.json
git commit -m "chore: regenerate fallback registry with incident-trend-analyzer"
```

- [ ] **Step 5: Final commit — all tests green**

If all tests pass, no additional commit needed. If any test required a fix, commit the fix:

```bash
git commit -m "fix: address test feedback for incident-trend-analyzer"
```

---

### Task Summary

| Task | Description | Files | Dependencies |
|------|-------------|-------|--------------|
| 1 | Routing entry + routing tests | `default-triggers.json`, `test-routing.sh` | None |
| 2 | Fallback parity verification | `test-registry.sh` (verify only) | Task 1 |
| 3 | Create SKILL.md | `skills/incident-trend-analyzer/SKILL.md` | None |
| 4 | Sync fallback + full test suite | `fallback-registry.json`, all tests | Tasks 1–3 |

Tasks 1 and 3 are independent and can be parallelized. Task 2 depends on Task 1. Task 4 depends on all.
