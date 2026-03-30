## ADDED Requirements

### Requirement: Per-cluster open-incident hours
compute-clusters.py MUST output a `total_open_hours` field per cluster computed as `sum(durations) / 3600` from actual incident durations.

#### Scenario: Flapping cluster with 50 five-minute incidents
- **WHEN** 50 incidents each lasting 5 minutes are processed
- **THEN** `total_open_hours` MUST equal 4.2

### Requirement: Zero-channel policy detection
compute-clusters.py MUST output a `zero_channel_policies` inventory-level array containing enabled policies with zero notification channels. Each entry MUST include `policy_name`, `policy_id`, `enabled`, `raw_incidents`, and `squad`.

#### Scenario: Policy with no notification channels
- **WHEN** an enabled policy has `notificationChannels: []`
- **THEN** it MUST appear in `zero_channel_policies` with correct `raw_incidents` count

### Requirement: Disabled-but-noisy policy detection
compute-clusters.py MUST output a `disabled_but_noisy_policies` inventory-level array containing disabled policies with `raw_incidents > 0`. Each entry MUST include `policy_name`, `policy_id`, `raw_incidents`, and `squad`.

#### Scenario: Disabled policy with active incidents
- **WHEN** a disabled policy has 5 incidents in the analysis window
- **THEN** it MUST appear in `disabled_but_noisy_policies` with `raw_incidents: 5`

### Requirement: Silent policy count
compute-clusters.py MUST output `silent_policy_count` (enabled policies not appearing in any cluster) and `silent_policy_total` (total enabled policies).

#### Scenario: One active policy with no incidents
- **WHEN** 1 of 2 policies has no incidents
- **THEN** `silent_policy_count` MUST equal 1 and `silent_policy_total` MUST equal the enabled policy count

### Requirement: Condition type breakdown
compute-clusters.py MUST output `condition_type_breakdown` as a dict mapping condition type names to counts across all policies.

#### Scenario: Two conditionThreshold policies
- **WHEN** both policies use `conditionThreshold`
- **THEN** `condition_type_breakdown.conditionThreshold` MUST equal 2

## CHANGED Requirements

### Requirement: Investigate template preserves config diffs
The Investigate Per-Item Template MUST include a conditional Proposed Config Diff section. The section MUST only appear when evidence basis is `measured` or `structural` and a config diff is derivable. The section MUST include Gate Blocker and To Upgrade fields.

#### Scenario: Structural finding demoted from Do Now
- **WHEN** an item has structural evidence and a derivable config change but lacks a named owner
- **THEN** the Investigate template MUST render the Proposed Config Diff section with the full current/proposed/derivation table

### Requirement: Mandatory silent policy cleanup trigger
SKILL.md MUST include a Mandatory Needs Decision Triggers section. When `silent_policy_total > 0` and `silent_policy_count / silent_policy_total > 0.5`, the report MUST include a Silent Policy Cleanup Needs Decision item.

### Requirement: Deterministic inventory health
The Dead/Orphaned Config and Inventory Health report sections MUST read from compute-clusters output fields. They MUST NOT be computed ad-hoc during report generation.
