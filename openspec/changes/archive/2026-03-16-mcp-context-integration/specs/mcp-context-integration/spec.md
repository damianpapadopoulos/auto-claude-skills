# MCP Context Integration — Delta

## ADDED Requirements

### Requirement: MCP Server Detection Fallback
The session-start hook MUST detect MCP servers registered via `claude mcp add` in addition to marketplace-installed plugins.

#### Scenario: User-scoped MCP server detection
Given forgetful is registered as a user-scoped MCP server in ~/.claude.json
When the session-start hook runs
Then forgetful_memory capability is set to true in the registry cache

#### Scenario: Project-scoped MCP server detection
Given serena is registered as a project-scoped MCP server in ~/.claude.json
When the session-start hook runs
Then serena capability is set to true in the registry cache

#### Scenario: Plugin detection not downgraded
Given serena is detected as true via plugin array
When the MCP fallback runs and serena is not in ~/.claude.json
Then serena remains true (never downgraded)

### Requirement: Correct Tool Name References
Phase and tier docs MUST reference actual MCP tool names, not fictional ones.

#### Scenario: Serena tool name in phase docs
Given the model reads a phase doc referencing serena
When the doc mentions dependency mapping
Then it references find_referencing_symbols (not cross_reference)

#### Scenario: Forgetful tool name in phase docs
Given the model reads a phase doc referencing forgetful
When the doc mentions memory querying
Then it references the intent ("Query Forgetful") with a pointer to the tier doc for mechanics

### Requirement: Historical Truth in All Code Phases
Implementation and Code Review phases MUST include Historical Truth (Forgetful/flat-file) guidance.

#### Scenario: Implementation phase workaround check
Given the model enters the Implementation phase
When it begins implementing a file
Then it checks for known workarounds via Forgetful (or CLAUDE.md/learnings.md fallback) before coding

#### Scenario: Code Review convention check
Given the model enters the Code Review phase
When a reviewer suggests an architectural change
Then it checks Forgetful (or CLAUDE.md fallback) for prior conventions before accepting

### Requirement: Serena Nudge Guard
A PreToolUse hook MUST hint when Grep is used for symbol lookups while serena is available.

#### Scenario: CamelCase symbol grep triggers nudge
Given serena=true in the registry cache
When the model calls Grep with pattern "MyClassName"
Then the hook emits an advisory hint suggesting find_symbol

#### Scenario: Complex regex does not trigger nudge
Given serena=true in the registry cache
When the model calls Grep with pattern "log.*Error|warn"
Then the hook does not emit any hint

### Requirement: Memory Consolidation Enforcement
Commit-time and session-end enforcement MUST remind about memory consolidation.

#### Scenario: Commit without consolidation marker
Given the model is in SHIP phase
When it attempts git commit and no fresh consolidation marker exists
Then openspec-guard emits a consolidation warning

#### Scenario: Session end without consolidation
Given the session is ending
When no fresh consolidation marker exists
Then consolidation-stop.sh emits a tier-specific reminder (Forgetful/chub/learnings.md)

### Requirement: Delta Spec Sync Enforcement
Commit-time enforcement MUST warn about unsynced archived delta specs.

#### Scenario: Archived delta without canonical
Given an archived change has a delta spec for capability "foo"
When no canonical spec exists at openspec/specs/foo/spec.md
Then openspec-guard emits a delta sync warning

#### Scenario: Canonical older than delta
Given an archived delta spec is newer than its canonical spec
When the model attempts git commit in SHIP phase
Then openspec-guard emits a delta sync warning
