#!/bin/bash
# --- Claude Code Skill Activation Hook v2 (config-driven) --------
# https://github.com/damianpapadopoulos/auto-claude-skills
#
# Config-driven routing engine that reads the cached skill registry
# instead of using hardcoded regex patterns.
#
# Input: {"prompt": "..."} via stdin
# Output: {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"..."}}
#
# Bash 3.2 compatible (macOS default). Heavy jq usage for scoring.
# -----------------------------------------------------------------
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# jq is required for registry-based routing
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

PROMPT=$(cat 2>/dev/null | jq -r '.prompt // empty' 2>/dev/null) || true

# =================================================================
# EARLY EXITS (preserved from v1)
# =================================================================
[[ -z "$PROMPT" ]] && exit 0
[[ "$PROMPT" =~ ^[[:space:]]*/  ]] && exit 0
(( ${#PROMPT} < 8 )) && exit 0

P=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# =================================================================
# BLOCKLIST (preserved from v1 for backwards compatibility)
# =================================================================
if [[ "$P" =~ ^(hi|hello|hey|thanks|thank.you|good.(morning|afternoon|evening)|bye|goodbye|ok|okay|yes|no|sure|yep|nope|got.it|sounds.good|cool|nice|great|perfect|awesome|understood)([[:space:]!.,]+.{0,20})?$ ]]; then
  TAIL="${P#*[[:space:]]}"
  if [[ "$TAIL" == "$P" ]] || (( ${#TAIL} < 20 )); then
    exit 0
  fi
fi

# =================================================================
# LOAD REGISTRY
# =================================================================
REGISTRY_CACHE="${HOME}/.claude/.skill-registry-cache.json"
FALLBACK_REGISTRY="${PLUGIN_ROOT}/config/fallback-registry.json"
REGISTRY=""

if [[ -f "$REGISTRY_CACHE" ]] && jq empty "$REGISTRY_CACHE" >/dev/null 2>&1; then
  REGISTRY="$(cat "$REGISTRY_CACHE")"
elif [[ -f "$FALLBACK_REGISTRY" ]] && jq empty "$FALLBACK_REGISTRY" >/dev/null 2>&1; then
  REGISTRY="$(cat "$FALLBACK_REGISTRY")"
else
  # No registry available — emit minimal phase checkpoint and exit
  OUT="SKILL ACTIVATION (0 skills | phase checkpoint only)

Phase: assess current phase (DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/DEBUG)
and consider whether any installed skill applies."
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
    "$(printf '%s' "$OUT" | jq -Rs .)"
  exit 0
fi

# =================================================================
# LOAD USER SETTINGS
# =================================================================
MAX_SUGGESTIONS=3
USER_CONFIG="${HOME}/.claude/skill-config.json"
if [[ -f "$USER_CONFIG" ]] && jq empty "$USER_CONFIG" >/dev/null 2>&1; then
  _ms="$(jq -r '.settings.max_suggestions // .max_suggestions // 3' "$USER_CONFIG" 2>/dev/null)"
  # Validate as positive integer; fall back to 3
  if [[ "$_ms" =~ ^[1-9][0-9]*$ ]]; then
    MAX_SUGGESTIONS="$_ms"
  fi
fi

# =================================================================
# SCORE SKILLS AGAINST PROMPT
# =================================================================
# Use jq to iterate available+enabled skills, test each trigger regex
# against the lowercased prompt, compute scores, and return sorted results.
#
# Score formula: sum(trigger_scores) + priority + name_boost
# Per-trigger: 30 for word-boundary match, 10 for substring match (accumulated, not max).

# Single jq call extracts all enabled skills (replaces ~80 per-skill jq forks with 1).
# Format: name<US>name_lower<US>role<US>priority<US>invoke<US>phase<US>triggers
# US (\x1f) as field separator (non-whitespace, so empty fields survive IFS splitting).
# SOH (\x01) as intra-field trigger delimiter.
DELIM=$'\x01'
FS=$'\x1f'
SKILL_DATA="$(printf '%s' "$REGISTRY" | jq -r '
  [.skills[] | select(.available == true and .enabled == true)] | .[] |
  (.name + "\u001f" + (.name | ascii_downcase) + "\u001f" + .role + "\u001f" +
   (.priority // 0 | tostring) + "\u001f" + (.invoke // "SKIP") + "\u001f" +
   (.phase // "") + "\u001f" + ((.triggers // []) | join("\u0001")))
' 2>/dev/null)"

# Score each skill (name-boost check merged into the same loop — no separate pre-pass)
RESULTS=""
while IFS="$FS" read -r skill_name skill_name_lower skill_role skill_priority skill_invoke skill_phase triggers_joined; do
  [[ -z "$skill_name" ]] && continue

  # Name boost: check if skill name appears as whole word in prompt
  # Word boundaries for kebab-case names: start/end of string, or non-[a-z0-9-] character
  name_boost=0
  if [[ "$P" =~ (^|[^a-z0-9-])${skill_name_lower}($|[^a-z0-9-]) ]]; then
    name_boost=100
  fi

  # Score triggers (iterate using string splitting — no per-trigger jq fork)
  trigger_score=0
  if [[ -n "$triggers_joined" ]]; then
    _remaining="$triggers_joined"
    while [[ -n "$_remaining" ]]; do
      if [[ "$_remaining" == *"${DELIM}"* ]]; then
        trigger="${_remaining%%${DELIM}*}"
        _remaining="${_remaining#*${DELIM}}"
      else
        trigger="$_remaining"
        _remaining=""
      fi
      [[ -z "$trigger" ]] && continue

      # Test regex against lowercased prompt
      if [[ "$P" =~ $trigger ]]; then
        matched="${BASH_REMATCH[0]}"
        # Word-boundary heuristic: check chars before/after match
        prefix="${P%%"$matched"*}"
        prefix_len="${#prefix}"
        after_pos=$((prefix_len + ${#matched}))
        is_word_boundary=1

        if [[ "$prefix_len" -gt 0 ]]; then
          char_before="${P:$((prefix_len - 1)):1}"
          if [[ "$char_before" =~ [a-z0-9_.-] ]]; then
            is_word_boundary=0
          fi
        fi
        if [[ "$after_pos" -lt "${#P}" ]]; then
          char_after="${P:${after_pos}:1}"
          if [[ "$char_after" =~ [a-z0-9_.-] ]]; then
            is_word_boundary=0
          fi
        fi

        if [[ "$is_word_boundary" -eq 1 ]]; then
          this_score=30
        else
          this_score=10
        fi
        trigger_score=$((trigger_score + this_score))
      fi
    done
  fi

  # Apply skill-name-mention boost (+100) and allow through even with zero trigger_score
  if [[ "$trigger_score" -gt 0 ]] || [[ "$name_boost" -gt 0 ]]; then
    final_score=$((trigger_score + skill_priority + name_boost))
    RESULTS="${RESULTS}${final_score}|${skill_name}|${skill_role}|${skill_invoke}|${skill_phase}
"
  fi
done <<EOF
${SKILL_DATA}
EOF

# Sort by score descending
SORTED="$(printf '%s' "$RESULTS" | grep -v '^$' | sort -s -t'|' -k1 -rn)"

# =================================================================
# SELECT BY ROLE CAPS
# =================================================================
# Max 1 process, up to 2 domain, max 1 workflow, total <= max_suggestions
# INVARIANT: If any process skill matched, it gets a reserved slot.
SELECTED=""
OVERFLOW_DOMAIN=""
PROCESS_COUNT=0
DOMAIN_COUNT=0
WORKFLOW_COUNT=0
TOTAL_COUNT=0

# Pre-select: find the highest-ranked process skill and reserve a slot
RESERVED_PROCESS=""
while IFS='|' read -r score name role invoke phase; do
  [[ -z "$name" ]] && continue
  if [[ "$role" == "process" ]]; then
    RESERVED_PROCESS="${score}|${name}|${role}|${invoke}|${phase}"
    SELECTED="${RESERVED_PROCESS}
"
    PROCESS_COUNT=1
    TOTAL_COUNT=1
    break
  fi
done <<EOF
${SORTED}
EOF

# Fill remaining slots from SORTED, skipping the reserved process skill
while IFS='|' read -r score name role invoke phase; do
  [[ -z "$name" ]] && continue

  # Skip the already-reserved process skill
  if [[ -n "$RESERVED_PROCESS" ]] && [[ "$role" == "process" ]] && [[ "$RESERVED_PROCESS" == "${score}|${name}|${role}|${invoke}|${phase}" ]]; then
    continue
  fi

  case "$role" in
    process)
      [[ "$PROCESS_COUNT" -ge 1 ]] && continue
      [[ "$TOTAL_COUNT" -ge "$MAX_SUGGESTIONS" ]] && continue
      PROCESS_COUNT=$((PROCESS_COUNT + 1))
      ;;
    domain)
      if [[ "$DOMAIN_COUNT" -ge 2 ]] || [[ "$TOTAL_COUNT" -ge "$MAX_SUGGESTIONS" ]]; then
        # Track overflow domain skills — still relevant, just didn't fit
        OVERFLOW_DOMAIN="${OVERFLOW_DOMAIN}${name}|${invoke}
"
        continue
      fi
      DOMAIN_COUNT=$((DOMAIN_COUNT + 1))
      ;;
    workflow)
      [[ "$WORKFLOW_COUNT" -ge 1 ]] && continue
      [[ "$TOTAL_COUNT" -ge "$MAX_SUGGESTIONS" ]] && continue
      WORKFLOW_COUNT=$((WORKFLOW_COUNT + 1))
      ;;
  esac

  SELECTED="${SELECTED}${score}|${name}|${role}|${invoke}|${phase}
"
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
done <<EOF
${SORTED}
EOF

# =================================================================
# DETERMINE LABEL
# =================================================================
PLABEL=""
PROCESS_SKILL=""
HAS_DOMAIN=0
HAS_WORKFLOW=0

while IFS='|' read -r score name role invoke phase; do
  [[ -z "$name" ]] && continue
  case "$role" in
    process)
      PROCESS_SKILL="$name"
      case "$name" in
        systematic-debugging)       PLABEL="Fix / Debug" ;;
        brainstorming)              PLABEL="Build New" ;;
        executing-plans|subagent-driven-development) PLABEL="Plan Execution" ;;
        test-driven-development)    PLABEL="Run / Test" ;;
        requesting-code-review|receiving-code-review) PLABEL="Review" ;;
      esac
      ;;
    domain)
      HAS_DOMAIN=1
      ;;
    workflow)
      HAS_WORKFLOW=1
      # If no process skill sets the label, workflow skills set Ship / Complete
      if [[ -z "$PLABEL" ]]; then
        case "$name" in
          verification-before-completion|finishing-a-development-branch) PLABEL="Ship / Complete" ;;
        esac
      fi
      ;;
  esac
done <<EOF
${SELECTED}
EOF

[[ -z "$PLABEL" ]] && PLABEL="(Claude: assess intent)"
[[ "$HAS_DOMAIN" -eq 1 ]] && PLABEL="${PLABEL} + Domain"
[[ "$HAS_WORKFLOW" -eq 1 ]] && PLABEL="${PLABEL} + Workflow"

# =================================================================
# PRIMARY PHASE (process > workflow > domain > first non-empty)
# =================================================================
PRIMARY_PHASE=""
_PHASE_PROCESS=""
_PHASE_WORKFLOW=""
_PHASE_DOMAIN=""
_PHASE_FIRST=""

while IFS='|' read -r score name role invoke phase; do
  [[ -z "$name" ]] && continue
  if [[ -n "$phase" ]] && [[ -z "$_PHASE_FIRST" ]]; then
    _PHASE_FIRST="$phase"
  fi
  case "$role" in
    process)  [[ -z "$_PHASE_PROCESS" ]] && _PHASE_PROCESS="$phase" ;;
    workflow) [[ -z "$_PHASE_WORKFLOW" ]] && _PHASE_WORKFLOW="$phase" ;;
    domain)   [[ -z "$_PHASE_DOMAIN" ]] && _PHASE_DOMAIN="$phase" ;;
  esac
done <<EOF
${SELECTED}
EOF

if [[ -n "$_PHASE_PROCESS" ]]; then
  PRIMARY_PHASE="$_PHASE_PROCESS"
elif [[ -n "$_PHASE_WORKFLOW" ]]; then
  PRIMARY_PHASE="$_PHASE_WORKFLOW"
elif [[ -n "$_PHASE_DOMAIN" ]]; then
  PRIMARY_PHASE="$_PHASE_DOMAIN"
else
  PRIMARY_PHASE="$_PHASE_FIRST"
fi

# =================================================================
# METHODOLOGY HINTS
# =================================================================
# Single jq call extracts all hint data (replaces ~9 per-hint jq forks with 1)
HINTS=""
HINTS_DATA="$(printf '%s' "$REGISTRY" | jq -r '
  .methodology_hints // [] | .[] |
  ((.skill // "") + "\u001f" + .hint + "\u001f" + ((.triggers // []) | join("\u0001")))
' 2>/dev/null)"

while IFS="$FS" read -r hint_skill hint_text hint_triggers_joined; do
  [[ -z "$hint_text" ]] && continue

  # Suppress hint if its associated skill is already selected
  if [[ -n "$hint_skill" ]] && printf '%s' "$SELECTED" | grep -q "|${hint_skill}|"; then
    continue
  fi

  # Test hint triggers against prompt
  if [[ -n "$hint_triggers_joined" ]]; then
    _remaining="$hint_triggers_joined"
    while [[ -n "$_remaining" ]]; do
      if [[ "$_remaining" == *"${DELIM}"* ]]; then
        htrigger="${_remaining%%${DELIM}*}"
        _remaining="${_remaining#*${DELIM}}"
      else
        htrigger="$_remaining"
        _remaining=""
      fi
      [[ -z "$htrigger" ]] && continue
      if [[ "$P" =~ $htrigger ]]; then
        HINTS="${HINTS}
- ${hint_text}"
        break
      fi
    done
  fi
done <<EOF
${HINTS_DATA}
EOF

# =================================================================
# PHASE COMPOSITION: PARALLEL / SEQUENCE / HINTS
# =================================================================
COMPOSITION_LINES=""
COMPOSITION_HINTS=""

# Determine the current phase from selected skills (use PRIMARY_PHASE)
CURRENT_PHASE="$PRIMARY_PHASE"

# Single jq call computes all composition output (replaces ~20-30 per-entry jq forks with 1)
if [[ -n "$CURRENT_PHASE" ]]; then
  _comp_output="$(printf '%s' "$REGISTRY" | jq -r --arg ph "$CURRENT_PHASE" '
    [.plugins // [] | .[] | select(.available == true) | .name] as $avail |
    .phase_compositions[$ph] // empty |
    (
      (.parallel // [] | .[] |
        select(.plugin as $p | $avail | any(. == $p)) |
        "LINE:  PARALLEL: \(.use) -> \(.purpose) [\(.plugin)]"),
      (.sequence // [] | .[] |
        if .plugin then
          select(.plugin as $p | $avail | any(. == $p)) |
          "LINE:  SEQUENCE: \(.use // .step) -> \(.purpose) [\(.plugin)]"
        else
          "LINE:  SEQUENCE: \(.step) -> \(.purpose)"
        end),
      (.hints // [] | .[] |
        select(.plugin as $p | $avail | any(. == $p)) |
        "HINT:\(.text)")
    )
  ' 2>/dev/null)"

  while IFS= read -r _cline; do
    [[ -z "$_cline" ]] && continue
    case "$_cline" in
      LINE:*)  COMPOSITION_LINES="${COMPOSITION_LINES}
${_cline#LINE:}" ;;
      HINT:*)  COMPOSITION_HINTS="${COMPOSITION_HINTS}
- ${_cline#HINT:}" ;;
    esac
  done <<EOF
${_comp_output}
EOF
fi

# =================================================================
# BUILD ORCHESTRATED CONTEXT OUTPUT
# =================================================================

# =================================================================
# BUILD SKILL LINES + EVAL LIST (shared across compact and full formats)
# =================================================================
SKILL_LINES=""
EVAL_SKILLS=""

if [[ "$TOTAL_COUNT" -gt 0 ]]; then
  _SL_PROCESS=""
  _SL_DOMAIN=""
  _SL_WORKFLOW=""
  _SL_STANDALONE=""

  while IFS='|' read -r score name role invoke phase; do
    [[ -z "$name" ]] && continue
    if [[ -n "$EVAL_SKILLS" ]]; then
      EVAL_SKILLS="${EVAL_SKILLS}, ${name} YES/NO"
    else
      EVAL_SKILLS="${name} YES/NO"
    fi

    if [[ -n "$PROCESS_SKILL" ]]; then
      case "$role" in
        process)  _SL_PROCESS="
Process: ${name} -> ${invoke}" ;;
        domain)   _SL_DOMAIN="${_SL_DOMAIN}
  Domain: ${name} -> ${invoke}" ;;
        workflow) _SL_WORKFLOW="${_SL_WORKFLOW}
Workflow: ${name} -> ${invoke}" ;;
      esac
    else
      _SL_STANDALONE="${_SL_STANDALONE}
${name} -> ${invoke}"
    fi
  done <<EOF
${SELECTED}
EOF

  SKILL_LINES="${_SL_PROCESS}${_SL_DOMAIN}${_SL_WORKFLOW}${_SL_STANDALONE}"

  # Overflow domain skills (relevant but didn't fit in top suggestions)
  while IFS='|' read -r oname oinvoke; do
    [[ -z "$oname" ]] && continue
    SKILL_LINES="${SKILL_LINES}
  Also relevant: ${oname} -> ${oinvoke}"
    EVAL_SKILLS="${EVAL_SKILLS}, ${oname} YES/NO"
  done <<EOF
${OVERFLOW_DOMAIN}
EOF
fi

# Domain invocation instruction (shared)
DOMAIN_HINT=""
if [[ "$DOMAIN_COUNT" -gt 0 ]] || [[ -n "$OVERFLOW_DOMAIN" ]]; then
  if [[ -n "$PROCESS_SKILL" ]]; then
    DOMAIN_HINT="
Domain skills evaluated YES: invoke them (before, during, or after the process skill) -- do not just note them."
  else
    DOMAIN_HINT="
Domain skills evaluated YES: invoke them -- do not just note them."
  fi
fi

# =================================================================
# FORMAT OUTPUT (only the wrapper text differs between compact/full)
# =================================================================
if [[ "$TOTAL_COUNT" -eq 0 ]]; then
  OUT="SKILL ACTIVATION (0 skills | phase checkpoint only)

Phase: assess current phase (DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/DEBUG)
and consider whether any installed skill applies."

elif [[ "$TOTAL_COUNT" -le 2 ]]; then
  # --- compact format ---
  EVAL_PHASE="$PRIMARY_PHASE"
  [[ -z "$EVAL_PHASE" ]] && EVAL_PHASE="IMPLEMENT"

  OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})
${SKILL_LINES}${COMPOSITION_LINES}

Evaluate: **Phase: [${EVAL_PHASE}]** | ${EVAL_SKILLS}${DOMAIN_HINT}"

else
  # --- full format (3+ skills) ---
  OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})

Step 1 -- ASSESS PHASE. Check conversation context:
  DESIGN    -> brainstorming (ask questions, get approval)
  PLAN      -> writing-plans (break into tasks, confirm before execution)
  IMPLEMENT -> executing-plans or subagent-driven-development + TDD (offer agent-team-execution for 3+ independent tasks)
  REVIEW    -> requesting-code-review
  SHIP      -> verification-before-completion + finishing-a-development-branch
  DEBUG     -> systematic-debugging, then return to current phase

Step 2 -- EVALUATE skills against your phase assessment.${SKILL_LINES}${COMPOSITION_LINES}
You MUST print a brief evaluation for each skill above. Format:
  **Phase: [PHASE]** | [skill1] YES/NO, [skill2] YES/NO
Example: **Phase: IMPLEMENT** | test-driven-development YES, claude-md-improver NO (not editing CLAUDE.md)
This line is MANDATORY -- do not skip it.

Step 3 -- State your plan and proceed. Keep it to 1-2 sentences.${DOMAIN_HINT}"
fi

# Append methodology hints if any
if [[ -n "$HINTS" ]] || [[ -n "$COMPOSITION_HINTS" ]]; then
  OUT+="
${HINTS}${COMPOSITION_HINTS}"
fi

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
  "$(printf '%s' "$OUT" | jq -Rs .)"
