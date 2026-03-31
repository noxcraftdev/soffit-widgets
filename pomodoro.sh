#!/bin/bash
# Example soffit plugin: Pomodoro timer
#
# Control commands (run from your shell, not from soffit):
#   Start a session:  echo $(date +%s) > /tmp/soffit-pomodoro
#   Stop a session:   rm /tmp/soffit-pomodoro
#
# The plugin reads that state file on every render and computes how many
# minutes remain. No background process needed.

INPUT=$(cat)

COMPACT=$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('config', {}).get('compact', False))
" 2>/dev/null)

STATE_FILE="/tmp/soffit-pomodoro"
WORK_MINS=25

# No active session
if [ ! -f "$STATE_FILE" ]; then
  if [ "$COMPACT" = "True" ]; then
    echo '{"output": "⏸", "components": ["timer", "status"]}'
  else
    echo '{"output": "🍅 idle", "components": ["timer", "status"]}'
  fi
  exit 0
fi

START=$(cat "$STATE_FILE")
NOW=$(date +%s)
ELAPSED=$(( (NOW - START) / 60 ))
REMAINING=$(( WORK_MINS - ELAPSED ))

# Session over — time for a break
if [ "$REMAINING" -le 0 ]; then
  if [ "$COMPACT" = "True" ]; then
    echo '{"output": "🔔BREAK", "components": ["timer", "status"]}'
  else
    echo '{"output": "🍅 break time!", "components": ["timer", "status"]}'
  fi
  exit 0
fi

# Session in progress
if [ "$COMPACT" = "True" ]; then
  echo "{\"output\": \"${REMAINING}m\", \"components\": [\"timer\", \"status\"]}"
else
  echo "{\"output\": \"🍅 ${REMAINING}m left\", \"components\": [\"timer\", \"status\"]}"
fi
