# Incident-Analysis Trigger Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the incident-analysis skill trigger on natural symptom language (connection failures, SIGTERM, OOM, pod crashes) — not just explicit incident terminology.

**Architecture:** Expand triggers with signal-derived infrastructure vocabulary from `signals.yaml`, fix silently-dropped keywords, rewrite the description to lead with symptoms, and sync the gcp-observability methodology hint. No architectural changes needed — role-cap system already supports process+domain co-firing.

**Tech Stack:** Bash tests, JSON config

---

### Task 1: Write failing tests for symptom-based trigger matching

**Files:**
- Modify: `tests/test-routing.sh` (append new test block before final `print_summary`)

These tests verify that real-world incident prompts (using symptom language, not explicit "incident" terminology) cause incident-analysis to appear in the hook output as a domain skill.

- [ ] **Step 1: Write the failing tests**

Append this test block to `tests/test-routing.sh`, just before the final `print_summary` line:

```bash
# ---------------------------------------------------------------------------
# Symptom-based incident-analysis routing tests
# ---------------------------------------------------------------------------

test_incident_analysis_triggers_on_connection_failure() {
    echo "-- test: incident-analysis triggers on connection failure symptoms --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "Core failed to acquire connections while being healthy. Looking into the cloud sql proxy. Error during SIGTERM shutdown: 61 active connections still exist after waiting for 0s")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires on connection+SIGTERM symptoms" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_triggers_on_oom_kill() {
    echo "-- test: incident-analysis triggers on OOM kill symptoms --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "pod keeps getting OOMKilled, memory pressure is high and the container restarts every few minutes")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires on OOM symptoms" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_triggers_on_crash_loop() {
    echo "-- test: incident-analysis triggers on CrashLoopBackOff --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "backend-api is in CrashLoopBackOff after the latest deploy, liveness probe keeps failing")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires on crash loop symptoms" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_triggers_on_latency_spike() {
    echo "-- test: incident-analysis triggers on latency spike --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "seeing a latency spike on the payments service, p99 went from 200ms to 5s after the last deploy")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires on latency spike symptoms" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_triggers_on_cloud_sql_proxy() {
    echo "-- test: incident-analysis triggers on cloud sql proxy issues --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "cloud sql proxy restarted and dropped all active connections, the app cannot reach the database")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires on cloud sql proxy symptoms" "incident-analysis" "${context}"

    teardown_test_env
}

test_incident_analysis_cofires_with_debugging() {
    echo "-- test: incident-analysis co-fires as domain alongside systematic-debugging as process --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "connection error after SIGTERM, pod crashing and restarting")"
    context="$(extract_context "${output}")"
    assert_contains "incident-analysis fires as domain" "incident-analysis" "${context}"
    assert_contains "systematic-debugging fires as process" "systematic-debugging" "${context}"

    teardown_test_env
}

test_incident_analysis_triggers_on_connection_failure
test_incident_analysis_triggers_on_oom_kill
test_incident_analysis_triggers_on_crash_loop
test_incident_analysis_triggers_on_latency_spike
test_incident_analysis_triggers_on_cloud_sql_proxy
test_incident_analysis_cofires_with_debugging
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/test-routing.sh 2>/dev/null | grep -E "(PASS|FAIL).*(symptom|connection|oom|crash|latency|cloud.sql|co-fires)" | tail -20`

Expected: All 6 new tests FAIL because incident-analysis doesn't match symptom language yet.

- [ ] **Step 3: Commit failing tests**

```bash
git add tests/test-routing.sh
git commit -m "test: add failing tests for symptom-based incident-analysis routing"
```

---

### Task 2: Expand incident-analysis triggers and update test helper

**Files:**
- Modify: `config/default-triggers.json:411-412` (triggers array)
- Modify: `tests/test-routing.sh:420-424` (`install_registry_with_incident_analysis` helper — triggers)

The trigger terms are derived from `skills/incident-analysis/signals.yaml` signal IDs and their detection parameters — the closed vocabulary of what the skill actually knows how to investigate.

**Critical:** The test helper `install_registry_with_incident_analysis()` hard-codes the registry entries used by all incident-analysis tests. The hook under test reads from the cache file written by this helper, NOT from `default-triggers.json`. Both must be updated in sync.

- [ ] **Step 1: Replace the triggers array in default-triggers.json**

In `config/default-triggers.json`, replace the single trigger string at line 412 with three trigger strings:

```json
      "triggers": [
        "(incident|postmortem|outage|root.cause|error.spike|log.analysis|production.error|staging.error)",
        "(connection.*(fail|refus|timeout|pool|exhaust|acquir)|oom.?kill|memory.pressure|cpu.*(throttl|saturat)|crash.?loop|liveness.probe|node.not.ready|upstream.*(fail|error|timeout))",
        "(sigterm|sigkill|shutdown.*(error|fail|grace)|active.connection|cloud.?sql|proxy.*(restart|error|fail|crash)|pod.*(restart|crash|evict)|latency.*(spike|p99)|request.timeout|circuit.break|deploy.*(fail|rollback))"
      ],
```

Line 1 is the original explicit terminology (unchanged). Line 2 is signal-derived from `signals.yaml` (resource saturation, workload health, dependencies). Line 3 is operational symptom language (kill signals, infrastructure components, deploy correlation).

- [ ] **Step 2: Update the test helper triggers to match**

In `tests/test-routing.sh`, find the `install_registry_with_incident_analysis()` function (line ~415). Replace the `triggers` value in the jq expression from:

```
"triggers": ["(incident|postmortem|outage|root.cause|error.spike|log.analysis|production.error|staging.error)"],
```

to:

```
"triggers": ["(incident|postmortem|outage|root.cause|error.spike|log.analysis|production.error|staging.error)", "(connection.*(fail|refus|timeout|pool|exhaust|acquir)|oom.?kill|memory.pressure|cpu.*(throttl|saturat)|crash.?loop|liveness.probe|node.not.ready|upstream.*(fail|error|timeout))", "(sigterm|sigkill|shutdown.*(error|fail|grace)|active.connection|cloud.?sql|proxy.*(restart|error|fail|crash)|pod.*(restart|crash|evict)|latency.*(spike|p99)|request.timeout|circuit.break|deploy.*(fail|rollback))"],
```

- [ ] **Step 3: Run the tests to verify they pass**

Run: `bash tests/test-routing.sh 2>/dev/null | grep -E "(PASS|FAIL).*(symptom|connection|oom|crash|latency|cloud.sql|co-fires)" | tail -20`

Expected: All 6 new tests PASS. All pre-existing incident-analysis tests still PASS.

- [ ] **Step 4: Commit**

```bash
git add config/default-triggers.json tests/test-routing.sh
git commit -m "feat: expand incident-analysis triggers with signal-derived vocabulary"
```

---

### Task 3: Fix keywords (replace silently-dropped entries) and update test helper

**Files:**
- Modify: `config/default-triggers.json:414-420` (keywords array)
- Modify: `tests/test-routing.sh:430` (test helper keywords)

The keyword "logs" (4 chars) is silently dropped by the 6-char minimum filter at `hooks/skill-activation-hook.sh:206`. Replace with longer, more specific multi-word keywords that survive the filter and match symptom language.

- [ ] **Step 1: Replace the keywords array in default-triggers.json**

In `config/default-triggers.json`, replace the keywords:

```json
      "keywords": [
        "incident",
        "postmortem",
        "outage",
        "error spike",
        "connection failure",
        "connection pool",
        "cloud sql proxy",
        "graceful shutdown",
        "active connections",
        "health check",
        "pod restart",
        "latency spike",
        "request timeout"
      ],
```

Kept "outage" (6 chars, passes filter, specific incident term). Removed "logs" (4 chars, silently dropped). Added symptom-vocabulary keywords that complement the regex triggers. All keywords >= 6 chars.

- [ ] **Step 2: Update the test helper keywords to match**

In `tests/test-routing.sh`, find the `install_registry_with_incident_analysis()` function and replace the `keywords` value in the jq expression from:

```
"keywords": ["incident", "postmortem", "outage", "logs", "error spike"],
```

to:

```
"keywords": ["incident", "postmortem", "outage", "error spike", "connection failure", "connection pool", "cloud sql proxy", "graceful shutdown", "active connections", "health check", "pod restart", "latency spike", "request timeout"],
```

- [ ] **Step 3: Run the full routing test suite**

Run: `bash tests/test-routing.sh 2>/dev/null | tail -5`

Expected: All tests pass, including both old and new incident-analysis tests.

- [ ] **Step 4: Commit**

```bash
git add config/default-triggers.json tests/test-routing.sh
git commit -m "fix: replace silently-dropped keywords with signal-derived vocabulary"
```

---

### Task 4: Rewrite description to lead with symptoms

**Files:**
- Modify: `config/default-triggers.json:425` (description field)
- Modify: `skills/incident-analysis/SKILL.md:3` (frontmatter description)

- [ ] **Step 1: Update the description in default-triggers.json**

Replace the description field:

```json
      "description": "Investigate production symptoms: connection failures, pod crashes/restarts, SIGTERM/OOM errors, latency spikes, Cloud SQL/proxy issues, deployment-correlated errors. Playbook-driven: MITIGATE -> CLASSIFY -> INVESTIGATE -> EXECUTE -> VALIDATE -> POSTMORTEM.",
```

- [ ] **Step 2: Update the SKILL.md frontmatter description to match**

Replace line 3 in `skills/incident-analysis/SKILL.md`:

```
description: Investigate production symptoms: connection failures, pod crashes/restarts, SIGTERM/OOM errors, latency spikes, Cloud SQL/proxy issues, deployment-correlated errors
```

- [ ] **Step 3: Run routing tests**

Run: `bash tests/test-routing.sh 2>/dev/null | tail -5`

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add config/default-triggers.json skills/incident-analysis/SKILL.md
git commit -m "docs: rewrite incident-analysis description to lead with symptoms"
```

---

### Task 5: Expand gcp-observability methodology hint triggers

**Files:**
- Modify: `config/default-triggers.json:557-558` (gcp-observability triggers)
- Modify: `tests/test-routing.sh` (test helper gcp-observability entry + new test)

The gcp-observability hint references incident-analysis in its hint text but has the same narrow triggers. Sync it with the expanded vocabulary so the hint fires as a safety net.

- [ ] **Step 1: Expand the gcp-observability trigger in default-triggers.json**

Replace the single trigger string at line 558:

```json
      "triggers": [
        "(runtime.log|error.group|metric.regress|production.error|staging.error|verify.deploy|post.deploy|list.log|list.metric|trace.search|incident|postmortem|root.cause|outage|error.spike|log.analysis|5[0-9][0-9].error)",
        "(connection.*(fail|refus|timeout|pool|exhaust)|oom.?kill|crash.?loop|cloud.?sql|proxy.*(restart|error|fail)|pod.*(restart|crash|evict)|sigterm|sigkill|latency.*(spike|p99)|deploy.*(fail|rollback))"
      ],
```

- [ ] **Step 2: Update the test helper gcp-observability triggers to match**

In `tests/test-routing.sh`, find the gcp-observability entry inside `install_registry_with_incident_analysis()` (line ~434). Replace the `triggers` value in the jq expression from:

```
"triggers": ["(runtime.log|error.group|metric.regress|production.error|staging.error|verify.deploy|post.deploy|list.log|list.metric|trace.search|incident|postmortem|root.cause|outage|error.spike|log.analysis|5[0-9][0-9].error)"],
```

to:

```
"triggers": ["(runtime.log|error.group|metric.regress|production.error|staging.error|verify.deploy|post.deploy|list.log|list.metric|trace.search|incident|postmortem|root.cause|outage|error.spike|log.analysis|5[0-9][0-9].error)", "(connection.*(fail|refus|timeout|pool|exhaust)|oom.?kill|crash.?loop|cloud.?sql|proxy.*(restart|error|fail)|pod.*(restart|crash|evict)|sigterm|sigkill|latency.*(spike|p99)|deploy.*(fail|rollback))"],
```

- [ ] **Step 3: Write a test for hint firing on symptom language**

Add after the existing `test_incident_analysis_preserves_existing_triggers` test block (after its invocation line):

```bash
test_gcp_hint_fires_on_symptom_language() {
    echo "-- test: gcp-observability hint fires on symptom language --"
    setup_test_env
    install_registry_with_incident_analysis

    local output context

    output="$(run_hook "cloud sql proxy crashed and connections are failing")"
    context="$(extract_context "${output}")"
    assert_contains "gcp-observability hint fires on symptoms" "INCIDENT ANALYSIS" "${context}"

    teardown_test_env
}

test_gcp_hint_fires_on_symptom_language
```

- [ ] **Step 4: Run routing tests**

Run: `bash tests/test-routing.sh 2>/dev/null | tail -5`

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add config/default-triggers.json tests/test-routing.sh
git commit -m "feat: expand gcp-observability hint triggers to match incident-analysis vocabulary"
```

---

### Task 6: Regenerate fallback registry and run full test suite

**Files:**
- Modify: `config/fallback-registry.json` (auto-regenerated)

The fallback registry is auto-regenerated by `session-start-hook.sh` (line 771-788) when it detects changes. We trigger this manually then verify parity.

- [ ] **Step 1: Regenerate the fallback registry**

Run:
```bash
CLAUDE_PLUGIN_ROOT="$(pwd)" bash hooks/session-start-hook.sh <<< '{}' > /dev/null 2>&1
```

This runs the session-start hook which auto-regenerates `config/fallback-registry.json` at step 10c.

- [ ] **Step 2: Verify the fallback contains expanded triggers**

Run:
```bash
jq '.. | objects | select(.name == "incident-analysis") | .triggers' config/fallback-registry.json
```

Expected: Array with 3 trigger strings (original + signal-derived + operational).

- [ ] **Step 3: Run the full test suite**

Run: `bash tests/run-tests.sh`

Expected: All test suites pass.

- [ ] **Step 4: Commit**

```bash
git add config/fallback-registry.json
git commit -m "chore: regenerate fallback registry with expanded incident-analysis triggers"
```
