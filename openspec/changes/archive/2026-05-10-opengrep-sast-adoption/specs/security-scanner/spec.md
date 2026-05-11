## ADDED Requirements

### Requirement: Preferred SAST binary detection
The security-scanner skill MUST detect `opengrep` first and fall back to `semgrep` when opengrep is absent. The detected binary MUST be used for all SAST scan invocations.

#### Scenario: Opengrep preferred when both installed
- **GIVEN** both `opengrep` and `semgrep` are on PATH
- **WHEN** the agent invokes the security-scanner skill during REVIEW
- **THEN** the resolved `$SAST_BIN` MUST point to the `opengrep` binary
- **AND** Step 2 invocations MUST use `"$SAST_BIN"` rather than a hardcoded binary name

#### Scenario: Semgrep fallback when opengrep absent
- **GIVEN** `semgrep` is on PATH but `opengrep` is not
- **WHEN** the agent invokes the security-scanner skill during REVIEW
- **THEN** the resolved `$SAST_BIN` MUST point to the `semgrep` binary
- **AND** the skill MUST proceed without warning the user about the absence of opengrep

#### Scenario: Graceful degradation with neither
- **GIVEN** neither `opengrep` nor `semgrep` is on PATH
- **WHEN** the agent invokes the security-scanner skill
- **THEN** `$SAST_BIN` MUST resolve to an empty string
- **AND** the skill MUST fall back to LLM-only review and recommend installing opengrep first, semgrep as fallback

### Requirement: JSON contract preservation across SAST binaries
The security-scanner skill SHALL parse SAST JSON output using only fields that are byte-identical between opengrep and semgrep: `results[].check_id`, `results[].extra.severity`, `results[].path`, `results[].start.line`, and `results[].extra.message`.

#### Scenario: Byte-identical jq output on a fixture
- **GIVEN** a fixture file with a known Python code-execution-sink finding
- **WHEN** the skill's jq pipeline runs against both `opengrep scan --json --config auto` and `semgrep scan --json --config auto` output
- **THEN** the parsed `{rule, severity, file, line, message}` records MUST be identical

#### Scenario: Same registry for --config auto
- **GIVEN** both binaries are invoked with `--config auto`
- **WHEN** they fetch the rule registry
- **THEN** they MUST resolve to the same `semgrep.dev/c/auto` endpoint

### Requirement: Capability detection emits opengrep field
The session-start hook MUST detect `opengrep` availability and include an `opengrep=` field in the `SECURITY_CAPS` line. The existing `semgrep=`, `trivy=`, and `gitleaks=` fields MUST remain emitted to preserve backwards compatibility.

#### Scenario: Both SAST binaries detected
- **GIVEN** both `opengrep` and `semgrep` are installed at session start
- **WHEN** the session-start hook runs
- **THEN** the `Security tools:` line MUST contain both `semgrep=true` and `opengrep=true`

#### Scenario: Only opengrep detected
- **GIVEN** `opengrep` is installed but `semgrep` is not
- **WHEN** the session-start hook runs
- **THEN** the `Security tools:` line MUST contain `semgrep=false, opengrep=true`

### Requirement: Routing trigger and hint copy include opengrep
The `deterministic-security-scan` methodology hint MUST trigger on prompts mentioning `opengrep` in addition to existing keywords, and the hint and purpose copy MUST reference opengrep alongside semgrep and trivy. Both `config/default-triggers.json` and `config/fallback-registry.json` MUST be updated identically.

#### Scenario: Prompt mentioning opengrep activates the hint
- **GIVEN** a prompt containing the word `opengrep` during REVIEW phase
- **WHEN** the activation hook processes methodology hints
- **THEN** the `deterministic-security-scan` hint MUST fire

#### Scenario: Config parity preserved
- **GIVEN** the security-scan trigger regex and hint/purpose copy in both config files
- **WHEN** `test_fallback_registry_parity` runs
- **THEN** the assertion MUST pass — both files contain the same `opengrep`-aware copy
