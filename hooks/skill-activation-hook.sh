#!/bin/bash
# --- Claude Code Skill Activation Hook v8 -----------------------
# https://github.com/damianpapadopoulos/auto-claude-skills
#
# Hybrid intent routing with phase-aware checkpoints.
#
# DESIGN PRINCIPLE: The regex is a FAST PRE-FILTER, not the decision
# maker. Claude Code (already running) makes the real intent assessment
# via the phase checkpoint instruction injected into context.
# No extra API call needed -- Claude IS the classifier.
#
# v8: Wider fallthrough net. In a Claude Code session, most prompts
# are dev-related. Instead of allowlisting dev keywords, we blocklist
# the few clearly non-dev patterns and let Claude assess everything else.
#
# Three layers: Primary Intent -> Cross-cutting Overlays -> Phase Check
# The hook suggests; Claude decides; the user overrides.
# -----------------------------------------------------------------
set -uo pipefail

PROMPT=$(cat 2>/dev/null | jq -r '.prompt // empty' 2>/dev/null) || true

# --- Early exits -------------------------------------------------
[[ -z "$PROMPT" ]] && exit 0
[[ "$PROMPT" =~ ^[[:space:]]*/  ]] && exit 0
(( ${#PROMPT} < 8 )) && exit 0

P=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# --- Non-dev prompt filter (blocklist approach) ------------------
# Exit early ONLY for prompts that are clearly not dev tasks.
# Everything else gets the phase checkpoint so Claude can decide.
if [[ "$P" =~ ^(hi|hello|hey|thanks|thank.you|good.(morning|afternoon|evening)|bye|goodbye|ok|okay|yes|no|sure|yep|nope|got.it|sounds.good|cool|nice|great|perfect|awesome|understood)([[:space:]!.,]+.{0,20})?$ ]]; then
  # Allow short trailing words like "hello there", "hey claude", "thanks a lot"
  # but not "hello can you fix the bug" (that's a real prompt)
  TAIL="${P#*[[:space:]]}"
  if [[ "$TAIL" == "$P" ]] || (( ${#TAIL} < 20 )); then
    exit 0
  fi
fi

# --- Skill path resolution ---------------------------------------
SP_BASE="$HOME/.claude/plugins/cache/claude-plugins-official/superpowers"
SP_SKILLS=""
if [[ -d "$SP_BASE" ]]; then
  SP_VERSION=$(ls -1 "$SP_BASE" 2>/dev/null | sort -V | tail -1)
  [[ -n "$SP_VERSION" ]] && SP_SKILLS="$SP_BASE/$SP_VERSION/skills"
fi
USER_SKILLS="$HOME/.claude/skills"
PLUGIN_CACHE="$HOME/.claude/plugins/cache/claude-plugins-official"

skill_path() {
  case "$1" in
    frontend-design)
      [[ -d "$PLUGIN_CACHE/frontend-design" ]] && echo "Call Skill(frontend-design:frontend-design)" && return ;;
    claude-md-improver)
      [[ -d "$PLUGIN_CACHE/claude-md-management" ]] && echo "Call Skill(claude-md-management:claude-md-improver)" && return ;;
    claude-automation-recommender)
      [[ -d "$PLUGIN_CACHE/claude-code-setup" ]] && echo "Call Skill(claude-code-setup:claude-automation-recommender)" && return ;;
    doc-coauthoring|webapp-testing|security-scanner)
      [[ -f "$USER_SKILLS/$1/SKILL.md" ]] && echo "Read $USER_SKILLS/$1/SKILL.md" && return ;;
    *)
      [[ -n "$SP_SKILLS" && -f "$SP_SKILLS/$1/SKILL.md" ]] && echo "Read $SP_SKILLS/$1/SKILL.md" && return ;;
  esac
  echo "SKIP"
}

# =================================================================
# LAYER 1: PRIMARY INTENT (fast regex pre-filter)
# Priority: Fix > Execute Plan > Build > Review > Ship
# These are SUGGESTIONS -- Claude's phase assessment decides.
# Broader patterns = fewer false negatives. Claude filters false positives.
# =================================================================
PRIMARY="" PLABEL=""

# --- Fix / Debug ---
if [[ -z "$PLABEL" && "$P" =~ (debug|bug|fix|broken|fail|error|crash|wrong|unexpected|not.work|regression|issue|problem|doesn.t|won.t|can.t|stuck|hang|freeze|timeout|leak|corrupt|invalid|missing) ]]; then
  PRIMARY="systematic-debugging test-driven-development"
  PLABEL="Fix / Debug"
fi

# --- Plan Execution ---
if [[ -z "$PLABEL" && "$P" =~ (execute.*plan|run.the.plan|implement.the.plan|implement.*(rest|remaining)|continue|follow.the.plan|pick.up|resume|next.task|next.step|carry.on|keep.going|where.were.we|what.s.next) ]]; then
  PRIMARY="subagent-driven-development executing-plans"
  PLABEL="Plan Execution"
fi

# --- Build / Create ---
if [[ -z "$PLABEL" && "$P" =~ (build|create|implement|develop|scaffold|init|bootstrap|brainstorm|design|architect|strateg|scope|outline|approach|add|write|make|generate|set.?up|install|configure|wire.up|connect|integrate|extend|new|start|introduce|enable|support|how.(should|would|could)) ]]; then
  PRIMARY="brainstorming test-driven-development"
  PLABEL="Build New"
fi

# --- Modify / Update ---
if [[ -z "$PLABEL" && "$P" =~ (update|change|modify|edit|alter|adjust|tweak|move|rename|replace|swap|switch|convert|transform|migrate|upgrade|downgrade|bump|patch|optimize|improve|enhance|speed.up|performance|refactor|restructure|reorganize|simplify|consolidate|extract|inline|split|combine) ]]; then
  PRIMARY="brainstorming test-driven-development"
  PLABEL="Modify / Update"
fi

# --- Remove / Clean ---
if [[ -z "$PLABEL" && "$P" =~ (remove|delete|drop|clean|prune|strip|deprecate|disable|turn.off|get.rid|eliminate|unused|dead.code) ]]; then
  PRIMARY="brainstorming test-driven-development"
  PLABEL="Remove / Clean"
fi

# --- Review ---
if [[ -z "$PLABEL" && "$P" =~ (review|pull.?request|code.?review|check.*(code|changes|diff)|code.?quality|lint|smell|tech.?debt|(^|[^a-z])pr($|[^a-z])) ]]; then
  PRIMARY="requesting-code-review receiving-code-review"
  PLABEL="Review"
fi

# --- Ship / Complete ---
if [[ -z "$PLABEL" && "$P" =~ (ship|merge|deploy|push|release|tag|publish|pr.ready|ready.to|wrap.?up|all.(done|good|green|passing)|lgtm|finalize|complete|finish) ]]; then
  PRIMARY="verification-before-completion finishing-a-development-branch"
  PLABEL="Ship / Complete"
fi

# --- Investigate / Understand ---
if [[ -z "$PLABEL" && "$P" =~ (explain|understand|what.is|what.does|how.does|where.is|find|search|look.at|show.me|trace|investigate|analyze|profile|benchmark|measure|count|list|summarize|describe|walk.me|dig.into) ]]; then
  PRIMARY="systematic-debugging"
  PLABEL="Investigate"
fi

# --- Run / Test ---
if [[ -z "$PLABEL" && "$P" =~ (run|test|execute|verify|validate|check|ensure|confirm|try|attempt|evaluate|assert|expect|coverage|pass|green) ]]; then
  PRIMARY="test-driven-development"
  PLABEL="Run / Test"
fi

# =================================================================
# LAYER 2: CROSS-CUTTING OVERLAYS (additive)
# =================================================================
OVERLAY="" OLABEL=""

if [[ "$P" =~ (secur(e|ity)|vulnerab|owasp|pentest|attack|exploit|compliance|hipaa|gdpr|encrypt|auth(entication|orization)|inject|xss|csrf|sanitiz|supply.?chain) ]]; then
  OVERLAY+=" security-scanner"; OLABEL+="Security "
fi
if [[ "$P" =~ (^|[^a-z])(ui|frontend|component|layout|style|css|tailwind|responsive|dashboard|landing.?page|mockup|wireframe)($|[^a-z]) ]]; then
  OVERLAY+=" frontend-design webapp-testing"; OLABEL+="Frontend "
fi
if [[ "$P" =~ (proposal|spec[^a-z]|rfc|write.?up|technical.?doc|architecture.?doc|documentation) ]]; then
  OVERLAY+=" doc-coauthoring"; OLABEL+="Docs "
fi
if [[ "$P" =~ (claude\.md|claude.md|\.claude|skill|hook|mcp|plugin) ]]; then
  OVERLAY+=" claude-automation-recommender claude-md-improver writing-skills"; OLABEL+="Meta "
fi
if [[ "$P" =~ (parallel|concurrent|multiple.*(failure|bug|issue|error|test)|independent.*(task|failure|bug|issue|test)|worktree) ]]; then
  OVERLAY+=" dispatching-parallel-agents using-git-worktrees"; OLABEL+="Parallel "
fi

# =================================================================
# METHODOLOGY HINTS
# =================================================================
HINTS=""
if [[ -d "$PLUGIN_CACHE/ralph-loop" && "$P" =~ (migrate|refactor.all|fix.all|batch|overnight|autonom|iterate|keep.(going|trying|fixing)|until.*(pass|work|complet|succeed)|make.*tests?.pass|run.*until|loop|coverage|greenfield) ]]; then
  HINTS+="\n- RALPH LOOP: Consider /ralph-loop for autonomous iteration."
fi
if [[ -d "$PLUGIN_CACHE/pr-review-toolkit" && "$P" =~ (review|pull.?request|code.?review|(^|[^a-z])pr($|[^a-z])) ]]; then
  HINTS+="\n- PR REVIEW: Consider /pr-review for structured review."
fi

# =================================================================
# BUILD OUTPUT
# =================================================================
ALL_SKILLS=$(echo "$PRIMARY $OVERLAY" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ')

# Resolve paths, skip missing
TABLE="" COUNT=0
for skill in $ALL_SKILLS; do
  method=$(skill_path "$skill")
  [[ "$method" == "SKIP" ]] && continue
  TABLE+="  $skill -> $method\n"
  ((COUNT++))
done

# --- FALLTHROUGH: always emit phase checkpoint -------------------
# v8: We already filtered non-dev prompts above. If we got here,
# the prompt is likely dev-related. Always emit the phase checkpoint
# so Claude can self-assess intent, even with 0 skill matches.
[[ -z "$PLABEL" ]] && PLABEL="(Claude: assess intent)"

OLABEL="${OLABEL% }"

LABELS=""
[[ -n "$PLABEL" ]] && LABELS="$PLABEL"
if [[ -n "$OLABEL" ]]; then
  [[ -n "$LABELS" ]] && LABELS="$LABELS + $OLABEL" || LABELS="$OLABEL"
fi

# --- Assemble instruction ----------------------------------------
OUT="SKILL ACTIVATION ($COUNT skills | $LABELS)"

# Phase map ALWAYS included -- Claude does the real classification
OUT+="

Step 1 -- ASSESS PHASE. Check conversation context:
  DESIGN    -> brainstorming (ask questions, get approval)
  PLAN      -> writing-plans (break into tasks, confirm before execution)
  IMPLEMENT -> executing-plans or subagent-driven-development + TDD
  REVIEW    -> requesting-code-review
  SHIP      -> verification-before-completion + finishing-a-development-branch
  DEBUG     -> systematic-debugging, then return to current phase"

if (( COUNT > 0 )); then
  OUT+="

Step 2 -- EVALUATE skills against your phase assessment.
$(printf '%b' "$TABLE")
You MUST print a brief evaluation for each skill above. Format:
  **Phase: [PHASE]** | [skill1] YES/NO, [skill2] YES/NO
Example: **Phase: IMPLEMENT** | test-driven-development YES, claude-md-improver NO (not editing CLAUDE.md)
This line is MANDATORY -- do not skip it."
fi

OUT+="

Step 3 -- State your plan and proceed. Keep it to 1-2 sentences."

if [[ -n "$HINTS" ]]; then
  OUT+="\n$(printf '%b' "$HINTS")"
fi

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
  "$(printf '%s' "$OUT" | jq -Rs .)"
