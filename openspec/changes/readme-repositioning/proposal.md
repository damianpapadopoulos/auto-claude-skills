# Proposal: README Repositioning

## Problem Statement
The README was written from the inside out — leading with install commands and internal implementation jargon. GitHub/marketplace visitors evaluating the plugin had no clear way to understand what it does, why they'd want it, or where its boundaries are within 30 seconds of landing on the page.

## Proposed Solution
Rewrote README.md as a decision-funnel product page with 10 sections ordered by visitor questions: what it is → what it does → examples → how it works → install → integrations → config → diagnostics → boundaries → uninstall. Added an SDLC phase table, 3 example prompts showing routing behavior, and a "What It Is Not" boundary-setting section.

## Out of Scope
- No code, hook, config, or type changes
- No changes to CLAUDE.md or contributor documentation
- No new features or behavioral changes to the plugin itself
