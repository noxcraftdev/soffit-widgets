#!/usr/bin/env bash
# System stats: CPU 1-minute load average, memory usage, and uptime
#
# Uses theme colors and icons from soffit config for customizable appearance.
# Memory color adapts to usage: green < 50%, orange 50-80%, red >= 80%.

set -euo pipefail

INPUT=$(cat)

COMPACT=False COMPONENTS="" DIM="" LGRAY="" GREEN="" ORANGE="" RED="" RESET="" ICON_CPU="" ICON_MEM="" ICON_UP=""

eval "$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cfg = d.get('config', {})
palette = cfg.get('palette', {})
icons = cfg.get('icons', {})
print(f'COMPACT={cfg.get(\"compact\", False)}')
print('COMPONENTS=\"' + ','.join(cfg.get('components', [])) + '\"')
print(f'DIM=\"{palette.get(\"muted\", \"\")}\"')
print(f'LGRAY=\"{palette.get(\"subtle\", \"\")}\"')
print(f'GREEN=\"{palette.get(\"success\", \"\")}\"')
print(f'ORANGE=\"{palette.get(\"warning\", \"\")}\"')
print(f'RED=\"{palette.get(\"danger\", \"\")}\"')
print(f'RESET=\"{palette.get(\"reset\", \"\")}\"')
print(f'ICON_CPU=\"{icons.get(\"cpu\", \"\u26a1\")}\"')
print(f'ICON_MEM=\"{icons.get(\"mem\", \"\U0001f9e0\")}\"')
print(f'ICON_UP=\"{icons.get(\"uptime\", \"\u231b\")}\"')
" 2>/dev/null)"

LOAD=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo "?")
MEM_PCT=$(free 2>/dev/null | awk '/Mem:/{printf "%.0f", $3/$2*100}')
MEM="${MEM_PCT:-?}%"
UP=$(uptime -p 2>/dev/null | sed 's/up //' | sed 's/ hours\?/h/' | sed 's/ minutes\?/m/' | sed 's/, //' || echo "?")

# Pick memory color based on usage
if [ "${MEM_PCT:-0}" -ge 80 ] 2>/dev/null; then
  MEM_COL="$RED"
elif [ "${MEM_PCT:-0}" -ge 50 ] 2>/dev/null; then
  MEM_COL="$ORANGE"
else
  MEM_COL="$GREEN"
fi

parts=""
show_all=true
[ -n "$COMPONENTS" ] && show_all=false

if $show_all || echo "$COMPONENTS" | grep -q "cpu"; then
  if [ "$COMPACT" = "True" ]; then
    parts="${parts}${LGRAY}${LOAD}${RESET}"
  else
    parts="${parts}${DIM}${ICON_CPU}${RESET}${LGRAY}${LOAD}${RESET}"
  fi
fi

if $show_all || echo "$COMPONENTS" | grep -q "mem"; then
  [ -n "$parts" ] && { [ "$COMPACT" = "True" ] && parts="$parts " || parts="$parts ${DIM}|${RESET} "; }
  if [ "$COMPACT" = "True" ]; then
    parts="${parts}${MEM_COL}${MEM}${RESET}"
  else
    parts="${parts}${DIM}${ICON_MEM}${RESET}${MEM_COL}${MEM}${RESET}"
  fi
fi

if $show_all || echo "$COMPONENTS" | grep -q "uptime"; then
  [ -n "$parts" ] && { [ "$COMPACT" = "True" ] && parts="$parts " || parts="$parts ${DIM}|${RESET} "; }
  if [ "$COMPACT" = "True" ]; then
    parts="${parts}${DIM}${UP}${RESET}"
  else
    parts="${parts}${DIM}${ICON_UP}${UP}${RESET}"
  fi
fi

echo -e "{\"output\": \"$parts\", \"components\": [\"cpu\", \"mem\", \"uptime\"]}"
