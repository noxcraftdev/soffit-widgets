#!/usr/bin/env bash
# Daily budget pacing -- hours remaining at current burn rate
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

GREEN="" YELLOW="" RED="" DIM="" RESET="" ICON="" COMPACT=False

eval "$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cfg = d.get('config', {})
palette = cfg.get('palette', {})
icons = cfg.get('icons', {})
print(f'GREEN=\"{palette.get(\"success\", \"\")}\"')
print(f'YELLOW=\"{palette.get(\"warning\", \"\")}\"')
print(f'RED=\"{palette.get(\"danger\", \"\")}\"')
print(f'DIM=\"{palette.get(\"muted\", \"\")}\"')
print(f'RESET=\"{palette.get(\"reset\", \"\")}\"')
print(f'ICON=\"{icons.get(\"icon\", \"\")}\"')
print(f'COMPACT={cfg.get(\"compact\", False)}')
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

  local color label tier

  if [[ "$over_budget" == "true" ]]; then
    tier=red
    label="OVER"
  else
    # Format time remaining in bash
    local h_float="$hours_remaining"
    local total_m
    total_m=$(python3 -c "print(int(max(0.0, float('$h_float')) * 60))" 2>/dev/null || echo 0)
    local hrs=$(( total_m / 60 ))
    local mins=$(( total_m % 60 ))
    if (( hrs > 0 )); then
      label="${hrs}h ${mins}m left"
    else
      label="${mins}m left"
    fi

    # Determine tier from pct
    local pct_int
    pct_int=$(python3 -c "print(int(float('$pct')))" 2>/dev/null || echo 0)
    if (( pct_int > 50 )); then
      tier=green
    elif (( pct_int > 10 )); then
      tier=yellow
    else
      tier=red
    fi
  fi

  case "$tier" in
    green)  color="$GREEN" ;;
    yellow) color="$YELLOW" ;;
    *)      color="$RED" ;;
  esac

  local output
  if [[ "$COMPACT" == "True" ]]; then
    # Compact: colored status word
    case "$tier" in
      green)  output="${color}ok${RESET}" ;;
      yellow) output="${color}low${RESET}" ;;
      *)      output="${color}stop${RESET}" ;;
    esac
  else
    if [[ -n "$ICON" ]]; then
      output="${DIM}${ICON}${RESET}${color}${label}${RESET}"
    else
      output="${color}${label}${RESET}"
    fi
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
  echo "$DATA" | python3 -c "
import json, sys
d = json.load(sys.stdin)
hours_remaining = d['hours_remaining']
over_budget = 'true' if d['over_budget'] else 'false'
budget = float(sys.argv[1])
today_cost = d['today_cost']
pct_remaining = max(0.0, (budget - today_cost) / budget * 100) if budget > 0 else 0.0
sys.stdout.write(str(hours_remaining) + '\t' + over_budget + '\t' + str(pct_remaining))
" "$BUDGET" > "$TMPFILE" && mv "$TMPFILE" "$CACHE" || rm -f "$TMPFILE"
) & disown
