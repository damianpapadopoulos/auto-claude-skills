# README — Delta

## ADDED Requirements

### Requirement: Decision-Funnel Structure
README sections SHALL be ordered as a decision funnel for first-time visitors evaluating the plugin.

#### Scenario: Visitor scans README
Given a GitHub visitor landing on the repository
When they read the README top-to-bottom
Then they encounter sections in this order: what it is, what it does, examples, how it works, install, integrations, configuration, diagnostics, boundaries, uninstall

### Requirement: SDLC Phase Table
The "What It Does" section SHALL include a table showing what the plugin does at each development phase.

#### Scenario: Visitor wants to understand phase behavior
Given a visitor reading the "What It Does" section
When they look at the phase table
Then they see 6 rows (DESIGN, PLAN, IMPLEMENT, REVIEW, SHIP, DEBUG) with verified behavioral descriptions

### Requirement: Example Prompts
The README SHALL include three concrete examples showing prompt-to-phase-to-behavior routing.

#### Scenario: Visitor wants to see routing in action
Given a visitor reading the "Example Prompts" section
When they read each example
Then they see the prompt, the detected phase, and which skills activate

### Requirement: Boundary Setting
The README SHALL include a "What It Is Not" section clarifying what the plugin does not do.

#### Scenario: Visitor wonders if this replaces their IDE/ticketing/deployment tool
Given a visitor reading the "What It Is Not" section
When they check each boundary statement
Then they understand the plugin is a workflow orchestrator, not a replacement for external tools

## CHANGED Requirements

### Requirement: Install Section
Prerequisites (Claude Code CLI, jq) are folded into the Install section rather than appearing as a standalone section.

#### Scenario: Visitor wants to install
Given a visitor reading the Install section
When they look for prerequisites
Then they find them listed inline before the install commands

### Requirement: Integrations Listing
Companion plugins and MCP integrations are grouped by category instead of listed with exact counts.

#### Scenario: Visitor wants to know what integrations are available
Given a visitor reading the Optional Integrations section
When they scan the categories
Then they see core workflow plugins, MCP/context sources, phase enhancers, and Atlassian — without brittle counts

## REMOVED Requirements

### Requirement: Fallthrough Assessment Claim
The claim that unmatched development prompts trigger "Claude assesses from context" has been removed.

#### Scenario: Zero-match prompt
Given a prompt that matches no trigger patterns
When the routing engine processes it
Then no output is produced (silent exit), not a context-based assessment
