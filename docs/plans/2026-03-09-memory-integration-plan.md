# Memory Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add CLAUDE.md to auto-claude-skills for dogfooding, and add a methodology hint that nudges users toward `/revise-claude-md` during convention-changing sessions.

**Architecture:** Two independent changes: (1) a new `CLAUDE.md` file at project root, (2) a new entry in the `methodology_hints` array in `config/default-triggers.json`. No new hooks, no new state files.

**Tech Stack:** Markdown, JSON, bash (test suite)

---

### Task 1: Add CLAUDE.md to project root

**Files:**
- Create: `CLAUDE.md`

**Step 1: Write CLAUDE.md**

```markdown
# auto-claude-skills

Claude Code plugin for automatic skill routing based on prompt intent and SDLC phase.

## Commands

| Command | Description |
|---------|-------------|
| `bash tests/run-tests.sh` | Run all test suites |
| `bash tests/test-routing.sh` | Test skill routing engine |
| `bash tests/test-registry.sh` | Test registry building and merging |
| `bash tests/test-context.sh` | Test context formatting and phase composition |
| `bash -n hooks/<name>.sh` | Syntax-check a hook (no execution) |
| `SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh` | Debug routing with explanation output |

## Architecture

- **Two main hooks**: `session-start-hook.sh` builds the skill registry at session start; `skill-activation-hook.sh` scores and routes on every prompt.
- **Registry**: Cached at `~/.claude/.skill-registry-cache.json`. Merged from `config/default-triggers.json` + plugin discoveries + `~/.claude/skill-config.json` overrides.
- **Scoring**: Regex trigger match → base score + priority + name bonus + composition bonus → role-cap selection (max 1 process, 2 domain, 1 workflow).
- **Output**: JSON via `hookSpecificOutput` on stdout. Hooks fail-open (exit 0 on error).

## Style

- Bash 3.2 compatible (macOS `/bin/bash`). No associative arrays.
- 50ms hook budget. Minimize jq forks — batch into single calls.
- Field separator: `\x1f` (US). Intra-field delimiter: `\x01` (SOH). Never `\n` inside fields.
- Commit messages: `<type>: <description>` (fix, feat, docs, test, refactor).

## Gotchas

- `[[ $P =~ $trigger ]]` returns exit 1 on regex non-match — never use `set -e` in routing hooks.
- jq is optional at runtime; session-start falls back to `config/fallback-registry.json`.
- Concurrent sessions share `~/.claude/` — session-token scoping prevents counter races.
- `CLAUDE_PLUGIN_ROOT` from env; fallback: `$(cd "$(dirname "$0")/.." && pwd)`.
- `docs/plans/` is gitignored — use `git add -f` for design docs.
```

**Step 2: Verify the file renders correctly**

Run: `head -40 CLAUDE.md`
Expected: The full file content renders as expected.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md for project context"
```

---

### Task 2: Add methodology hint for CLAUDE.md maintenance

**Files:**
- Modify: `config/default-triggers.json` (in `methodology_hints` array, after the last entry around line 482)
- Modify: `tests/test-routing.sh` (add test for the new hint)

**Step 1: Write the failing test**

Add a new test function in `tests/test-routing.sh` after `test_phase_scoped_methodology_hints` (around line 847). The test registry used by tests already includes methodology hints from the `install_registry` helper — but for this test we need the new hint in the registry. The simplest approach: add the hint to the inline test registry at the `methodology_hints` arrays in `test-routing.sh`.

First, add the hint entry to both test registries (the full one at ~line 256 and the compact one at ~line 525):

In the full registry (~line 256), after the existing hints:
```json
,
{
  "name": "claude-md-maintenance",
  "triggers": ["(refactor|restructur|new.convention|architecture.change|reorganize|rename.*(module|package|directory))"],
  "trigger_mode": "regex",
  "hint": "CLAUDE.MD: If this session changed project conventions or structure, consider /revise-claude-md",
  "skill": "claude-md-improver",
  "phases": ["IMPLEMENT", "SHIP"]
}
```

In the compact registry (~line 525), after existing hints:
```json
,
{"name": "claude-md-maintenance", "triggers": ["(refactor|restructur|new.convention|architecture.change|reorganize|rename.*(module|package|directory))"], "trigger_mode": "regex", "hint": "CLAUDE.MD: If this session changed project conventions or structure, consider /revise-claude-md", "skill": "claude-md-improver", "phases": ["IMPLEMENT", "SHIP"]}
```

Then add the test function:
```bash
test_claude_md_maintenance_hint() {
    echo "-- test: claude-md maintenance hint --"
    setup_test_env
    install_registry

    # "refactor the authentication module" triggers systematic-debugging? No —
    # "refactor" triggers brainstorming (DESIGN phase). But the hint only fires
    # in IMPLEMENT/SHIP. So we need a prompt that lands in IMPLEMENT phase
    # AND matches the hint trigger.
    #
    # "implement the refactoring plan" → triggers executing-plans (IMPLEMENT)
    # and matches "refactor" in the hint trigger.
    local output context
    output="$(run_hook "implement the refactoring plan for the auth module")"
    context="$(extract_context "${output}")"
    assert_contains "claude-md hint fires in IMPLEMENT phase" "CLAUDE.MD" "${context}"

    # "design a new refactored architecture" → triggers brainstorming (DESIGN phase)
    # Hint should NOT fire because DESIGN is not in the hint's phases.
    output="$(run_hook "design a new refactored architecture")"
    context="$(extract_context "${output}")"
    assert_not_contains "claude-md hint suppressed in DESIGN phase" "CLAUDE.MD" "${context}"

    # When claude-md-improver is already selected as a skill, hint is suppressed
    output="$(run_hook "improve the claude.md and refactor conventions")"
    context="$(extract_context "${output}")"
    assert_not_contains "claude-md hint suppressed when skill selected" "CLAUDE.MD" "${context}"

    teardown_test_env
}
```

**Step 2: Run the test to verify it fails**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "claude-md maintenance"`
Expected: FAIL — hint not found in output (hint doesn't exist in production config yet).

**Step 3: Add the methodology hint to default-triggers.json**

Add to `config/default-triggers.json` in the `methodology_hints` array (after the last entry, before the closing `]`):

```json
,
{
  "name": "claude-md-maintenance",
  "triggers": [
    "(refactor|restructur|new.convention|architecture.change|reorganize|rename.*(module|package|directory))"
  ],
  "trigger_mode": "regex",
  "hint": "CLAUDE.MD: If this session changed project conventions or structure, consider /revise-claude-md",
  "skill": "claude-md-improver",
  "phases": [
    "IMPLEMENT",
    "SHIP"
  ]
}
```

**Step 4: Update the fallback registry**

Run: `bash hooks/session-start-hook.sh` to regenerate, then copy the methodology_hints section to `config/fallback-registry.json`. Or manually add the same entry to the fallback file.

Actually — check if the fallback registry is auto-generated or manually maintained:

Run: `head -5 config/fallback-registry.json`

If manually maintained, add the same hint entry. If auto-generated, regenerate it.

**Step 5: Run the test to verify it passes**

Run: `bash tests/test-routing.sh 2>&1 | grep -A2 "claude-md maintenance"`
Expected: All three assertions PASS.

**Step 6: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass. No regressions.

**Step 7: Commit**

```bash
git add config/default-triggers.json config/fallback-registry.json tests/test-routing.sh
git commit -m "feat: add methodology hint for CLAUDE.md maintenance"
```

---

### Task 3: Verify end-to-end integration

**Files:** None (manual verification)

**Step 1: Verify hint fires correctly with full registry**

Run: `SKILL_EXPLAIN=1 echo '{"prompt":"implement the refactoring plan for the auth module"}' | bash hooks/skill-activation-hook.sh 2>&1`
Expected: Output includes `CLAUDE.MD:` hint text.

**Step 2: Verify hint does NOT fire in wrong phase**

Run: `echo '{"prompt":"design a new refactored architecture"}' | bash hooks/skill-activation-hook.sh 2>&1`
Expected: Output does NOT include `CLAUDE.MD:`.

**Step 3: Final commit (if any fixes needed)**

If no fixes needed, skip. Otherwise fix and commit:
```bash
git add -A
git commit -m "fix: address integration issues from memory-integration plan"
```
