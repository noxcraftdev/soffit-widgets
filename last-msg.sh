#!/bin/bash
# Show the time of the last Claude response in this session
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
print(f'DIM=\"{theme.get(\"dim\", \"\")}\"')
print(f'LGRAY=\"{theme.get(\"lgray\", \"\")}\"')
print(f'RESET=\"{theme.get(\"reset\", \"\")}\"')
print(f'ICON=\"{icons.get(\"icon\", \"Last Msg: \")}\"')
" 2>/dev/null)"

TIMESTAMP=$(date +%H:%M:%S)

if [ "$COMPACT" = "True" ]; then
  echo -e "{\"output\": \"${LGRAY}${TIMESTAMP}${RESET}\", \"components\": [\"time\"]}"
else
  echo -e "{\"output\": \"${DIM}${ICON}${RESET}${LGRAY}${TIMESTAMP}${RESET}\", \"components\": [\"time\"]}"
fi
