# Delta Spec: skill-routing — local-adjustability hint

## ADDED Requirements

### Requirement: Evidence-gated local-override hint at session start

The session-start hook SHALL append a single advisory banner line pointing to the local override mechanism (`~/.claude/skill-config.json`, the zero-match log, and `SKILL_EXPLAIN=1`) when and only when the previous session recorded at least 5 zero-match prompts, at least 8 total prompts, and a zero-match rate of at least 30%. The hint MUST be suppressed when a cooldown marker younger than 7 days exists, or when the user's `skill-config.json` already contains per-skill overrides. Emitting the hint SHALL touch the cooldown marker. Every failure mode (unreadable or non-numeric counters, jq absent or erroring, marker operations failing) MUST suppress the hint without affecting the rest of the banner (fail-open).

#### Scenario: High miss rate fires the hint once

- GIVEN the previous session recorded 5 zero-matches across 10 prompts
- AND no cooldown marker exists and `skill-config.json` has no per-skill overrides
- WHEN the session-start hook runs
- THEN the banner SHALL contain one routing-hint line naming 5, 10, and the rate
- AND the cooldown marker SHALL exist afterwards

#### Scenario: Chatty session does not fire

- GIVEN the previous session recorded 5 zero-matches across 50 prompts (10%)
- WHEN the session-start hook runs
- THEN the banner SHALL NOT contain a routing-hint line

#### Scenario: Existing overrides suppress the hint

- GIVEN qualifying friction evidence AND `skill-config.json` containing at least one per-skill override
- WHEN the session-start hook runs
- THEN the banner SHALL NOT contain a routing-hint line

#### Scenario: Fresh cooldown suppresses the hint

- GIVEN qualifying friction evidence AND a cooldown marker touched less than 7 days ago
- WHEN the session-start hook runs
- THEN the banner SHALL NOT contain a routing-hint line
- AND the marker's mtime SHALL be unchanged
