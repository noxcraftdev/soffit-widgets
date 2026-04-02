#!/bin/bash
# Pomodoro timer widget
#
# Control commands (run from your shell, not from soffit):
#   Start a session:  echo $(date +%s) > /tmp/soffit-pomodoro
#   Stop a session:   rm /tmp/soffit-pomodoro
#
# Uses theme colors and icons from soffit config for customizable appearance.

INPUT=$(cat)

eval "$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cfg = d.get('config', {})
theme = cfg.get('theme', {})
icons = cfg.get('icons', {})
print(f'COMPACT={cfg.get(\"compact\", False)}')
print(f'GREEN=\"{theme.get(\"green\", \"\")}\"')
print(f'ORANGE=\"{theme.get(\"orange\", \"\")}\"')
print(f'DIM=\"{theme.get(\"dim\", \"\")}\"')
print(f'RESET=\"{theme.get(\"reset\", \"\")}\"')
print(f'ICON=\"{icons.get(\"icon\", \"\U0001f345 \")}\"')
print(f'BELL=\"{icons.get(\"bell\", \"\U0001f514\")}\"')
" 2>/dev/null)"

STATE_FILE="/tmp/soffit-pomodoro"
WORK_MINS=25

# No active session
if [ ! -f "$STATE_FILE" ]; then
  if [ "$COMPACT" = "True" ]; then
    echo -e "{\"output\": \"${DIM}\u23f8${RESET}\", \"components\": [\"timer\", \"status\"]}"
  else
    echo -e "{\"output\": \"${DIM}${ICON}idle${RESET}\", \"components\": [\"timer\", \"status\"]}"
  fi
  exit 0
fi

START=$(cat "$STATE_FILE")
NOW=$(date +%s)
ELAPSED=$(( (NOW - START) / 60 ))
REMAINING=$(( WORK_MINS - ELAPSED ))

# Session over
if [ "$REMAINING" -le 0 ]; then
  if [ "$COMPACT" = "True" ]; then
    echo -e "{\"output\": \"${ORANGE}${BELL}BREAK${RESET}\", \"components\": [\"timer\", \"status\"]}"
  else
    echo -e "{\"output\": \"${ORANGE}${ICON}break time!${RESET}\", \"components\": [\"timer\", \"status\"]}"
  fi
  exit 0
fi

# Session in progress
if [ "$COMPACT" = "True" ]; then
  echo -e "{\"output\": \"${GREEN}${REMAINING}m${RESET}\", \"components\": [\"timer\", \"status\"]}"
else
  echo -e "{\"output\": \"${GREEN}${ICON}${REMAINING}m left${RESET}\", \"components\": [\"timer\", \"status\"]}"
fi
