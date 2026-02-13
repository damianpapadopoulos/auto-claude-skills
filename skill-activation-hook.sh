#!/bin/bash
# --- Claude Code Skill Activation Hook v7 -----------------------
# https://github.com/dkpapapadopoulos/auto-claude-skills
#
# Hybrid intent routing with phase-aware checkpoints.
#
# The regex is a FAST PRE-FILTER, not the decision maker.
# Claude Code (already running) makes the real intent assessment
# via the phase checkpoint instruction injected into context.
# No extra API call needed -- Claude IS the classifier.
#
# Three layers: Primary Intent -> Cross-cutting Overlays -> Phase Check
# The hook suggests; Claude decides; the user overrides.
# -----------------------------------------------------------------
set -uo pipefail

PROMPT=$(cat 2>/dev/null | jq -r '.prompt // empty' 2>/dev/null) || true

# --- Early exits -------------------------------------------------
[[ -z "$PROMPT" ]] && exit 0
[[ "$PROMPT" =~ ^[[:space:]]/ ]] && exit 0
(( ${#PROMPT} < 8 )) && exit 0

P="${PROMPT,,}"

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
# This is a suggestion -- Claude's phase assessment decides.
# =================================================================
PRIMARY="" PLABEL=""

if [[ -z "$PLABEL" && "$P" =~ (debug|bug|fix(es|ed|ing)?|broken|fail(ing|ure)|error|crash|wrong|unexpected|not.working|regression|issue.with|problem.with|doesn.t.work|won.t.(start|run|compile|build)) ]]; then
  PRIMARY="systematic-debugging test-driven-development"
  PLABEL="Fix / Debug"
fi

if [[ -z "$PLABEL" && "$P" =~ (execute.*(plan|tasks)|run.the.plan|implement.the.plan|implement.*(rest|remaining).*(plan|tasks)|continue.*(plan|implementation|from.yesterday|where)|follow.the.plan|pick.up.where|resume|next.task) ]]; then
  PRIMARY="subagent-driven-development executing-plans"
  PLABEL="Plan Execution"
fi

if [[ -z "$PLABEL" && "$P" =~ (build|create|implement|develop|scaffold|init|bootstrap|brainstorm|design|architect|strateg|scope|outline|approach|set.?up.*(project|app|system|service|api|server|module)|add.*(feature|endpoint|module|component|page|route|handler)|write.*(code|function|class|module|test|script)|how.(should|would|could).(we|i)) ]]; then
  PRIMARY="brainstorming test-driven-development"
  PLABEL="Build New"
fi

if [[ -z "$PLABEL" && "$P" =~ (review|pull.?request|code.?review|check.(this|my|the).(code|changes|diff)|refactor|clean.?up|code.?quality|lint|smell|tech.?debt) ]]; then
  PRIMARY="requesting-code-review receiving-code-review"
  PLABEL="Review"
fi
if [[ -z "$PLABEL" && "$P" =~ (^|[^a-z])pr($|[^a-z]) ]]; then
  PRIMARY="requesting-code-review receiving-code-review"
  PLABEL="Review"
fi

if [[ -z "$PLABEL" && "$P" =~ (ship|merge|deploy|push.to.(main|prod|master)|pr.ready|ready.to.(merge|deploy|ship)|wrap.?up|all.(done|good|green|passing)|lgtm|looks.good.*(ship|merge|deploy)) ]]; then
  PRIMARY="verification-before-completion finishing-a-development-branch"
  PLABEL="Ship / Complete"
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
if [[ "$P" =~ (proposal|spec[^a-z]|rfc|write.?up|technical.?doc|architecture.?doc) ]]; then
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

# --- FALLTHROUGH: no regex match ---------------------------------
# If keywords missed but prompt looks dev-related, still emit the
# phase checkpoint so Claude can assess intent itself.
# Claude IS the LLM -- no extra API call needed.
if [[ $COUNT -eq 0 && -z "$HINTS" ]]; then
  if [[ "$P" =~ (code|test|api|function|class|module|file|repo|branch|commit|database|server|endpoint|config|docker|package|dependency|library|service|feature|task|ticket|sprint|release|version|migration|schema|model|component|route|controller|middleware|plan|ready|done|looks.good|approved|go.ahead|proceed|next.step|move.on) ]]; then
    PLABEL="(no keyword match)"
  else
    exit 0
  fi
fi

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
For each: [name] YES/NO [reason]. Phase overrides keyword match."
fi

OUT+="

Step 3 -- CONFIRM with user. State your phase and plan. Ask before proceeding.

Step 4 -- ACTIVATE approved skills. Follow their internal chain."

if [[ -n "$HINTS" ]]; then
  OUT+="\n$(printf '%b' "$HINTS")"
fi

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
  "$(printf '%s' "$OUT" | jq -Rs .)"
