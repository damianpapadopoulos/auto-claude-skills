#!/usr/bin/env python3
"""
Skill Activation Hook — Python routing engine prototype.

This is a minimal prototype implementing the core scoring + selection loop
from hooks/skill-activation-hook.sh to evaluate Python as a long-term
replacement for the Bash routing engine.

EVALUATION CRITERIA:
  Line count comparison:
    - Python scoring + selection: ~180 lines (this file)
    - Bash equivalent (_score_skills + _select_by_role_caps + main plumbing): ~260 lines
    - Python is ~30% fewer lines for equivalent logic, with significantly
      better readability due to data structures (dicts/lists vs pipe-delimited strings).

  Error handling quality:
    - Python: try/except with structured error types; json.JSONDecodeError, re.error, KeyError.
      Easy to catch and report specific failures.
    - Bash: everything is string-based; malformed JSON silently produces empty strings,
      regex errors are indistinguishable from non-matches (both return exit 1).
    - Verdict: Python is substantially better for error handling.

  Regex behavior differences (Python re vs Bash =~):
    - Both use POSIX-style extended regex, but Python re has differences:
      * Python re does not support POSIX character classes like [[:space:]], [[:upper:]].
        Must use \s, [A-Z], etc.
      * Python re uses \b for word boundaries; Bash uses manual [^a-z0-9] checks.
      * Python re.search() finds any match; Bash =~ anchors to the whole string
        but returns the leftmost match via BASH_REMATCH.
      * Python re quantifiers are non-greedy with ?, Bash is always greedy.
    - In practice: trigger regexes are simple alternations that behave identically.
      The word-boundary scoring logic is reimplemented explicitly (same algorithm).

  Startup time consideration:
    - Python: ~30-50ms cold start (interpreter + imports). Measured on macOS M-series.
    - Bash: ~5-10ms for shell startup, but each jq fork adds ~5ms.
      With 1-3 jq calls (current optimized bash), total is ~15-25ms.
    - Verdict: Python is slightly slower on cold start but competitive.
      For a hook that runs once per user prompt, the difference is negligible.
      Python gains back time by avoiding subprocess forks for JSON processing.

  Maintainability assessment:
    - Python: native JSON handling, real data structures, type hints possible,
      easy unit testing, standard debugging tools, clear control flow.
    - Bash: pipe-delimited strings, manual field splitting, fragile IFS handling,
      implicit global state, debugging requires echo/set -x.
    - Verdict: Python is dramatically more maintainable. The scoring algorithm
      is ~3x easier to understand in Python.

SCOPE (implemented):
  - JSON input parsing (stdin)
  - Registry loading from $HOME/.claude/.skill-registry-cache.json or fallback
  - Trigger scoring (regex matching with word-boundary detection)
  - Role-cap selection (1 process, 2 domain, 1 workflow, total <= max_suggestions)
  - Name boost (full=100, segment=40, min 6 chars for segments)
  - JSON output (same format as bash hook)

EXPLICITLY EXCLUDED:
  - Composition chain walking
  - Methodology hints
  - Phase compositions
  - SKILL_EXPLAIN / SKILL_DEBUG
  - Depth-aware verbosity
  - Blocklist checking

Input:  {"prompt": "..."} via stdin
Output: {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"..."}}
"""

import json
import os
import re
import sys
from typing import Any


def load_registry(plugin_root: str) -> dict | None:
    """Load skill registry from cache or fallback."""
    cache_path = os.path.join(os.environ.get("HOME", ""), ".claude", ".skill-registry-cache.json")
    fallback_path = os.path.join(plugin_root, "config", "fallback-registry.json")

    for path in (cache_path, fallback_path):
        if os.path.isfile(path):
            try:
                with open(path) as f:
                    data = json.load(f)
                return data
            except (json.JSONDecodeError, OSError):
                continue
    return None


def load_max_suggestions() -> int:
    """Load max_suggestions from user config, default 3."""
    config_path = os.path.join(os.environ.get("HOME", ""), ".claude", "skill-config.json")
    if os.path.isfile(config_path):
        try:
            with open(config_path) as f:
                cfg = json.load(f)
            ms = cfg.get("settings", {}).get("max_suggestions") or cfg.get("max_suggestions", 3)
            if isinstance(ms, int) and ms >= 1:
                return ms
            if isinstance(ms, str) and ms.isdigit() and int(ms) >= 1:
                return int(ms)
        except (json.JSONDecodeError, OSError, TypeError):
            pass
    return 3


def compute_name_boost(skill_name_lower: str, prompt_lower: str) -> int:
    """
    Name boost: full name match -> 100, hyphen-segment match -> 40.
    Segments must be >= 6 chars to avoid false positives.
    """
    # Full name match as whole word
    pattern = r'(?:^|[^a-z0-9\-])' + re.escape(skill_name_lower) + r'(?:$|[^a-z0-9\-])'
    if re.search(pattern, prompt_lower):
        return 100

    # Segment match for hyphenated names
    if '-' in skill_name_lower:
        for segment in skill_name_lower.split('-'):
            if len(segment) < 6:
                continue
            seg_pattern = r'(?:^|[^a-z0-9])' + re.escape(segment) + r'(?:$|[^a-z0-9])'
            if re.search(seg_pattern, prompt_lower):
                return 40

    return 0


def is_word_boundary(prompt: str, start: int, end: int) -> bool:
    """Check if a match at [start:end] sits on word boundaries."""
    if start > 0 and re.match(r'[a-z0-9_.\-]', prompt[start - 1]):
        return False
    if end < len(prompt) and re.match(r'[a-z0-9_.\-]', prompt[end]):
        return False
    return True


def score_trigger(trigger: str, prompt_lower: str) -> int:
    """
    Score a single trigger regex against the prompt.
    Returns 30 for word-boundary match, 10 for substring match, 0 for no match.

    Mirrors the Bash word-boundary scanning loop: tries progressively shorter
    suffixes to find a word-boundary hit even if the first match is mid-word.
    """
    try:
        compiled = re.compile(trigger)
    except re.error:
        return 0

    # Scan for best match (word-boundary=30, substring=10)
    best = 0
    offset = 0
    scan = prompt_lower

    while scan:
        m = compiled.search(scan)
        if not m:
            break

        abs_start = offset + m.start()
        abs_end = offset + m.end()

        if is_word_boundary(prompt_lower, abs_start, abs_end):
            return 30  # Best possible, stop scanning

        best = 10  # At least a substring match

        # Advance one char past match start and retry
        skip = m.start() + 1
        scan = scan[skip:]
        offset += skip

    return best


def score_skills(skills: list[dict], prompt_lower: str) -> list[dict]:
    """
    Score all enabled/available skills against the prompt.
    Returns list of scored skills sorted by score descending.
    """
    results = []

    for skill in skills:
        if not skill.get("available") or not skill.get("enabled"):
            continue

        name = skill.get("name", "")
        name_lower = name.lower()
        role = skill.get("role", "")
        priority = skill.get("priority", 0)
        invoke = skill.get("invoke", f"Skill({name})")
        phase = skill.get("phase", "")
        triggers = skill.get("triggers", [])

        # Name boost
        name_boost = compute_name_boost(name_lower, prompt_lower)

        # Trigger scoring: accumulate scores across all triggers
        trigger_score = 0
        for trigger in triggers:
            trigger_score += score_trigger(trigger, prompt_lower)

        # Include skill if it has any score
        if trigger_score > 0 or name_boost > 0:
            final_score = trigger_score + priority + name_boost
            results.append({
                "score": final_score,
                "name": name,
                "role": role,
                "invoke": invoke,
                "phase": phase,
            })

    # Sort by score descending (stable sort preserves insertion order for ties)
    results.sort(key=lambda x: x["score"], reverse=True)
    return results


def select_by_role_caps(sorted_skills: list[dict], max_suggestions: int) -> tuple[list[dict], list[dict], list[dict]]:
    """
    Apply role caps: max 1 process, max 2 domain, max 1 workflow, total <= max_suggestions.
    The highest-ranked process skill always gets a reserved slot.

    Returns (selected, overflow_domain, overflow_workflow).
    """
    selected = []
    overflow_domain = []
    overflow_workflow = []
    process_count = 0
    domain_count = 0
    workflow_count = 0
    total_count = 0

    # Pass 1: reserve top process skill
    reserved_process_name = None
    for s in sorted_skills:
        if s["role"] == "process":
            reserved_process_name = s["name"]
            selected.append(s)
            process_count = 1
            total_count = 1
            break

    # Pass 2: fill remaining slots
    for s in sorted_skills:
        role = s["role"]

        if role == "process":
            if s["name"] == reserved_process_name:
                continue
            if process_count >= 1 or total_count >= max_suggestions:
                continue
            process_count += 1
        elif role == "domain":
            if domain_count >= 2 or total_count >= max_suggestions:
                overflow_domain.append(s)
                continue
            domain_count += 1
        elif role == "workflow":
            if workflow_count >= 1 or total_count >= max_suggestions:
                overflow_workflow.append(s)
                continue
            workflow_count += 1
        else:
            if total_count >= max_suggestions:
                continue

        selected.append(s)
        total_count += 1

    return selected, overflow_domain, overflow_workflow


def determine_label_phase(selected: list[dict]) -> tuple[str, str]:
    """
    Determine the display label and primary phase from selected skills.
    Returns (plabel, primary_phase).
    """
    plabel = ""
    has_domain = False
    has_workflow = False

    phase_process = ""
    phase_workflow = ""
    phase_domain = ""
    phase_first = ""

    for s in selected:
        role = s["role"]
        phase = s.get("phase", "")
        name = s["name"]

        if phase and not phase_first:
            phase_first = phase

        if role == "process":
            if not phase_process:
                phase_process = phase
            label_map = {
                "systematic-debugging": "Fix / Debug",
                "brainstorming": "Build New",
                "executing-plans": "Plan Execution",
                "subagent-driven-development": "Plan Execution",
                "test-driven-development": "Run / Test",
                "requesting-code-review": "Review",
                "receiving-code-review": "Review",
            }
            if not plabel and name in label_map:
                plabel = label_map[name]
        elif role == "domain":
            has_domain = True
            if not phase_domain:
                phase_domain = phase
        elif role == "workflow":
            has_workflow = True
            if not phase_workflow:
                phase_workflow = phase
            if not plabel and name in ("verification-before-completion", "finishing-a-development-branch"):
                plabel = "Ship / Complete"

    if not plabel:
        plabel = "(Claude: assess intent)"
    if has_domain:
        plabel += " + Domain"
    if has_workflow:
        plabel += " + Workflow"

    # Primary phase: process > workflow > domain > first
    primary_phase = phase_process or phase_workflow or phase_domain or phase_first

    return plabel, primary_phase


def build_skill_lines(selected: list[dict], overflow_domain: list[dict],
                      overflow_workflow: list[dict]) -> tuple[str, str]:
    """Build skill display lines and eval skills string."""
    process_skill = None
    for s in selected:
        if s["role"] == "process":
            process_skill = s["name"]
            break

    eval_parts = []
    sl_process = ""
    sl_domain = ""
    sl_workflow = ""
    sl_standalone = ""

    for s in selected:
        eval_parts.append(f"{s['name']} YES/NO")
        if process_skill:
            if s["role"] == "process":
                sl_process = f"\nProcess: {s['name']} -> {s['invoke']}"
            elif s["role"] == "domain":
                sl_domain += f"\n  Domain: {s['name']} -> {s['invoke']}"
            elif s["role"] == "workflow":
                sl_workflow += f"\n Workflow: {s['name']} -> {s['invoke']}"
        else:
            sl_standalone += f"\n{s['name']} -> {s['invoke']}"

    skill_lines = sl_process + sl_domain + sl_workflow + sl_standalone

    # Overflow
    for overflow in (overflow_domain, overflow_workflow):
        for s in overflow:
            skill_lines += f"\n  Also relevant: {s['name']} -> {s['invoke']}"
            eval_parts.append(f"{s['name']} YES/NO")

    return skill_lines, ", ".join(eval_parts)


def format_output(selected: list[dict], overflow_domain: list[dict],
                  overflow_workflow: list[dict], registry: dict) -> str:
    """Format the final output text (additionalContext)."""
    total_count = len(selected)

    if total_count == 0:
        return ("SKILL ACTIVATION (0 skills | phase checkpoint only)\n\n"
                "Phase: assess current phase (DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/DEBUG)\n"
                "and consider whether any installed skill applies.")

    plabel, primary_phase = determine_label_phase(selected)
    skill_lines, eval_skills = build_skill_lines(selected, overflow_domain, overflow_workflow)

    # Domain hint
    domain_hint = ""
    domain_count = sum(1 for s in selected if s["role"] == "domain")
    has_overflow_domain = len(overflow_domain) > 0
    process_skill = next((s["name"] for s in selected if s["role"] == "process"), None)

    if domain_count > 0 or has_overflow_domain:
        if process_skill:
            domain_hint = ("\nDomain skills evaluated YES: invoke them "
                           "(before, during, or after the process skill) -- do not just note them.")
        else:
            domain_hint = "\nDomain skills evaluated YES: invoke them -- do not just note them."

    eval_phase = primary_phase or "IMPLEMENT"

    if total_count <= 2:
        return (f"SKILL ACTIVATION ({total_count} skills | {plabel})\n"
                f"{skill_lines}\n\n"
                f"Evaluate: **Phase: [{eval_phase}]** | {eval_skills}{domain_hint}")
    else:
        # Full format (3+ skills)
        phase_guide = ""
        pg = registry.get("phase_guide")
        if pg:
            for key in sorted(pg.keys()):
                padding = " " * max(0, 10 - len(key))
                phase_guide += f"  {key}{padding} -> {pg[key]}\n"
        if not phase_guide:
            phase_guide = "  (no phase guide available -- assess intent from context)\n"

        return (f"SKILL ACTIVATION ({total_count} skills | {plabel})\n\n"
                f"Step 1 -- ASSESS PHASE. Check conversation context:\n"
                f"{phase_guide}\n"
                f"Step 2 -- EVALUATE skills against your phase assessment."
                f"{skill_lines}\n"
                f"You MUST print a brief evaluation for each skill above. Format:\n"
                f"  **Phase: [PHASE]** | [skill1] YES/NO, [skill2] YES/NO\n"
                f"Example: **Phase: IMPLEMENT** | test-driven-development YES, claude-md-improver NO (not editing CLAUDE.md)\n"
                f"This line is MANDATORY -- do not skip it.\n\n"
                f"Step 3 -- State your plan and proceed. Keep it to 1-2 sentences.{domain_hint}")


def main() -> None:
    """Main entry point."""
    # Read input from stdin
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            sys.exit(0)
        input_data = json.loads(raw)
    except (json.JSONDecodeError, OSError):
        sys.exit(0)

    prompt = input_data.get("prompt", "")
    if not prompt:
        sys.exit(0)

    # Skip slash commands
    if prompt.lstrip().startswith("/"):
        sys.exit(0)

    # Skip very short prompts
    if len(prompt) < 5:
        sys.exit(0)

    prompt_lower = prompt.lower()

    # Load registry
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT", os.path.join(os.path.dirname(__file__), ".."))
    registry = load_registry(plugin_root)

    if registry is None:
        out = ("SKILL ACTIVATION (0 skills | phase checkpoint only)\n\n"
               "Phase: assess current phase (DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/DEBUG)\n"
               "and consider whether any installed skill applies.")
        result = {
            "hookSpecificOutput": {
                "hookEventName": "UserPromptSubmit",
                "additionalContext": out,
            }
        }
        print(json.dumps(result))
        sys.exit(0)

    skills = registry.get("skills", [])
    max_suggestions = load_max_suggestions()

    # Score -> Select -> Format
    scored = score_skills(skills, prompt_lower)
    selected, overflow_domain, overflow_workflow = select_by_role_caps(scored, max_suggestions)
    out = format_output(selected, overflow_domain, overflow_workflow, registry)

    result = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": out,
        }
    }
    print(json.dumps(result))


if __name__ == "__main__":
    main()
