#!/usr/bin/env bash
# Daily budget pacing — hours remaining at current burn rate
#
# Requires: claudelytics in PATH, CLAUDELYTICS_DAILY_BUDGET env var set
# Cache: stale-while-revalidate, 60s TTL, refresh locked for 30s

set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

BUDGET="${CLAUDELYTICS_DAILY_BUDGET:-}"
if [[ -z "$BUDGET" ]]; then
  echo '{"output": "--", "components": ["clock"]}'
  exit 0
fi

INPUT=$(cat)

# Pre-initialize so set -u doesn't abort if eval produces no output
GREEN="" YELLOW="" RED="" DIM="" RESET="" ICON=""

eval "$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cfg = d.get('config', {})
theme = cfg.get('theme', {})
icons = cfg.get('icons', {})
print(f'GREEN=\"{theme.get(\"green\", \"\")}\"')
print(f'YELLOW=\"{theme.get(\"yellow\", \"\")}\"')
print(f'RED=\"{theme.get(\"red\", \"\")}\"')
print(f'DIM=\"{theme.get(\"dim\", \"\")}\"')
print(f'RESET=\"{theme.get(\"reset\", \"\")}\"')
print(f'ICON=\"{icons.get(\"icon\", \"\")}\"')
" 2>/dev/null)"

command -v claudelytics &>/dev/null || {
  echo '{"output": "claudelytics not found", "components": ["clock"]}'
  exit 0
}

CACHE="/tmp/soffit-budget-clock"
LOCK="/tmp/soffit-budget-clock.lock"

# Render from cached raw data, applying current theme colors on each call
render() {
  local raw
  raw=$(cat "$CACHE" 2>/dev/null) || return 1
  local hours_remaining over_budget pct
  hours_remaining=$(echo "$raw" | cut -f1)
  over_budget=$(echo "$raw" | cut -f2)
  pct=$(echo "$raw" | cut -f3)

  local color label color_and_label tier
  color_and_label=$(python3 -c "
import sys
over = '$over_budget' == 'true'
h = float('$hours_remaining') if not over else 0.0
p = float('$pct') if not over else 0.0
if over:
    print('red\tOVER')
else:
    total_m = int(max(0.0, h) * 60)
    hrs = total_m // 60
    mins = total_m % 60
    lbl = f'{hrs}h {mins}m left' if hrs > 0 else f'{mins}m left'
    tier = 'green' if p > 50 else ('yellow' if p > 10 else 'red')
    print(tier + '\t' + lbl)
")
  tier=$(echo "$color_and_label" | cut -f1)
  label=$(echo "$color_and_label" | cut -f2)

  case "$tier" in
    green)  color="$GREEN" ;;
    yellow) color="$YELLOW" ;;
    *)      color="$RED" ;;
  esac

  local output
  if [[ -n "$ICON" ]]; then
    output="${DIM}${ICON}${RESET}${color}${label}${RESET}"
  else
    output="${color}${label}${RESET}"
  fi

  echo -e "{\"output\": \"$output\", \"components\": [\"clock\"]}"
}

if [[ -f "$CACHE" ]]; then
  render
else
  echo '{"output": "--", "components": ["clock"]}'
fi

# Check if cache is fresh (< 60s)
if [[ -f "$CACHE" ]]; then
  NOW=$(date +%s)
  MTIME=$(stat -c %Y "$CACHE" 2>/dev/null || echo 0)
  AGE=$(( NOW - MTIME ))
  (( AGE < 60 )) && exit 0
fi

# Check for running refresh (lock < 30s)
if [[ -f "$LOCK" ]]; then
  NOW=$(date +%s)
  LMTIME=$(stat -c %Y "$LOCK" 2>/dev/null || echo 0)
  LAGE=$(( NOW - LMTIME ))
  (( LAGE < 30 )) && exit 0
fi

rm -f "$LOCK"
touch "$LOCK"

(
  trap 'rm -f "$LOCK"' EXIT
  DATA=$(claudelytics --json budget-status --budget "$BUDGET" 2>/dev/null) || exit 0
  TMPFILE=$(mktemp)
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
hours_remaining = d['hours_remaining']
over_budget = 'true' if d['over_budget'] else 'false'
budget = float(sys.argv[2])
today_cost = d['today_cost']
pct_remaining = max(0.0, (budget - today_cost) / budget * 100) if budget > 0 else 0.0
sys.stdout.write(str(hours_remaining) + '\t' + over_budget + '\t' + str(pct_remaining))
" "$DATA" "$BUDGET" > "$TMPFILE" && mv "$TMPFILE" "$CACHE" || rm -f "$TMPFILE"
) & disown
