# Design: Hypothesis-to-Learning Loop Closure

## Problem

The plugin's SDLC loop has a hard break between DISCOVER and LEARN. `product-discovery` outputs an ephemeral in-chat brief with no durable artifact. `outcome-review` references a `~/.claude/.skill-learn-baselines/` directory that nothing ever writes to. The DISCOVER phase composition has no persistence hint, unlike DESIGN which already has explicit "PERSIST DESIGN" guidance. Shipped features cannot be validated against their original hypotheses because the hypotheses don't survive the session.

## Capabilities Affected

| Capability | Change type |
|---|---|
| `product-discovery` skill | Add Hypotheses section to brief template |
| `openspec-state.sh` library | Add `openspec_state_set_discovery_path` helper function |
| `openspec-ship` skill | Add hypothesis extraction into session state (new Step 7a-bis) |
| `outcome-review` skill | Consume baseline file, add per-hypothesis validation report |
| DISCOVER phase composition | Add persistence hint matching DESIGN pattern |
| SHIP phase composition | Add `write-learn-baseline` terminal step |
| `default-triggers.json` | Composition changes for DISCOVER and SHIP phases |
| `fallback-registry.json` | Mirror all composition changes |

## Out of Scope

- **Modifying Superpowers-owned skills** — `brainstorming`, `writing-plans`, `executing-plans`, `finishing-a-development-branch`, `verification-before-completion`, `requesting-code-review` are external dependencies. We build around them, not into them.
- **Modifying `openspec_state_upsert_change` signature** — existing callers stay unchanged. New field uses a dedicated helper.
- **Hypothesis tracking UI/dashboard** — this is an artifact contract, not a product.
- **Automated PostHog query generation from hypothesis metrics** — outcome-review already handles metric queries; we add structured input, not new query logic.
- **Gap 2 (adversarial review)** — separate feature.
- **Routing hook logic, role-cap selection, trigger matching, scoring** — untouched.

## Approach

### Data Flow

```
DISCOVER                    DESIGN/PLAN              SHIP (openspec-ship)         SHIP (write-learn-baseline)     LEARN
   │                            │                          │                            │                          │
   Save discovery.md ─────► readable ──────────────────► Parse Hypotheses              │                          │
   Set discovery_path          │                         Extract H1..Hn → state         │                          │
   in session state            │                              │                         │                          │
                               │                              └──────────────────────► Read state                  │
                               │                                                      Detect ship event            │
                               │                                                      Write baseline.json ──────► Read baseline
                               │                                                           │                      Report per-H
```

### 1. Product-discovery Brief Gains a Hypotheses Section

Add to the Step 3 brief template in `skills/product-discovery/SKILL.md`:

```markdown
## Hypotheses

### H1: [description]
We believe [intervention] will [outcome].
- **Metric:** [specific metric name or event]
- **Baseline:** [current value or "unknown"]
- **Target:** [directional — "increase", "decrease >20%", or specific threshold]
- **Window:** [validation timeframe — "2 weeks post-ship", "next sprint"]
```

The prose hypothesis is what the user sees and validates. The four structured fields give outcome-review greppable data without requiring YAML or JSON parsing. All fields are nullable — `Baseline: unknown` is valid at discovery time and can be refined during DESIGN/PLAN when data is available.

### 2. DISCOVER Composition Gains a Persistence Hint

Add to the `DISCOVER` phase composition in `default-triggers.json` (and mirror in `fallback-registry.json`):

```json
{
  "text": "PERSIST DISCOVERY: After product-discovery completes and the user approves the brief, save it to `docs/plans/YYYY-MM-DD-<slug>-discovery.md`. Then run: source hooks/lib/openspec-state.sh && openspec_state_set_discovery_path \"$TOKEN\" \"$SLUG\" \"$DISCOVERY_PATH\" to set discovery_path in session state.",
  "when": "always"
}
```

This matches the existing DESIGN persistence hint pattern. The discovery artifact lands at the same `docs/plans/` path where brainstorming and writing-plans already look for intent artifacts.

### 3. New `openspec_state_set_discovery_path` Helper

Add to `hooks/lib/openspec-state.sh`:

```bash
# --- openspec_state_set_discovery_path <token> <slug> <discovery_path> ---
# Set discovery_path for a change entry.
# Creates the change entry if it doesn't exist (with other fields null).
# Same jq-merge pattern as openspec_state_mark_verified.
openspec_state_set_discovery_path() {
    local token="${1:-}"
    local slug="${2:-}"
    local discovery_path="${3:-}"
    [ -z "$token" ] && return 0
    [ -z "$slug" ] && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    if [ -f "$state_file" ]; then
        local tmp
        tmp="$(jq --arg slug "$slug" --arg dp "$discovery_path" '
            .changes[$slug] = ((.changes[$slug] // {}) + {discovery_path: $dp})
        ' "$state_file" 2>/dev/null)" || return 0
        printf '%s\n' "$tmp" > "$state_file"
    else
        jq -n --arg slug "$slug" --arg dp "$discovery_path" '{
            openspec_surface: "none",
            verification_seen: false,
            verification_at: null,
            changes: {($slug): {discovery_path: $dp}}
        }' > "$state_file" 2>/dev/null || return 0
    fi
}
```

Key properties:
- Merges `discovery_path` into existing change entry without overwriting other fields (design_path, plan_path, etc.)
- Creates the state file and change entry if neither exists (DISCOVER runs before DESIGN, so state may not exist yet)
- Fail-open on jq errors (consistent with all other helpers)

### 4. openspec-ship Extracts Hypotheses into Session State

New Step 7a-bis in `skills/openspec-ship/SKILL.md`, inserted immediately before Step 7b (Archive Intent Artifacts). At this point, Step 2 has already read session state (including `discovery_path`), and the discovery artifact is still at its live `docs/plans/` path — archival to `docs/plans/archive/` happens in Step 7b after this extraction:

**When:** `discovery_path` exists in session state AND the file at that path is readable.

**Action:**
1. Read the `## Hypotheses` section from the discovery artifact
2. Parse each `### H<N>:` entry, extracting the four structured fields (Metric, Baseline, Target, Window) and the description
3. Write to session state as `changes.<slug>.hypotheses`:

```json
[
  {
    "id": "H1",
    "description": "We believe X will Y",
    "metric": "checkout_completion_rate",
    "baseline": "unknown",
    "target": "increase",
    "window": "2 weeks post-ship"
  }
]
```

**When `discovery_path` is absent or file is unreadable:** Skip silently. `hypotheses` stays null in state. This covers sessions that entered at DEBUG or skipped discovery.

**Why here:** openspec-ship already reads the design artifact for the divergences report (Step 7c). The discovery artifact is still at its live path at this point — archival happens after extraction. Extracting here means the baseline writer has zero filesystem dependencies.

### 5. New `write-learn-baseline` SHIP Composition Step

New terminal step in the SHIP composition sequence, firing after `finishing-a-development-branch`:

```json
{
  "step": "write-learn-baseline",
  "purpose": "Write learn baseline for outcome-review. Fires only after a ship event (merge or PR)."
}
```

**Ship detection logic:**

| Signal | Meaning |
|---|---|
| Current branch is main/master AND feature branch no longer exists | Option 1 — merge local |
| `gh pr list --head <feature-branch>` returns a PR URL | Option 2 — PR created |
| Current branch is still the feature branch AND no PR exists | Option 3 — keep (no ship) |
| Feature branch deleted AND not on main | Option 4 — discard (no ship) |

**On ship detected, write** `~/.claude/.skill-learn-baselines/<slug>.json`:

```json
{
  "schema_version": 1,
  "slug": "feature-name",
  "shipped_at": "2026-04-17T14:00:00Z",
  "ship_method": "merge_local",
  "pr_url": null,
  "branch": "feat/feature-name",
  "discovery_path": "docs/plans/archive/2026-04-17-feature-name-discovery.md",
  "design_path": "docs/plans/archive/2026-04-17-feature-name-design.md",
  "hypotheses": [
    {
      "id": "H1",
      "description": "We believe X will Y",
      "metric": "checkout_completion_rate",
      "baseline": "unknown",
      "target": "increase",
      "window": "2 weeks post-ship"
    }
  ],
  "jira_ticket": null
}
```

Fields:
- `hypotheses` — denormalized snapshot from session state (copied, not referenced). Survives file moves and archive reorganization.
- `ship_method` — `"merge_local"` or `"pull_request"`. Determines whether outcome-review should check PR merge status before treating as shipped.
- `pr_url` — populated for Option 2, null for Option 1.
- `discovery_path` and `design_path` — archived paths for human reference. Not consumed programmatically by outcome-review (it uses the denormalized hypotheses).
- `jira_ticket` — populated from session state if Atlassian MCP was used during discovery, null otherwise.

**On no ship detected:** Skip silently. No baseline file written.

### 6. outcome-review Consumes Baseline with Hypothesis Validation

Changes to `skills/outcome-review/SKILL.md`:

**Step 2 (Identify the Feature):** Already looks for `~/.claude/.skill-learn-baselines/`. No change to lookup logic.

**Step 3 (Gather Metrics):** When the baseline has non-null `hypotheses`, use the `metric` field from each hypothesis to guide PostHog queries (Tier 1) or to ask the user for specific metrics (Tier 2). This replaces the generic "query adoption metrics" with targeted queries.

**Step 4 (Synthesize Report):** Add a Hypothesis Validation section when hypotheses are present:

```markdown
**Hypothesis Validation:**
| ID | Hypothesis | Metric | Baseline | Target | Actual | Status |
|----|-----------|--------|----------|--------|--------|--------|
| H1 | X will Y  | checkout_rate | unknown | increase | +12% | Confirmed |
| H2 | Z reduces W | error_count | 45/day | decrease | 52/day | Not confirmed |
```

Status values: `Confirmed`, `Not confirmed`, `Inconclusive` (insufficient data or window not elapsed), `Partially confirmed` (directionally correct but below target).

**When `hypotheses` is null:** Fall back to existing generic metrics flow. No behavioral change for sessions that skipped discovery.

## Superpowers Boundary

| Component | Owner | Our change |
|---|---|---|
| `product-discovery` SKILL.md | auto-claude-skills | **Edit** |
| `openspec-state.sh` | auto-claude-skills | **Edit** |
| `openspec-ship` SKILL.md | auto-claude-skills | **Edit** |
| `outcome-review` SKILL.md | auto-claude-skills | **Edit** |
| `default-triggers.json` | auto-claude-skills | **Edit** |
| `fallback-registry.json` | auto-claude-skills | **Edit** |
| `brainstorming` SKILL.md | Superpowers | **Untouched** |
| `writing-plans` SKILL.md | Superpowers | **Untouched** |
| `executing-plans` SKILL.md | Superpowers | **Untouched** |
| `finishing-a-development-branch` SKILL.md | Superpowers | **Untouched** |
| `verification-before-completion` SKILL.md | Superpowers | **Untouched** |
| `requesting-code-review` SKILL.md | Superpowers | **Untouched** |
| Routing hook logic, scoring, role-cap | auto-claude-skills | **Untouched** |

Zero Superpowers skill files are modified. Coupling points:
- Discovery artifact lands at `docs/plans/` where Superpowers skills already look
- Session state is invisible to Superpowers skills (they don't read it)
- `write-learn-baseline` detects `finishing-a-development-branch` outcome from git state, not from the skill's internals

## Acceptance Scenarios

**GIVEN** a user runs product-discovery and approves a brief with 2 hypotheses
**WHEN** the session completes through SHIP with a local merge (Option 1)
**THEN** a learn-baseline file exists at `~/.claude/.skill-learn-baselines/<slug>.json` containing both hypotheses with their structured fields, `ship_method: "merge_local"`, and a non-null `shipped_at`.

**GIVEN** a user runs the full SDLC loop and ships via PR (Option 2)
**WHEN** outcome-review is invoked weeks later with "how did <feature> perform"
**THEN** the outcome report includes a Hypothesis Validation table with one row per hypothesis from the baseline, and each row has an Actual value (from PostHog or manual input) and a Status assessment.

**GIVEN** a user runs through SHIP but picks Option 3 (keep branch) or Option 4 (discard)
**WHEN** the SHIP composition completes
**THEN** no learn-baseline file is written for that feature.

**GIVEN** a session that skipped product-discovery (e.g., direct bug fix entering at DEBUG)
**WHEN** openspec-ship runs and then write-learn-baseline fires
**THEN** `changes.<slug>.hypotheses` is null in session state. The baseline file (if ship detected) has `hypotheses: null`. outcome-review falls back to its existing generic metrics flow.

## Decision

Implement as described. The design threads a durable hypothesis artifact from DISCOVER through to LEARN using five targeted edits to existing auto-claude-skills files, one new composition step, and zero changes to Superpowers-owned skills.
