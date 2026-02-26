#!/bin/bash
# teammate-idle-guard.sh — Conditional heartbeat for agent team teammates
# Checks if the idle teammate has unfinished tasks before nudging.
# Exit 0 = allow idle. Exit 2 = nudge (stderr fed back to teammate).

# jq is required to parse teammate/task data
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

INPUT=$(cat)
TEAMMATE=$(printf '%s' "$INPUT" | jq -r '.teammate_name // empty' 2>/dev/null)
TEAM=$(printf '%s' "$INPUT" | jq -r '.team_name // empty' 2>/dev/null)

# No teammate info = allow idle
if [ -z "$TEAMMATE" ] || [ -z "$TEAM" ]; then
    exit 0
fi

TASKS_DIR="${HOME}/.claude/tasks/${TEAM}"

# No task directory = no team tasks = allow idle
[ ! -d "$TASKS_DIR" ] && exit 0

# Check if this teammate owns any in_progress tasks
UNFINISHED=""
for task_file in "${TASKS_DIR}"/*.json; do
    [ -f "$task_file" ] || continue
    MATCH=$(jq -r --arg owner "$TEAMMATE" \
        'select(.owner == $owner and .status == "in_progress") | .subject' \
        "$task_file" 2>/dev/null)
    if [ -n "$MATCH" ]; then
        [ -n "$UNFINISHED" ] && UNFINISHED="${UNFINISHED}, "
        UNFINISHED="${UNFINISHED}${MATCH}"
    fi
done

if [ -n "$UNFINISHED" ]; then
    # Cooldown: skip nudge if < 120 seconds since last nudge for this teammate
    SAFE_TEAM=$(printf '%s' "$TEAM" | tr -cd 'a-zA-Z0-9_-')
    SAFE_MATE=$(printf '%s' "$TEAMMATE" | tr -cd 'a-zA-Z0-9_-')
    COOLDOWN_DIR="${HOME}/.claude/.idle-cooldowns"
    mkdir -p "$COOLDOWN_DIR" 2>/dev/null || COOLDOWN_DIR="/tmp"
    COOLDOWN_FILE="${COOLDOWN_DIR}/claude-idle-${SAFE_TEAM}-${SAFE_MATE}-last-nudge"
    NOW=$(date +%s) || NOW=""
    if [ -n "$NOW" ] && [ -f "$COOLDOWN_FILE" ]; then
        LAST_NUDGE=$(cat "$COOLDOWN_FILE" 2>/dev/null) || LAST_NUDGE=""
        if [[ "$LAST_NUDGE" =~ ^[0-9]+$ ]]; then
            ELAPSED=$((NOW - LAST_NUDGE))
            if [ "$ELAPSED" -lt 120 ]; then
                exit 0
            fi
        fi
    fi
    if [ -n "$NOW" ]; then
        printf '%s' "$NOW" > "$COOLDOWN_FILE" 2>/dev/null || true
    fi
    echo "You have unfinished tasks: ${UNFINISHED}. Continue working or report your blocker to the lead via SendMessage." >&2
    exit 2
fi

exit 0
