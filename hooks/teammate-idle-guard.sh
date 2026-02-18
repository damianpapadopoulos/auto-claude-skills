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
    echo "You have unfinished tasks: ${UNFINISHED}. Continue working or report your blocker to the lead via SendMessage." >&2
    exit 2
fi

exit 0
