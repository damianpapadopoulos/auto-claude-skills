---
name: agent-team-review
description: Multi-perspective parallel code review with specialist reviewers for security, quality, and spec compliance.
---

# Agent Team Review

## Overview

Parallel code review using agent teams. The lead spawns 2-3 reviewer teammates, each with a different review lens. Reviewers investigate independently, then the lead synthesizes findings into a unified review report.

**Prerequisite:** Implementation must be complete (all tasks marked done). Activates for larger implementations (5+ files changed).

## Sizing Rule

| Condition | Action |
|-----------|--------|
| < 5 files changed | Use single-agent requesting-code-review |
| 5+ files changed | Spawn reviewer team |

## Reviewer Composition

| Teammate | Lens | Focus |
|----------|------|-------|
| `security-reviewer` | Security | Auth flows, input validation, secrets, OWASP risks |
| `quality-reviewer` | Code quality | Patterns, maintainability, test coverage, edge cases |
| `spec-reviewer` | Spec compliance | Does implementation match the design doc and plan? |

## Protocol

### 1. Preparation

```
TeamCreate("code-review")

Gather context:
- Design doc from docs/plans/*-design.md
- Implementation plan from docs/plans/*.md
- Git diff: git diff {base_sha}...HEAD
- List of files changed
```

### 2. Spawn Reviewers

Each reviewer gets:
- The full diff
- The design doc
- Their specific review lens instructions
- The communication contract

### 3. Parallel Review

Reviewers work independently using Read, Grep, and analysis tools. They do NOT modify any files.

### 4. Lead Synthesis

After all reviewers report findings:

1. Group findings by severity (blocking → warning → suggestion)
2. Deduplicate overlapping findings
3. Present unified report to user

### 5. Verdict Routing

| Verdict | Action |
|---------|--------|
| `blocking_issues` | TeamDelete → return to IMPLEMENT → fix issues → re-review |
| `suggestions_only` | TeamDelete → proceed to SHIP |
| `clean` | TeamDelete → proceed to SHIP |

## Communication Contract

### Reviewer → Lead: Individual Finding

```json
{
  "type": "review_finding",
  "severity": "blocking | warning | suggestion",
  "file": "src/auth.ts",
  "line": 42,
  "category": "security | quality | spec",
  "description": "SQL injection via unsanitized input",
  "suggestion": "Use parameterized queries"
}
```

### Lead → User: Review Summary

```json
{
  "type": "review_summary",
  "blocking": [],
  "warnings": [],
  "suggestions": [],
  "verdict": "blocking_issues | clean | suggestions_only"
}
```

## Reviewer Spawn Templates

### Security Reviewer
```
Task tool (general-purpose):
  name: "security-reviewer"
  team_name: "code-review"
  prompt: |
    You are a security reviewer examining code changes.

    ## Your Lens: Security

    Focus on:
    - Authentication and authorization flows
    - Input validation and sanitization
    - Secrets management (hardcoded keys, tokens, passwords)
    - OWASP Top 10 risks
    - SQL/NoSQL injection
    - XSS and CSRF vulnerabilities
    - Dependency vulnerabilities
    - Error messages leaking sensitive information

    ## Context
    Design doc: {design_doc}
    Diff: {diff}
    Files changed: {files}

    ## Rules
    - Read-only: do NOT modify any files
    - Report each finding using the review_finding JSON schema
    - Send all findings to the lead via SendMessage
    - Be specific: include file path, line number, and remediation
```

### Quality Reviewer
```
Task tool (general-purpose):
  name: "quality-reviewer"
  team_name: "code-review"
  prompt: |
    You are a code quality reviewer examining code changes.

    ## Your Lens: Code Quality

    Focus on:
    - Code patterns and consistency
    - Naming clarity and accuracy
    - Error handling completeness
    - Test coverage and test quality
    - Edge cases not covered
    - DRY violations
    - YAGNI violations (over-engineering)
    - Performance concerns
    - Maintainability

    ## Context
    Design doc: {design_doc}
    Diff: {diff}
    Files changed: {files}

    ## Rules
    - Read-only: do NOT modify any files
    - Report each finding using the review_finding JSON schema
    - Send all findings to the lead via SendMessage
    - Distinguish between blocking issues and suggestions
```

### Spec Compliance Reviewer
```
Task tool (general-purpose):
  name: "spec-reviewer"
  team_name: "code-review"
  prompt: |
    You are a spec compliance reviewer examining code changes.

    ## Your Lens: Spec Compliance

    Focus on:
    - Does implementation match the design doc?
    - Does implementation match the plan tasks?
    - Are all planned features implemented?
    - Are there unplanned features (scope creep)?
    - Do interfaces match the specified contracts?
    - Are edge cases from the spec handled?

    ## Context
    Design doc: {design_doc}
    Plan: {plan}
    Diff: {diff}
    Files changed: {files}

    ## Rules
    - Read-only: do NOT modify any files
    - Report each finding using the review_finding JSON schema
    - Send all findings to the lead via SendMessage
    - Flag both missing features AND unplanned additions
```

## Integration

- **Falls back to:** requesting-code-review for < 5 files
- **Protected by:** cozempic (auto-installed at SessionStart)
- **Heartbeat:** teammate-idle-guard.sh prevents false idle nudges
- **Follows:** agent-team-execution or single-agent implementation
