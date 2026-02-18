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
VERBOSITY="normal"
USER_CONFIG="${HOME}/.claude/skill-config.json"
if [[ -f "$USER_CONFIG" ]] && jq empty "$USER_CONFIG" >/dev/null 2>&1; then
  MAX_SUGGESTIONS="$(jq -r '.max_suggestions // 3' "$USER_CONFIG" 2>/dev/null)"
  VERBOSITY="$(jq -r '.verbosity // "normal"' "$USER_CONFIG" 2>/dev/null)"
fi

# =================================================================
# SCORE SKILLS AGAINST PROMPT
# =================================================================
# Use jq to iterate available+enabled skills, test each trigger regex
# against the lowercased prompt, compute scores, and return sorted results.
#
# Score formula: trigger_score (3 for word-boundary, 1 for substring) + priority
# We use jq to extract skill data, then bash for regex matching.

# Extract skills array as line-delimited JSON objects (one per skill)
SCORED_SKILLS="$(printf '%s' "$REGISTRY" | jq -c '
  [.skills[] | select(.available == true and .enabled == true)][]
' 2>/dev/null)"

# Score each skill
RESULTS=""
while IFS= read -r skill_json; do
  [[ -z "$skill_json" ]] && continue

  skill_name="$(printf '%s' "$skill_json" | jq -r '.name')"
  skill_role="$(printf '%s' "$skill_json" | jq -r '.role')"
  skill_priority="$(printf '%s' "$skill_json" | jq -r '.priority // 0')"
  skill_invoke="$(printf '%s' "$skill_json" | jq -r '.invoke // "SKIP"')"
  skill_phase="$(printf '%s' "$skill_json" | jq -r '.phase // ""')"

  trigger_count="$(printf '%s' "$skill_json" | jq '.triggers | length')"
  trigger_score=0

  ti=0
  while [[ "$ti" -lt "$trigger_count" ]]; do
    trigger="$(printf '%s' "$skill_json" | jq -r ".triggers[${ti}]")"
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
        if [[ "$char_before" =~ [a-z] ]]; then
          is_word_boundary=0
        fi
      fi
      if [[ "$after_pos" -lt "${#P}" ]]; then
        char_after="${P:${after_pos}:1}"
        if [[ "$char_after" =~ [a-z] ]]; then
          is_word_boundary=0
        fi
      fi

      if [[ "$is_word_boundary" -eq 1 ]]; then
        this_score=3
      else
        this_score=1
      fi

      if [[ "$this_score" -gt "$trigger_score" ]]; then
        trigger_score="$this_score"
      fi
    fi
  done

  if [[ "$trigger_score" -gt 0 ]]; then
    final_score=$((trigger_score + skill_priority))
    RESULTS="${RESULTS}${final_score}|${skill_name}|${skill_role}|${skill_invoke}|${skill_phase}
"
  fi
done <<EOF
${SCORED_SKILLS}
EOF

# Sort by score descending
SORTED="$(printf '%s' "$RESULTS" | grep -v '^$' | sort -t'|' -k1 -rn)"

# =================================================================
# SELECT BY ROLE CAPS
# =================================================================
# Max 1 process, up to 2 domain, max 1 workflow, total <= max_suggestions
SELECTED=""
PROCESS_COUNT=0
DOMAIN_COUNT=0
WORKFLOW_COUNT=0
TOTAL_COUNT=0

while IFS='|' read -r score name role invoke phase; do
  [[ -z "$name" ]] && continue
  [[ "$TOTAL_COUNT" -ge "$MAX_SUGGESTIONS" ]] && break

  case "$role" in
    process)
      [[ "$PROCESS_COUNT" -ge 1 ]] && continue
      PROCESS_COUNT=$((PROCESS_COUNT + 1))
      ;;
    domain)
      [[ "$DOMAIN_COUNT" -ge 2 ]] && continue
      DOMAIN_COUNT=$((DOMAIN_COUNT + 1))
      ;;
    workflow)
      [[ "$WORKFLOW_COUNT" -ge 1 ]] && continue
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
  INFORMED BY: ${name} -> ${invoke}" ;;
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

  OUT+="${PROCESS_LINE}${DOMAIN_LINES}${WORKFLOW_LINES}${STANDALONE_LINES}"

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

else
  # --- 3+ skills (full format) ---
  OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})"

  OUT+="

Step 1 -- ASSESS PHASE. Check conversation context:
  DESIGN    -> brainstorming (ask questions, get approval)
  PLAN      -> writing-plans (break into tasks, confirm before execution)
  IMPLEMENT -> executing-plans or subagent-driven-development + TDD
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
  INFORMED BY: ${name} -> ${invoke}" ;;
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

  OUT+="
You MUST print a brief evaluation for each skill above. Format:
  **Phase: [PHASE]** | [skill1] YES/NO, [skill2] YES/NO
Example: **Phase: IMPLEMENT** | test-driven-development YES, claude-md-improver NO (not editing CLAUDE.md)
This line is MANDATORY -- do not skip it.

Step 3 -- State your plan and proceed. Keep it to 1-2 sentences."
fi

# Append methodology hints if any
if [[ -n "$HINTS" ]]; then
  OUT+="
${HINTS}"
fi

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
  "$(printf '%s' "$OUT" | jq -Rs .)"
