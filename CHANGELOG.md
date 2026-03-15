# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Phase-aware RED FLAGS for DESIGN, PLAN, IMPLEMENT, and REVIEW phases
- Phase-enforcement methodology hint for DESIGN/PLAN phases
- REVIEW 3-step sequence (requesting → agent-team → receiving code review)
- IMPLEMENT sequence entries for worktree and finishing-branch requirements
- Required role (`role: "required"`) for cap-bypassing skills
- Composition parallel entries for TDD (IMPLEMENT/DEBUG) and security-scanner (REVIEW)
- SDLC chain bridging: end-to-end 7-step composition chain (DESIGN → SHIP)
- IMPLEMENT stickiness rule for explicit continuation language

### Changed
- Narrowed brainstorming triggers to boundary-safe generic verbs
- Narrowed design-debate triggers to tradeoff/comparison language only
- Narrowed agent-team-execution triggers to team-specific language
- Reclassified using-git-worktrees to required role (trigger-gated)
- Reclassified agent-team-review to required role (condition-gated)
- Updated requesting-code-review description to reflect subagent dispatch
- Updated executing-plans description to include worktree and finishing requirements
- Relaxed hook budget from 50ms to <200ms

### Fixed
- Composition state guard against _current_idx=-1 corruption
- IMPLEMENT stickiness restricted to continuation language (respects HARD-GATE)
- Guard stickiness injection against disabled/missing executing-plans
- Zero-match log prompt truncation (200 chars) and byte-size rotation (50KB)
- TDD fallback grep replaced with boolean flag (perf)
- Fallback registry parity with production config
- Test fixture parity for requesting-code-review priority
