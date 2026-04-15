## MODIFIED Requirements

### Requirement: Skill Structure — Spine and Reference Separation
SKILL.md MUST keep all 13 behavioral constraints, the investigation stage/step flow, and the Step 5 hypothesis formulation spine inline. Reference-lookup material (error taxonomy tables, exit code guides, conditional sub-playbook procedures) SHOULD be extracted to `references/` files with compressed pointer paragraphs in the spine.

#### Scenario: Agent follows CrashLoopBackOff triage after extraction
- **WHEN** an agent encounters `crash_loop_detected` signal during investigation
- **THEN** the SKILL.md pointer MUST contain enough routing terms (exit codes, redirect conditions) for the agent to decide whether to read `references/deep-dive-branches.md`, and the reference file MUST contain the full triage procedure

#### Scenario: Agent classifies error signals after taxonomy extraction
- **WHEN** an agent extracts key signals during Step 2
- **THEN** the SKILL.md pointer MUST name all three tiers and state "Investigate Tier 1 first", and `references/error-taxonomy.md` MUST contain the full taxonomy table with examples and baseline verification rules

### Requirement: Word Count Guard
SKILL.md MUST NOT exceed 11,500 words. The structural guard in `tests/test-incident-analysis-content.sh` MUST enforce this threshold.

#### Scenario: Word count guard prevents regression
- **WHEN** `wc -w < skills/incident-analysis/SKILL.md` is run
- **THEN** the result MUST be at or below 11,500

### Requirement: Stage-Transition Flowchart
SKILL.md MUST include a `dot` flowchart showing the 6-stage pipeline (MITIGATE, CLASSIFY, INVESTIGATE, EXECUTE, VALIDATE, POSTMORTEM) with re-entry paths (CLASSIFY low-confidence → INVESTIGATE, VALIDATE failed → INVESTIGATE).

#### Scenario: Flowchart shows re-entry paths
- **WHEN** an agent reads the Stage Flow section
- **THEN** the flowchart MUST show CLASSIFY → INVESTIGATE and VALIDATE → INVESTIGATE edges with descriptive labels

### Requirement: Behavioral Navigation Chain Tests
Tests MUST verify the spine-to-pointer-to-reference chain is intact for extracted content: (1) SKILL.md pointer references the target file, (2) the reference file contains the detailed procedure.

#### Scenario: Navigation chain test catches broken pointer
- **WHEN** a pointer in SKILL.md references a reference file
- **THEN** tests MUST assert both that the pointer text contains the file path AND that the reference file contains the expected procedure content
