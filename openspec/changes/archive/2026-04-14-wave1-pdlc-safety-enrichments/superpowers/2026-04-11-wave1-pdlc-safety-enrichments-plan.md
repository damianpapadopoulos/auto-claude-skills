# Wave 1: PDLC Acceleration and Agent-Safety Enrichments — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three domain skills (starter-template, prototype-lab, agent-safety-review) and a scenario-eval test suite to the auto-claude-skills plugin, enriching the DESIGN phase without altering the superpowers workflow backbone.

**Architecture:** All additions are domain skills routed via `config/default-triggers.json` entries. No hook changes, no process skill additions, no superpowers modifications. Scenario-evals validate routing correctness including driver-invariant protection.

**Tech Stack:** Bash 3.2, jq, SKILL.md markdown, JSON config

**Spec:** `docs/superpowers/specs/2026-04-11-wave1-pdlc-safety-enrichments-design.md`

---

### Task 1: Add routing entries for three new skills to default-triggers.json

**Files:**
- Modify: `config/default-triggers.json` (insert after the `alert-hygiene` skill entry, before `phase_guide`)

- [ ] **Step 1: Write failing test — starter-template trigger routing**

Add a test helper and test to `tests/test-routing.sh`. Insert the helper after the existing `install_registry_with_incident_trend` helper (around line 468), and the test after the last existing test function.

```bash
# Helper: install registry extended with Wave 1 skills
install_registry_with_wave1() {
    install_registry
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file
    tmp_file="$(mktemp)"
    jq '.skills += [
      {
        "name": "writing-skills",
        "role": "domain",
        "phase": "DESIGN",
        "triggers": ["(skill|write.*skill|create.*skill|edit.*skill|new.*skill|skill.*(file|md|template|format))"],
        "trigger_mode": "regex",
        "priority": 15,
        "precedes": [],
        "requires": [],
        "invoke": "Skill(superpowers:writing-skills)",
        "available": true,
        "enabled": true
      },
      {
        "name": "starter-template",
        "role": "domain",
        "phase": "DESIGN",
        "triggers": ["(new.?skill|new.?plugin|new.?command|scaffold|skeleton|template|boilerplate)"],
        "trigger_mode": "regex",
        "priority": 16,
        "precedes": [],
        "requires": [],
        "invoke": "Skill(auto-claude-skills:starter-template)",
        "available": true,
        "enabled": true
      },
      {
        "name": "prototype-lab",
        "role": "domain",
        "phase": "DESIGN",
        "triggers": ["(prototype|compare.?options|build.?variants|which.?approach|try.?both|try.?all|side.by.side)"],
        "trigger_mode": "regex",
        "priority": 15,
        "precedes": [],
        "requires": [],
        "invoke": "Skill(auto-claude-skills:prototype-lab)",
        "available": true,
        "enabled": true
      },
      {
        "name": "agent-safety-review",
        "role": "domain",
        "phase": "DESIGN",
        "triggers": ["(autonomous.?loop|ralph.?loop|overnight|unattended|background.?agent|browser.?agent|email.?agent|inbox.?agent|yolo|skip.?permission|dangerously|permissionless|auto.?reply|auto.?respond|send.on.behalf)"],
        "trigger_mode": "regex",
        "priority": 17,
        "precedes": [],
        "requires": [],
        "invoke": "Skill(auto-claude-skills:agent-safety-review)",
        "available": true,
        "enabled": true
      }
    ]' "$cache_file" > "$tmp_file" && mv "$tmp_file" "$cache_file"
}
```

Test function:

```bash
# ---------------------------------------------------------------------------
# Wave 1: starter-template triggers on "new skill" prompt
# ---------------------------------------------------------------------------
test_starter_template_triggers() {
    echo "-- test: starter-template triggers on new skill prompt --"
    setup_test_env
    install_registry_with_wave1

    local output
    output="$(run_hook "create a new skill for database migrations")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "starter-template fires on new skill" "starter-template" "${context}"
    assert_contains "brainstorming is still process skill" "brainstorming" "${context}"

    teardown_test_env
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "starter-template"`
Expected: FAIL — `install_registry_with_wave1` function not yet in the file, or skill not in registry

- [ ] **Step 3: Write failing test — prototype-lab trigger routing**

```bash
# ---------------------------------------------------------------------------
# Wave 1: prototype-lab triggers on "compare options" prompt
# ---------------------------------------------------------------------------
test_prototype_lab_triggers() {
    echo "-- test: prototype-lab triggers on compare options prompt --"
    setup_test_env
    install_registry_with_wave1

    local output
    output="$(run_hook "let's prototype and compare options for the caching layer")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "prototype-lab fires on compare options" "prototype-lab" "${context}"
    assert_contains "brainstorming is still process skill" "brainstorming" "${context}"

    teardown_test_env
}
```

- [ ] **Step 4: Write failing test — agent-safety-review trigger routing**

```bash
# ---------------------------------------------------------------------------
# Wave 1: agent-safety-review triggers on autonomous loop prompt
# ---------------------------------------------------------------------------
test_agent_safety_review_triggers() {
    echo "-- test: agent-safety-review triggers on autonomous loop prompt --"
    setup_test_env
    install_registry_with_wave1

    local output
    output="$(run_hook "set up an autonomous loop to process incoming emails overnight")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "agent-safety-review fires on autonomous loop" "agent-safety-review" "${context}"

    teardown_test_env
}
```

- [ ] **Step 5: Write failing test — driver invariant protection**

```bash
# ---------------------------------------------------------------------------
# Wave 1: driver invariants — new skills do not displace process drivers
# ---------------------------------------------------------------------------
test_wave1_driver_invariants() {
    echo "-- test: Wave 1 skills do not displace process drivers --"
    setup_test_env
    install_registry_with_wave1

    # DESIGN driver must remain brainstorming, not prototype-lab or agent-safety-review
    local output
    output="$(run_hook "build a new autonomous email agent skill")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "brainstorming remains DESIGN process" "Process: brainstorming" "${context}"
    assert_not_contains "prototype-lab is not process" "Process: prototype-lab" "${context}"
    assert_not_contains "agent-safety-review is not process" "Process: agent-safety-review" "${context}"

    teardown_test_env
}
```

- [ ] **Step 6: Run all four tests to verify they fail**

Run: `bash tests/test-routing.sh 2>&1 | tail -20`
Expected: 4 new FAILs (helper not wired, skills not in registry)

- [ ] **Step 7: Add the three skill entries to default-triggers.json**

Insert after the `alert-hygiene` entry (after line 527 closing `}`), before the `phase_guide` section:

```json
    {
      "name": "starter-template",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": [
        "(new.?skill|new.?plugin|new.?command|scaffold|skeleton|template|boilerplate)"
      ],
      "keywords": [
        "new skill",
        "create skill",
        "skill skeleton",
        "scaffold",
        "boilerplate",
        "starter template"
      ],
      "trigger_mode": "regex",
      "priority": 16,
      "precedes": [],
      "requires": [],
      "description": "Emit repo-native seed files (SKILL.md skeleton, routing entry, test snippets) when creating new skills, commands, or plugins.",
      "invoke": "Skill(auto-claude-skills:starter-template)"
    },
    {
      "name": "prototype-lab",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": [
        "(prototype|compare.?options|build.?variants|which.?approach|try.?both|try.?all|side.by.side)"
      ],
      "keywords": [
        "prototype",
        "compare options",
        "build variants",
        "which approach",
        "try both",
        "side by side"
      ],
      "trigger_mode": "regex",
      "priority": 15,
      "precedes": [],
      "requires": [],
      "description": "Produce 3 thin comparable variants of a proposed design with a comparison artifact and mandatory Human Validation Plan.",
      "invoke": "Skill(auto-claude-skills:prototype-lab)"
    },
    {
      "name": "agent-safety-review",
      "role": "domain",
      "phase": "DESIGN",
      "triggers": [
        "(autonomous.?loop|ralph.?loop|overnight|unattended|background.?agent|browser.?agent|email.?agent|inbox.?agent|yolo|skip.?permission|dangerously|permissionless|auto.?reply|auto.?respond|send.on.behalf)"
      ],
      "keywords": [
        "autonomous loop",
        "overnight agent",
        "unattended",
        "email agent",
        "browser agent",
        "YOLO mode",
        "skip permissions",
        "lethal trifecta"
      ],
      "trigger_mode": "regex",
      "priority": 17,
      "precedes": [],
      "requires": [],
      "description": "Evaluate designs involving autonomous agents for the lethal trifecta: private data + untrusted input + outbound action. Requires blast-radius mitigation, not better filtering.",
      "invoke": "Skill(auto-claude-skills:agent-safety-review)"
    }
```

- [ ] **Step 8: Add matching entries to fallback-registry.json**

Insert the same three entries into the `skills` array of `config/fallback-registry.json`, using the compact format (single-line triggers) matching the existing fallback style. Insert after the `alert-hygiene` entry.

- [ ] **Step 9: Wire test helper and test functions into test-routing.sh runner**

Add `install_registry_with_wave1` helper and the four test functions to `test-routing.sh`. Add calls to all four test functions in the test runner section at the bottom of the file.

- [ ] **Step 10: Run tests to verify they pass**

Run: `bash tests/test-routing.sh 2>&1 | tail -30`
Expected: All 4 new tests PASS. All existing tests still PASS.

- [ ] **Step 11: Commit**

```bash
git add config/default-triggers.json config/fallback-registry.json tests/test-routing.sh
git commit -m "feat: add routing entries for Wave 1 skills (starter-template, prototype-lab, agent-safety-review)"
```

---

### Task 2: Create starter-template skill

**Files:**
- Create: `skills/starter-template/SKILL.md`

- [ ] **Step 1: Write failing test — starter-template content contract**

Add to `tests/test-routing.sh`:

```bash
# ---------------------------------------------------------------------------
# Wave 1: starter-template SKILL.md content contract
# ---------------------------------------------------------------------------
test_starter_template_content_contract() {
    echo "-- test: starter-template SKILL.md has required sections --"
    local skill_file="${PROJECT_ROOT}/skills/starter-template/SKILL.md"

    local content
    content="$(cat "${skill_file}" 2>/dev/null || echo "")"

    assert_not_empty "starter-template SKILL.md exists and is non-empty" "${content}"
    assert_contains "starter-template has frontmatter name" "name: starter-template" "${content}"
    assert_contains "starter-template has When to Use section" "When to Use" "${content}"
    assert_contains "starter-template has Constraints section" "Constraints" "${content}"
    assert_contains "starter-template has SKILL.md skeleton" "SKILL.md skeleton" "${content}"
    assert_contains "starter-template has routing entry snippet" "default-triggers.json" "${content}"
    assert_contains "starter-template has test snippet" "test-routing.sh" "${content}"
    assert_contains "starter-template warns about process skill restriction" "superpowers-owned phase" "${content}"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "content contract"`
Expected: FAIL — `skills/starter-template/SKILL.md` does not exist yet, so `assert_not_empty` fails

- [ ] **Step 3: Create skills/starter-template/SKILL.md**

```markdown
---
name: starter-template
description: Emit repo-native seed files (SKILL.md skeleton, routing entry, test snippets) when creating new skills, commands, or plugins
---

# Starter Template

Emit seed files for new additions to auto-claude-skills. Ensures agents follow existing patterns from the first file.

## When to Use

During DESIGN phase when creating new skills, commands, plugins, hooks, or modules. Co-selects with writing-skills.

## Step 1: Identify Addition Type

Ask: What are we creating?

| Type | Skeleton | Notes |
|------|----------|-------|
| Domain skill | SKILL.md + routing entry + routing test + content assertion | Default. Most new additions are domain skills. |
| Workflow skill | SKILL.md + routing entry + routing test + composition test | Include `precedes`/`requires` fields. |
| Edge-overlay process skill | SKILL.md + routing entry + routing test + content assertion | **Restricted to DISCOVER and LEARN phases only.** If the user requests a process skill for a superpowers-owned phase (DESIGN, PLAN, IMPLEMENT, REVIEW, SHIP, DEBUG), emit a warning: "This phase's process driver is owned by superpowers. Consider a domain skill instead." |
| Hook | Script + config entry + syntax test | Bash 3.2 compatible. |
| Command | Command markdown + setup registration | Follow existing `commands/` pattern. |

## Step 2: Emit SKILL.md Skeleton

Generate based on type. Include frontmatter, tiered detection where applicable, and output contract section.

**Domain skill skeleton:**

```markdown
---
name: <skill-name>
description: <one-line description>
---

# <Skill Name>

<One paragraph purpose statement.>

## When to Use

<Phase and activation context.>

## Step 1: Detect Available Tools

<Tiered detection pattern if the skill depends on external tools.>

## Step 2: <Primary Action>

<Core behavior.>

## Output Contract

<What the skill produces — artifacts, reports, structured data.>
```

## Step 3: Emit Routing Entry Snippet

Generate a JSON snippet for `config/default-triggers.json`:

```json
{
  "name": "<skill-name>",
  "role": "domain",
  "phase": "<PHASE>",
  "triggers": [
    "<regex-pattern>"
  ],
  "keywords": ["<keyword1>", "<keyword2>"],
  "trigger_mode": "regex",
  "priority": 15,
  "precedes": [],
  "requires": [],
  "description": "<one-line description>",
  "invoke": "Skill(auto-claude-skills:<skill-name>)"
}
```

Note: Also needs a matching entry in `config/fallback-registry.json` using compact single-line trigger format.

## Step 4: Emit Test Snippets

**Routing test** (for `tests/test-routing.sh`):

```bash
test_<skill_name>_triggers() {
    echo "-- test: <skill-name> triggers on <trigger phrase> --"
    setup_test_env
    install_registry_with_<skill_name>

    local output
    output="$(run_hook "<sample prompt>")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "<skill-name> fires" "<skill-name>" "${context}"

    teardown_test_env
}
```

**Content/behavior assertion** (for relevant test file):

```bash
test_<skill_name>_content_contract() {
    echo "-- test: <skill-name> SKILL.md has required sections --"
    local skill_file="${PROJECT_ROOT}/skills/<skill-name>/SKILL.md"

    # Use assert_contains with file content (assert_file_contains does not exist in test-helpers.sh)
    local content
    content="$(cat "${skill_file}" 2>/dev/null || echo "")"
    assert_not_empty "<skill-name> SKILL.md exists and is non-empty" "${content}"
    assert_contains "<skill-name> has frontmatter name field" "name:" "${content}"
    assert_contains "<skill-name> has output contract section" "Output Contract" "${content}"
}
```

## Constraints

- Produces snippets, not complete files. The user or agent integrates them.
- Does not auto-register skills — registration is a deliberate step during REVIEW.
- Adapts skeleton to skill type (domain, workflow, edge-overlay process).
- All output follows Bash 3.2 and repo JSON conventions.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "content contract"`
Expected: PASS — all 7 content assertions pass now that SKILL.md exists

- [ ] **Step 5: Commit**

```bash
git add skills/starter-template/SKILL.md tests/test-routing.sh
git commit -m "feat: add starter-template skill for repo-native seed generation"
```

---

### Task 3: Create prototype-lab skill

**Files:**
- Create: `skills/prototype-lab/SKILL.md`

- [ ] **Step 1: Write failing test — prototype-lab does not displace brainstorming**

```bash
# ---------------------------------------------------------------------------
# Wave 1: prototype-lab does not displace brainstorming as DESIGN driver
# ---------------------------------------------------------------------------
test_prototype_lab_does_not_displace_brainstorming() {
    echo "-- test: prototype-lab does not displace brainstorming --"
    setup_test_env
    install_registry_with_wave1

    local output
    output="$(run_hook "prototype three different approaches for the caching system")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "prototype-lab is domain" "prototype-lab" "${context}"
    assert_contains "brainstorming remains process" "Process: brainstorming" "${context}"
    assert_not_contains "prototype-lab is not process" "Process: prototype-lab" "${context}"

    teardown_test_env
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "displace brainstorming"`
Expected: FAIL — test function not wired yet

- [ ] **Step 3: Create skills/prototype-lab/SKILL.md**

```markdown
---
name: prototype-lab
description: Produce 3 thin comparable variants of a proposed design with a comparison artifact and mandatory Human Validation Plan
---

# Prototype Lab

Build exactly 3 thin, comparable variants of a proposed design so the user can evaluate concrete alternatives before committing to a direction.

## When to Use

During DESIGN phase when competing approaches are identified. Fires on trigger match alongside brainstorming (which remains the process driver). The user or DESIGN phase guidance may suggest prototyping; this skill does not depend on brainstorming internally escalating to it.

**Relationship to design-debate:**
- design-debate **reasons** about options (3 agents argue)
- prototype-lab **builds** comparable artifacts (3 thin variants)
- They are complementary. design-debate can precede prototype-lab.

## Step 1: Identify Variant Scope

Determine what "a variant" means for this project:

| Project type | Variant contents |
|-------------|-----------------|
| New skill | SKILL.md draft + routing entry + one behavioral test |
| New hook | Script draft + config entry + one syntax test |
| New feature | Implementation sketch + one test |
| Architecture decision | Thin proof-of-concept code + one integration test |

Default: 3 variants. User can override ("just compare these 2").

## Step 2: Build Variants

For each variant (A, B, C):
1. Create the minimum artifacts defined in Step 1
2. Keep each variant thin — enough to evaluate the approach, not production-ready
3. Label clearly: **Variant A**, **Variant B**, **Variant C**
4. Note key trade-offs for each

## Step 3: Write Comparison Artifact

Save to `docs/plans/YYYY-MM-DD-<topic>-prototype-lab.md`:

```markdown
# Prototype Comparison: <Topic>

**Date:** YYYY-MM-DD
**Variants:** 3

## Variant A: <Name>
**Approach:** <1-2 sentences>
**Trade-offs:** <pros and cons>
**Artifact:** <path or inline>

## Variant B: <Name>
**Approach:** <1-2 sentences>
**Trade-offs:** <pros and cons>
**Artifact:** <path or inline>

## Variant C: <Name>
**Approach:** <1-2 sentences>
**Trade-offs:** <pros and cons>
**Artifact:** <path or inline>

## Recommendation
**Chosen:** Variant <X>
**Reasoning:** <why this over the others>

## Human Validation Plan
<REQUIRED — how the user will test the chosen option with real usage>
<AI-simulated testing may inform the draft but never replaces this section>
<Describe: who tests, what they test, what success looks like>

## Success Signals
<What to measure after shipping to confirm the choice was right>
```

## Step 4: Present to User

Show the comparison artifact. Ask the user to choose a variant. Only the chosen variant proceeds to writing-plans. The others are archived in the comparison artifact.

## Constraints

- 3 variants is the default
- Human Validation Plan is mandatory — the skill must not proceed without it
- AI-simulated user testing may inform the draft but never replaces real-user validation
- For auto-claude-skills, "prototype" means repo-native artifacts (SKILL.md, bash scripts, routing config, tests)
- Variants are disposable — only the chosen variant survives
```

- [ ] **Step 4: Wire test and run to verify it passes**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "displace brainstorming"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add skills/prototype-lab/SKILL.md tests/test-routing.sh
git commit -m "feat: add prototype-lab skill for multi-variant design comparison"
```

---

### Task 4: Create agent-safety-review skill

**Files:**
- Create: `skills/agent-safety-review/SKILL.md`

- [ ] **Step 1: Write failing test — agent-safety-review fires on YOLO prompt**

```bash
# ---------------------------------------------------------------------------
# Wave 1: agent-safety-review fires on YOLO prompt
# ---------------------------------------------------------------------------
test_agent_safety_review_yolo() {
    echo "-- test: agent-safety-review fires on YOLO prompt --"
    setup_test_env
    install_registry_with_wave1

    local output
    output="$(run_hook "run this in YOLO mode with skip permissions")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "agent-safety-review fires on YOLO" "agent-safety-review" "${context}"

    teardown_test_env
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "YOLO"`
Expected: FAIL

- [ ] **Step 3: Create skills/agent-safety-review/SKILL.md**

```markdown
---
name: agent-safety-review
description: Evaluate designs involving autonomous agents for the lethal trifecta — private data + untrusted input + outbound action
---

# Agent Safety Review

Architectural risk assessment for designs and implementations that involve autonomous agent behavior. Separate from security-scanner (which runs deterministic static analysis).

## When to Use

During DESIGN phase when the prompt involves autonomous agents, unattended operation, private data processing with external input, or outbound actions. Also co-selects during REVIEW phase when autonomy-related triggers match alongside requesting-code-review.

## Step 1: Assess the Three Fields

For the proposed design or implementation, evaluate each field:

| Field | Question | Examples |
|-------|----------|----------|
| `private_data` | Does the agent access information that should not be shared with all parties? | User email, credentials, internal logs, PII, private repos, API keys, session tokens |
| `untrusted_input` | Can an external party inject instructions the agent will process? | Email content, web pages, user-uploaded files, API responses from third parties, webhook payloads |
| `outbound_action` | Can the agent send data or take actions visible outside its sandbox? | Sending emails, posting to Slack, pushing to git, making API calls, writing to shared filesystems, creating PRs |

For each field, state:
- **Present** — with specific evidence from the design
- **Absent** — with explanation of why
- **Unknown** — flag for further investigation

## Step 2: Classify Risk

| Fields present | Classification | Action |
|---------------|----------------|--------|
| All 3 | **Lethal trifecta** — High risk | Require mitigation before proceeding |
| 2 of 3 | **Elevated risk** | Note which leg is missing. Recommend not adding the third without mitigation. |
| 0-1 | **Standard risk** | No special action required |

## Step 3: Recommend Mitigation (if lethal trifecta)

The primary mitigation is **blast-radius control** — cutting at least one leg of the trifecta. Improved detection scores are NOT proof of safety.

**Cut private_data:**
- Isolate the agent to a sandbox with no access to sensitive data
- Use synthetic/test data instead of production data
- Limit access to only the specific data needed, not broad access

**Cut untrusted_input:**
- Pre-filter or sanitize external input before the agent processes it
- Use a quarantine boundary: a read-only agent processes untrusted content, extracts structured data, passes only the structured output to the privileged agent
- Restrict input sources to trusted parties only

**Cut outbound_action:**
- Make the agent read-only — it can analyze but not act
- Require human-in-the-loop approval for all outbound actions
- Use a narrowly scoped HITL: auto-approve low-risk actions, require approval for high-risk ones (sending data externally, deleting resources, creating public artifacts)

## Step 4: Produce Risk Assessment

Output a structured assessment:

```markdown
## Agent Safety Assessment

**Design:** <what is being evaluated>
**Date:** YYYY-MM-DD

### Risk Fields
| Field | Status | Evidence |
|-------|--------|----------|
| private_data | Present/Absent/Unknown | <specific evidence> |
| untrusted_input | Present/Absent/Unknown | <specific evidence> |
| outbound_action | Present/Absent/Unknown | <specific evidence> |

### Classification
**Risk level:** Lethal trifecta / Elevated / Standard

### Mitigation (if required)
**Recommended approach:** <which leg to cut and how>
**Trade-off:** <what capability is reduced by the mitigation>
**Residual risk:** <what remains after mitigation>
```

## Constraints

- This is an architectural review, not a pass/fail gate. The user decides whether to accept the risk.
- Do NOT claim that improved prompt-injection detection scores solve the problem. 97% detection is a failing grade when the 3% leaks private data.
- Do NOT merge this analysis into security-scanner output. Keep architectural risk separate from deterministic code scanning.
- The skill produces an assessment, not a veto. The goal is informed decision-making.
```

- [ ] **Step 4: Wire test and run to verify it passes**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "YOLO"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add skills/agent-safety-review/SKILL.md tests/test-routing.sh
git commit -m "feat: add agent-safety-review skill for lethal trifecta detection"
```

---

### Task 5: Update DESIGN phase guidance

**Files:**
- Modify: `skills/unified-context-stack/phases/design.md`

- [ ] **Step 1: Read current design.md**

Read: `skills/unified-context-stack/phases/design.md`
Current content: 19 lines covering Intent Truth and Historical Truth steps.

- [ ] **Step 2: Add prototype-lab and agent-safety-review awareness**

Append after the existing content:

```markdown

### 2. Prototype Awareness
IF brainstorming identifies competing approaches or uncertain solution shape, mention to the user:
- **prototype-lab is available** — it can build 3 thin comparable variants for side-by-side evaluation
- This is optional — not every design needs prototyping. Simple, clear decisions should proceed directly to planning.

### 3. Safety Awareness
IF the design involves autonomous agents, unattended operation, or processing external input with outbound capabilities:
- **agent-safety-review is available** — it evaluates the lethal trifecta (private data + untrusted input + outbound action)
- Mention this proactively when autonomy-related concepts appear in the design discussion
```

- [ ] **Step 3: Verify the file reads correctly**

Run: `cat skills/unified-context-stack/phases/design.md`
Expected: Original 19 lines plus new sections 2 and 3

- [ ] **Step 4: Commit**

```bash
git add skills/unified-context-stack/phases/design.md
git commit -m "feat: add prototype-lab and agent-safety-review awareness to DESIGN phase guidance"
```

---

### Task 6: Create scenario-eval test suite

**Files:**
- Create: `tests/test-scenario-evals.sh`
- Create: `tests/fixtures/scenarios/` (directory)
- Create: 12 scenario fixture files

- [ ] **Step 1: Create the fixtures directory**

```bash
mkdir -p tests/fixtures/scenarios
```

- [ ] **Step 2: Create PDLC scenario fixtures**

Create `tests/fixtures/scenarios/pdlc-01-multivariant-design.json`:
```json
{
  "name": "pdlc-01-multivariant-design",
  "prompt": "I want to prototype and compare three different approaches for the new caching layer",
  "expected_skills": ["brainstorming", "prototype-lab"],
  "expected_phase": "DESIGN",
  "must_not_match": ["Process: prototype-lab"]
}
```

Create `tests/fixtures/scenarios/pdlc-02-which-approach.json`:
```json
{
  "name": "pdlc-02-which-approach",
  "prompt": "which approach should we try for the rate limiting middleware - let's build variants",
  "expected_skills": ["brainstorming", "prototype-lab"],
  "expected_phase": "DESIGN",
  "must_not_match": []
}
```

Create `tests/fixtures/scenarios/pdlc-03-new-skill.json`:
```json
{
  "name": "pdlc-03-new-skill",
  "prompt": "create a new skill for automated database migration management",
  "expected_skills": ["brainstorming", "starter-template"],
  "expected_phase": "DESIGN",
  "must_not_match": []
}
```

- [ ] **Step 3: Create safety scenario fixtures**

Create `tests/fixtures/scenarios/safety-04-lethal-trifecta.json`:
```json
{
  "name": "safety-04-lethal-trifecta",
  "prompt": "build an email agent that auto-replies to customer support tickets from our inbox",
  "expected_skills": ["agent-safety-review"],
  "expected_phase": "DESIGN",
  "must_not_match": []
}
```

Create `tests/fixtures/scenarios/safety-05-overnight-agent.json`:
```json
{
  "name": "safety-05-overnight-agent",
  "prompt": "run this agent overnight unattended to process the backlog",
  "expected_skills": ["agent-safety-review"],
  "expected_phase": "DESIGN",
  "must_not_match": []
}
```

Create `tests/fixtures/scenarios/safety-06-yolo-mode.json`:
```json
{
  "name": "safety-06-yolo-mode",
  "prompt": "skip permissions and run in YOLO mode to speed things up",
  "expected_skills": ["agent-safety-review"],
  "expected_phase": "DESIGN",
  "must_not_match": []
}
```

- [ ] **Step 4: Create guardrail scenario fixtures**

Create `tests/fixtures/scenarios/guardrail-07-skip-tests.json`:
```json
{
  "name": "guardrail-07-skip-tests",
  "prompt": "skip tests and ship this feature now",
  "expected_skills": ["verification-before-completion"],
  "expected_phase": "SHIP",
  "must_not_match": []
}
```

Create `tests/fixtures/scenarios/guardrail-08-skip-review.json`:
```json
{
  "name": "guardrail-08-skip-review",
  "prompt": "just ship it, no review needed, push directly",
  "expected_skills": ["verification-before-completion"],
  "expected_phase": "SHIP",
  "expected_in_composition": ["requesting-code-review"],
  "must_not_match": []
}
```

Create `tests/fixtures/scenarios/guardrail-09-overnight-loop.json`:
```json
{
  "name": "guardrail-09-overnight-loop",
  "prompt": "let the agent keep trying overnight in an autonomous loop",
  "expected_skills": ["agent-safety-review"],
  "expected_phase": "DESIGN",
  "must_not_match": []
}
```

- [ ] **Step 5: Create driver-invariant scenario fixtures**

Create `tests/fixtures/scenarios/invariant-10-design-driver.json`:
```json
{
  "name": "invariant-10-design-driver",
  "prompt": "design a new notification system with prototypes",
  "expected_skills": ["brainstorming"],
  "expected_phase": "DESIGN",
  "must_not_match": ["Process: prototype-lab", "Process: starter-template", "Process: agent-safety-review"]
}
```

Create `tests/fixtures/scenarios/invariant-11-implement-driver.json`:
```json
{
  "name": "invariant-11-implement-driver",
  "prompt": "execute the plan and implement the next task",
  "expected_skills": ["executing-plans"],
  "expected_phase": "IMPLEMENT",
  "must_not_match": ["Process: prototype-lab", "Process: starter-template", "Process: agent-safety-review"]
}
```

Create `tests/fixtures/scenarios/invariant-12-review-driver.json`:
```json
{
  "name": "invariant-12-review-driver",
  "prompt": "review the code changes in this pull request",
  "expected_skills": ["requesting-code-review"],
  "expected_phase": "REVIEW",
  "must_not_match": ["Process: prototype-lab", "Process: starter-template", "Process: agent-safety-review"]
}
```

- [ ] **Step 6: Create scenario-eval test runner**

Create `tests/test-scenario-evals.sh`:

```bash
#!/usr/bin/env bash
# test-scenario-evals.sh — Suite-level behavioral evaluation for auto-claude-skills
# Tests routing judgment, not just mechanics. Validates that the right skills fire
# for the right prompts and that guardrails intercept unsafe patterns.
# Bash 3.2 compatible.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures/scenarios"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-scenario-evals.sh ==="

# ---------------------------------------------------------------------------
# Helper: run the hook with a given prompt, return stdout
# ---------------------------------------------------------------------------
run_hook() {
    local prompt="$1"
    jq -n --arg p "${prompt}" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>/dev/null
}

# Helper: extract the additionalContext text from hook JSON output
extract_context() {
    local output="$1"
    printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Install the full registry including Wave 1 skills
# ---------------------------------------------------------------------------
install_scenario_registry() {
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    # Build from default-triggers.json to get the real production registry
    cp "${PROJECT_ROOT}/config/fallback-registry.json" "${cache_file}"
}

# ---------------------------------------------------------------------------
# Run a single scenario from a fixture file
# ---------------------------------------------------------------------------
run_scenario() {
    local fixture_file="$1"
    local name prompt
    name="$(jq -r '.name' "$fixture_file")"
    prompt="$(jq -r '.prompt' "$fixture_file")"

    echo "-- scenario: ${name} --"

    local output context
    output="$(run_hook "${prompt}")"
    context="$(extract_context "${output}")"

    # Check expected phase
    local expected_phase
    expected_phase="$(jq -r '.expected_phase // empty' "$fixture_file")"
    if [ -n "${expected_phase}" ]; then
        assert_contains "${name}: expected phase '${expected_phase}'" "Phase: [${expected_phase}]" "${context}"
    fi

    # Check expected skills are present
    local expected_count
    expected_count="$(jq -r '.expected_skills | length' "$fixture_file")"
    local i=0
    while [ "$i" -lt "$expected_count" ]; do
        local expected_skill
        expected_skill="$(jq -r ".expected_skills[$i]" "$fixture_file")"
        assert_contains "${name}: expected skill '${expected_skill}'" "${expected_skill}" "${context}"
        i=$((i + 1))
    done

    # Check expected_in_composition skills appear in the composition chain
    local comp_count
    comp_count="$(jq -r '.expected_in_composition // [] | length' "$fixture_file")"
    local k=0
    while [ "$k" -lt "$comp_count" ]; do
        local comp_skill
        comp_skill="$(jq -r ".expected_in_composition[$k]" "$fixture_file")"
        assert_contains "${name}: composition includes '${comp_skill}'" "${comp_skill}" "${context}"
        k=$((k + 1))
    done

    # Check must_not_match patterns are absent
    local must_not_count
    must_not_count="$(jq -r '.must_not_match | length' "$fixture_file")"
    local j=0
    while [ "$j" -lt "$must_not_count" ]; do
        local must_not
        must_not="$(jq -r ".must_not_match[$j]" "$fixture_file")"
        assert_not_contains "${name}: must not contain '${must_not}'" "${must_not}" "${context}"
        j=$((j + 1))
    done
}

# ---------------------------------------------------------------------------
# Main: run all scenario fixtures
# ---------------------------------------------------------------------------
setup_test_env
install_scenario_registry

for fixture in "${FIXTURES_DIR}"/*.json; do
    [ -f "$fixture" ] || continue
    run_scenario "$fixture"
done

teardown_test_env

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Scenario Eval Results ==="
echo "  Total: ${TESTS_RUN}"
echo "  Passed: ${TESTS_PASSED}"
echo "  Failed: ${TESTS_FAILED}"

if [ -n "${FAIL_MESSAGES}" ]; then
    echo ""
    echo "Failures:"
    printf '%s\n' "${FAIL_MESSAGES}"
fi

if [ "${TESTS_FAILED}" -gt 0 ]; then
    exit 1
fi
```

- [ ] **Step 7: Run scenario evals**

Run: `bash tests/test-scenario-evals.sh 2>&1`
Expected: All 12 scenarios pass (some may fail if fallback-registry doesn't yet include Wave 1 entries — fix in order after Task 1 step 8)

- [ ] **Step 8: Run full test suite**

Note: `run-tests.sh` auto-discovers all `test-*.sh` files, so `test-scenario-evals.sh` is picked up automatically. No modification to `run-tests.sh` needed.

Run: `bash tests/run-tests.sh 2>&1 | tail -40`
Expected: All suites pass including scenario-evals

- [ ] **Step 10: Commit**

```bash
git add tests/test-scenario-evals.sh tests/fixtures/scenarios/
git commit -m "feat: add scenario-eval test suite with 12 PDLC, safety, guardrail, and invariant scenarios"
```

---

### Task 7: Final integration verification

**Files:**
- No new files. Verification only.

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run-tests.sh 2>&1`
Expected: All tests pass — routing, registry, context, and scenario-evals

- [ ] **Step 2: Syntax-check all new skill files**

Run: `for f in skills/starter-template/SKILL.md skills/prototype-lab/SKILL.md skills/agent-safety-review/SKILL.md; do echo "--- $f ---"; head -5 "$f"; done`
Expected: All three files exist with valid frontmatter

- [ ] **Step 3: Verify JSON validity of modified config files**

Run: `jq empty config/default-triggers.json && echo "default-triggers OK" ; jq empty config/fallback-registry.json && echo "fallback-registry OK"`
Expected: Both OK

- [ ] **Step 4: Verify driver invariants haven't changed**

Run: `jq '.phase_compositions | to_entries[] | "\(.key): \(.value.driver)"' config/default-triggers.json`
Expected output:
```
"DISCOVER: product-discovery"
"DESIGN: brainstorming"
"PLAN: writing-plans"
"IMPLEMENT: executing-plans"
"REVIEW: requesting-code-review"
"SHIP: verification-before-completion"
"DEBUG: systematic-debugging"
"LEARN: outcome-review"
```

- [ ] **Step 5: Commit any final fixes**

Only if Steps 1-4 revealed issues. Otherwise skip.

---

Plan complete and saved to `docs/superpowers/plans/2026-04-11-wave1-pdlc-safety-enrichments-plan.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?