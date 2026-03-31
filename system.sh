#!/bin/bash
# Example soffit plugin: system stats (CPU load, memory usage, uptime)
#
# Reads /proc/loadavg and /proc/meminfo directly — no external commands
# beyond `free` and `uptime`, so it's fast enough for every render cycle.

INPUT=$(cat)

COMPACT=$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('config', {}).get('compact', False))
" 2>/dev/null)

COMPONENTS=$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(','.join(d.get('config', {}).get('components', [])))
" 2>/dev/null)

LOAD=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo "?")
MEM=$(free -m 2>/dev/null | awk '/Mem:/{printf "%.0f%%", $3/$2*100}')
UP=$(uptime -p 2>/dev/null | sed 's/up //' | sed 's/ hours\?/h/' | sed 's/ minutes\?/m/' | sed 's/, //' || echo "?")

parts=""
show_all=true
[ -n "$COMPONENTS" ] && show_all=false

# CPU load component
if $show_all || echo "$COMPONENTS" | grep -q "cpu"; then
  if [ "$COMPACT" = "True" ]; then
    parts="${parts}${LOAD}"
  else
    parts="${parts}⚡${LOAD}"
  fi
fi

# Memory component
if $show_all || echo "$COMPONENTS" | grep -q "mem"; then
  [ -n "$parts" ] && { [ "$COMPACT" = "True" ] && parts="$parts " || parts="$parts | "; }
  if [ "$COMPACT" = "True" ]; then
    parts="${parts}${MEM}"
  else
    parts="${parts}🧠${MEM}"
  fi
fi

# Uptime component
if $show_all || echo "$COMPONENTS" | grep -q "uptime"; then
  [ -n "$parts" ] && { [ "$COMPACT" = "True" ] && parts="$parts " || parts="$parts | "; }
  if [ "$COMPACT" = "True" ]; then
    parts="${parts}${UP}"
  else
    parts="${parts}⏳${UP}"
  fi
fi

echo "{\"output\": \"$parts\", \"components\": [\"cpu\", \"mem\", \"uptime\"]}"
