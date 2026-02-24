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
# Score formula: trigger_score (30 for word-boundary, 10 for substring) + priority
# We use jq to extract skill data, then bash for regex matching.

# Extract skills array as line-delimited JSON objects (one per skill)
SCORED_SKILLS="$(printf '%s' "$REGISTRY" | jq -c '
  [.skills[] | select(.available == true and .enabled == true)][]
' 2>/dev/null)"

# L3: Pre-pass — collect skill names that appear verbatim in the prompt
SKILL_NAME_MATCHES=""
while IFS= read -r _sj; do
  [[ -z "$_sj" ]] && continue
  _sn="$(printf '%s' "$_sj" | jq -r '.name')"
  if [[ "$P" == *"$_sn"* ]]; then
    SKILL_NAME_MATCHES="${SKILL_NAME_MATCHES}|${_sn}"
  fi
done <<EOF
${SCORED_SKILLS}
EOF

# Score each skill
RESULTS=""
while IFS= read -r skill_json; do
  [[ -z "$skill_json" ]] && continue

  # Extract all fields in one jq call (reduces 5 forks to 1 per skill)
  read -r skill_name skill_role skill_priority skill_invoke skill_phase <<FIELDS
$(printf '%s' "$skill_json" | jq -r '[.name, .role, (.priority // 0 | tostring), (.invoke // "SKIP"), (.phase // "")] | @tsv')
FIELDS

  trigger_count="$(printf '%s' "$skill_json" | jq '.triggers // [] | length')"
  trigger_score=0

  ti=0
  while [[ "$ti" -lt "$trigger_count" ]]; do
    trigger="$(printf '%s' "$skill_json" | jq -r "(.triggers // [])[${ti}]")"
    ti=$((ti + 1))

    # Test regex against lowercased prompt
    if [[ "$P" =~ $trigger ]]; then
      matched="${BASH_REMATCH[0]}"
      # Word-boundary heuristic: check chars before/after match
      # Use substring removal to find match position
      prefix="${P%%"$matched"*}"
      prefix_len="${#prefix}"
      after_pos=$((prefix_len + ${#matched}))
      is_word_boundary=1

      if [[ "$prefix_len" -gt 0 ]]; then
        char_before="${P:$((prefix_len - 1)):1}"
        if [[ "$char_before" =~ [a-z0-9_-] ]]; then
          is_word_boundary=0
        fi
      fi
      if [[ "$after_pos" -lt "${#P}" ]]; then
        char_after="${P:${after_pos}:1}"
        if [[ "$char_after" =~ [a-z0-9_-] ]]; then
          is_word_boundary=0
        fi
      fi

      if [[ "$is_word_boundary" -eq 1 ]]; then
        this_score=30
      else
        this_score=10
      fi

      if [[ "$this_score" -gt "$trigger_score" ]]; then
        trigger_score="$this_score"
      fi
    fi
  done

  # L3: Apply skill-name-mention boost (+100) and allow through even with zero trigger_score
  name_boost=0
  if [[ "$SKILL_NAME_MATCHES" == *"|${skill_name}"* ]]; then
    name_boost=100
  fi

  if [[ "$trigger_score" -gt 0 ]] || [[ "$name_boost" -gt 0 ]]; then
    final_score=$((trigger_score + skill_priority + name_boost))
    RESULTS="${RESULTS}${final_score}|${skill_name}|${skill_role}|${skill_invoke}|${skill_phase}
"
  fi
done <<EOF
${SCORED_SKILLS}
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
# METHODOLOGY HINTS
# =================================================================
HINTS=""
HINT_COUNT="$(printf '%s' "$REGISTRY" | jq '.methodology_hints // [] | length' 2>/dev/null)" || HINT_COUNT=0
hi=0
while [[ "$hi" -lt "$HINT_COUNT" ]]; do
  hint_triggers="$(printf '%s' "$REGISTRY" | jq -r ".methodology_hints[${hi}].triggers[]" 2>/dev/null)"
  hint_text="$(printf '%s' "$REGISTRY" | jq -r ".methodology_hints[${hi}].hint" 2>/dev/null)"
  hint_skill="$(printf '%s' "$REGISTRY" | jq -r ".methodology_hints[${hi}].skill // empty" 2>/dev/null)"

  # L1b: Suppress hint if its associated skill is already selected
  if [[ -n "$hint_skill" ]] && printf '%s' "$SELECTED" | grep -q "|${hint_skill}|"; then
    hi=$((hi + 1))
    continue
  fi

  while IFS= read -r htrigger; do
    [[ -z "$htrigger" ]] && continue
    if [[ "$P" =~ $htrigger ]]; then
      HINTS="${HINTS}
- ${hint_text}"
      break
    fi
  done <<HEOF
${hint_triggers}
HEOF
  hi=$((hi + 1))
done

# =================================================================
# PHASE COMPOSITION: PARALLEL / SEQUENCE / HINTS
# =================================================================
COMPOSITION_LINES=""
COMPOSITION_HINTS=""

# Determine the current phase from selected skills
CURRENT_PHASE=""
while IFS='|' read -r score name role invoke phase; do
    [[ -z "$name" ]] && continue
    if [[ -n "$phase" ]]; then
        CURRENT_PHASE="$phase"
        break
    fi
done <<EOF
${SELECTED}
EOF

# Look up phase composition if registry has it and a phase was determined
if [[ -n "$CURRENT_PHASE" ]]; then
    _pc="$(printf '%s' "$REGISTRY" | jq -c --arg ph "$CURRENT_PHASE" '.phase_compositions[$ph] // empty' 2>/dev/null)"
    if [[ -n "$_pc" ]]; then
        # Emit PARALLEL lines for available plugins
        _par_count="$(printf '%s' "$_pc" | jq '.parallel // [] | length' 2>/dev/null)" || _par_count=0
        _pi=0
        while [[ "$_pi" -lt "$_par_count" ]]; do
            _plugin="$(printf '%s' "$_pc" | jq -r ".parallel[${_pi}].plugin" 2>/dev/null)"
            _use="$(printf '%s' "$_pc" | jq -r ".parallel[${_pi}].use" 2>/dev/null)"
            _purpose="$(printf '%s' "$_pc" | jq -r ".parallel[${_pi}].purpose" 2>/dev/null)"

            # Check if plugin is available
            _pavail="$(printf '%s' "$REGISTRY" | jq -r --arg pn "$_plugin" '.plugins // [] | .[] | select(.name == $pn) | .available' 2>/dev/null)"
            if [[ "$_pavail" == "true" ]]; then
                COMPOSITION_LINES="${COMPOSITION_LINES}
  PARALLEL: ${_use} -> ${_purpose} [${_plugin}]"
            fi
            _pi=$((_pi + 1))
        done

        # Emit SEQUENCE lines (SHIP phase)
        _seq_count="$(printf '%s' "$_pc" | jq '.sequence // [] | length' 2>/dev/null)" || _seq_count=0
        _si=0
        while [[ "$_si" -lt "$_seq_count" ]]; do
            _plugin="$(printf '%s' "$_pc" | jq -r ".sequence[${_si}].plugin // empty" 2>/dev/null)"
            _step="$(printf '%s' "$_pc" | jq -r ".sequence[${_si}].step // empty" 2>/dev/null)"
            _use="$(printf '%s' "$_pc" | jq -r ".sequence[${_si}].use // empty" 2>/dev/null)"
            _purpose="$(printf '%s' "$_pc" | jq -r ".sequence[${_si}].purpose" 2>/dev/null)"

            if [[ -n "$_plugin" ]]; then
                _pavail="$(printf '%s' "$REGISTRY" | jq -r --arg pn "$_plugin" '.plugins // [] | .[] | select(.name == $pn) | .available' 2>/dev/null)"
                if [[ "$_pavail" == "true" ]]; then
                    COMPOSITION_LINES="${COMPOSITION_LINES}
  SEQUENCE: ${_use} -> ${_purpose} [${_plugin}]"
                fi
            elif [[ -n "$_step" ]]; then
                COMPOSITION_LINES="${COMPOSITION_LINES}
  SEQUENCE: ${_step} -> ${_purpose}"
            fi
            _si=$((_si + 1))
        done

        # Collect composition hints for available plugins
        _hint_count="$(printf '%s' "$_pc" | jq '.hints // [] | length' 2>/dev/null)" || _hint_count=0
        _hi=0
        while [[ "$_hi" -lt "$_hint_count" ]]; do
            _plugin="$(printf '%s' "$_pc" | jq -r ".hints[${_hi}].plugin" 2>/dev/null)"
            _text="$(printf '%s' "$_pc" | jq -r ".hints[${_hi}].text" 2>/dev/null)"

            _pavail="$(printf '%s' "$REGISTRY" | jq -r --arg pn "$_plugin" '.plugins // [] | .[] | select(.name == $pn) | .available' 2>/dev/null)"
            if [[ "$_pavail" == "true" ]]; then
                COMPOSITION_HINTS="${COMPOSITION_HINTS}
- ${_text}"
            fi
            _hi=$((_hi + 1))
        done
    fi
fi

# =================================================================
# BUILD ORCHESTRATED CONTEXT OUTPUT
# =================================================================

if [[ "$TOTAL_COUNT" -eq 0 ]]; then
  # --- 0 skills matched ---
  OUT="SKILL ACTIVATION (0 skills | phase checkpoint only)

Phase: assess current phase (DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/DEBUG)
and consider whether any installed skill applies."

elif [[ "$TOTAL_COUNT" -le 2 ]]; then
  # --- 1-2 skills (compact format) ---
  OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})"
  OUT+="
"

  # Build skill lines
  PROCESS_LINE=""
  DOMAIN_LINES=""
  WORKFLOW_LINES=""
  STANDALONE_LINES=""
  EVAL_SKILLS=""

  while IFS='|' read -r score name role invoke phase; do
    [[ -z "$name" ]] && continue
    if [[ -n "$EVAL_SKILLS" ]]; then
      EVAL_SKILLS="${EVAL_SKILLS}, ${name} YES/NO"
    else
      EVAL_SKILLS="${name} YES/NO"
    fi

    if [[ -n "$PROCESS_SKILL" ]]; then
      case "$role" in
        process)  PROCESS_LINE="
Process: ${name} -> ${invoke}" ;;
        domain)   DOMAIN_LINES="${DOMAIN_LINES}
  Domain: ${name} -> ${invoke}" ;;
        workflow) WORKFLOW_LINES="${WORKFLOW_LINES}
Workflow: ${name} -> ${invoke}" ;;
      esac
    else
      STANDALONE_LINES="${STANDALONE_LINES}
${name} -> ${invoke}"
    fi
  done <<EOF
${SELECTED}
EOF

  OUT+="${PROCESS_LINE}${DOMAIN_LINES}${WORKFLOW_LINES}${STANDALONE_LINES}${COMPOSITION_LINES}"

  # Append overflow domain skills (relevant but didn't fit in top suggestions)
  OVERFLOW_LINES=""
  while IFS='|' read -r oname oinvoke; do
    [[ -z "$oname" ]] && continue
    OVERFLOW_LINES="${OVERFLOW_LINES}
  Also relevant: ${oname} -> ${oinvoke}"
    EVAL_SKILLS="${EVAL_SKILLS}, ${oname} YES/NO"
  done <<EOF
${OVERFLOW_DOMAIN}
EOF
  OUT+="${OVERFLOW_LINES}"

  # Get phase from process skill or first skill
  EVAL_PHASE=""
  while IFS='|' read -r score name role invoke phase; do
    [[ -z "$name" ]] && continue
    if [[ -n "$phase" ]]; then
      EVAL_PHASE="$phase"
      break
    fi
  done <<EOF
${SELECTED}
EOF
  [[ -z "$EVAL_PHASE" ]] && EVAL_PHASE="IMPLEMENT"

  OUT+="

Evaluate: **Phase: [${EVAL_PHASE}]** | ${EVAL_SKILLS}"

  # Add domain invocation instruction when domain skills are present
  if [[ "$DOMAIN_COUNT" -gt 0 ]] || [[ -n "$OVERFLOW_DOMAIN" ]]; then
    OUT+="
Domain skills evaluated YES: invoke them (before, during, or after the process skill) -- do not just note them."
  fi

else
  # --- 3+ skills (full format) ---
  OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})"

  OUT+="

Step 1 -- ASSESS PHASE. Check conversation context:
  DESIGN    -> brainstorming (ask questions, get approval)
  PLAN      -> writing-plans (break into tasks, confirm before execution)
  IMPLEMENT -> executing-plans or subagent-driven-development + TDD (offer agent-team-execution for 3+ independent tasks)
  REVIEW    -> requesting-code-review
  SHIP      -> verification-before-completion + finishing-a-development-branch
  DEBUG     -> systematic-debugging, then return to current phase

Step 2 -- EVALUATE skills against your phase assessment."

  # Build skill lines with orchestration
  EVAL_SKILLS=""

  while IFS='|' read -r score name role invoke phase; do
    [[ -z "$name" ]] && continue
    if [[ -n "$EVAL_SKILLS" ]]; then
      EVAL_SKILLS="${EVAL_SKILLS}, ${name} YES/NO"
    else
      EVAL_SKILLS="${name} YES/NO"
    fi

    if [[ -n "$PROCESS_SKILL" ]]; then
      case "$role" in
        process)  OUT+="
Process: ${name} -> ${invoke}" ;;
        domain)   OUT+="
  Domain: ${name} -> ${invoke}" ;;
        workflow) OUT+="
Workflow: ${name} -> ${invoke}" ;;
      esac
    else
      OUT+="
${name} -> ${invoke}"
    fi
  done <<EOF
${SELECTED}
EOF

  # Append overflow domain skills
  while IFS='|' read -r oname oinvoke; do
    [[ -z "$oname" ]] && continue
    OUT+="
  Also relevant: ${oname} -> ${oinvoke}"
    EVAL_SKILLS="${EVAL_SKILLS}, ${oname} YES/NO"
  done <<EOF
${OVERFLOW_DOMAIN}
EOF
  OUT+="${COMPOSITION_LINES}"

  OUT+="
You MUST print a brief evaluation for each skill above. Format:
  **Phase: [PHASE]** | [skill1] YES/NO, [skill2] YES/NO
Example: **Phase: IMPLEMENT** | test-driven-development YES, claude-md-improver NO (not editing CLAUDE.md)
This line is MANDATORY -- do not skip it.

Step 3 -- State your plan and proceed. Keep it to 1-2 sentences."

  # Add domain invocation instruction when domain skills are present
  if [[ "$DOMAIN_COUNT" -gt 0 ]] || [[ -n "$OVERFLOW_DOMAIN" ]]; then
    OUT+="
Domain skills evaluated YES: invoke them (before, during, or after the process skill) -- do not just note them."
  fi
fi

# Append methodology hints if any
if [[ -n "$HINTS" ]] || [[ -n "$COMPOSITION_HINTS" ]]; then
  OUT+="
${HINTS}${COMPOSITION_HINTS}"
fi

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
  "$(printf '%s' "$OUT" | jq -Rs .)"
