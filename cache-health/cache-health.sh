#!/usr/bin/env bash
# Claude cache efficiency per session -- health grade + detailed metrics
#
# Requires: claudelytics in PATH
# Data source: claudelytics --json cache-stats --session-id <uuid>
# Cache: stale-while-revalidate, 60s TTL, refresh locked for 30s

set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

INPUT=$(cat)

# Pre-initialize so set -u doesn't abort if eval produces no output
COMPACT=False COMPONENTS="" ORANGE="" GREEN="" YELLOW="" DIM="" RESET="" SID=""
CACHE_TTL=60 HEALTHY_THRESHOLD=70 MODERATE_THRESHOLD=40

eval "$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cfg = d.get('config', {})
palette = cfg.get('palette', {})
settings = cfg.get('settings', {})
data = d.get('data', {})
print(f'COMPACT={cfg.get(\"compact\", False)}')
print('COMPONENTS=\"' + ','.join(cfg.get('components', [])) + '\"')
print(f'ORANGE=\"{palette.get(\"warning\", \"\")}\"')
print(f'GREEN=\"{palette.get(\"success\", \"\")}\"')
print(f'YELLOW=\"{palette.get(\"warning\", \"\")}\"')
print(f'DIM=\"{palette.get(\"muted\", \"\")}\"')
print(f'RESET=\"{palette.get(\"reset\", \"\")}\"')
print(f'SID=\"{data.get(\"session_id\", \"\")}\"')
print(f'CACHE_TTL={settings.get(\"cache_ttl\", 60)}')
print(f'HEALTHY_THRESHOLD={settings.get(\"healthy_threshold\", 70)}')
print(f'MODERATE_THRESHOLD={settings.get(\"moderate_threshold\", 40)}')
" 2>/dev/null)"

no_output() {
  echo '{"output": "--", "components": ["grade", "cold", "hit", "churn"]}'
}

# Fallback: find most recently modified JSONL when soffit doesn't send session_id
if [[ -z "$SID" ]]; then
  SID=$(python3 -c "
import os, glob
paths = []
for d in [os.path.expanduser('~/.claude/projects'), os.path.expanduser('~/.config/claude/projects')]:
    if os.path.isdir(d):
        paths.extend(glob.glob(os.path.join(d, '*', '*.jsonl')))
if paths:
    newest = max(paths, key=os.path.getmtime)
    print(os.path.splitext(os.path.basename(newest))[0])
" 2>/dev/null)
fi
[[ -z "$SID" ]] && { no_output; exit 0; }
command -v claudelytics &>/dev/null || { no_output; exit 0; }

CACHE="/tmp/soffit-cache-health-$SID"
LOCK="/tmp/soffit-cache-health-$SID.lock"

# Check if a specific component is requested
has_component() {
  local name="$1"
  [[ -z "$COMPONENTS" ]] && return 0  # show all
  local IFS=','
  for c in $COMPONENTS; do
    [[ "$c" == "$name" ]] && return 0
  done
  return 1
}

# Render from cached raw data, applying current theme colors on each call
render() {
  local raw
  raw=$(cat "$CACHE" 2>/dev/null) || return 1
  local cold hit churn
  cold=$(echo "$raw" | cut -f1)
  hit=$(echo "$raw" | cut -f2)
  churn=$(echo "$raw" | cut -f3)

  # Extract hit percentage number for grade calculation
  local hit_num
  hit_num="${hit%\%}"

  local parts=""

  # Health grade: single colored word based on hit%
  if has_component "grade"; then
    local grade_color grade_label
    if (( hit_num >= HEALTHY_THRESHOLD )); then
      grade_color="$GREEN"
      grade_label="healthy"
    elif (( hit_num >= MODERATE_THRESHOLD )); then
      grade_color="$ORANGE"
      grade_label="moderate"
    else
      grade_color="$ORANGE"
      grade_label="poor"
    fi

    if [[ "$COMPACT" == "True" ]]; then
      parts="${grade_color}${grade_label}${RESET}"
    else
      parts="${DIM}cache:${RESET}${grade_color}${grade_label}${RESET}"
    fi
  fi

  # Detailed metrics (opt-in for power users)
  if has_component "cold"; then
    [[ -n "$parts" ]] && { [[ "$COMPACT" == "True" ]] && parts="$parts " || parts="$parts ${DIM}|${RESET} "; }
    if [[ "$COMPACT" == "True" ]]; then
      parts="${parts}${ORANGE}${cold}${RESET}"
    else
      parts="${parts}${DIM}cold:${RESET}${ORANGE}${cold}${RESET}"
    fi
  fi

  if has_component "hit"; then
    [[ -n "$parts" ]] && { [[ "$COMPACT" == "True" ]] && parts="$parts " || parts="$parts ${DIM}|${RESET} "; }
    if [[ "$COMPACT" == "True" ]]; then
      parts="${parts}${GREEN}${hit}${RESET}"
    else
      parts="${parts}${DIM}hit:${RESET}${GREEN}${hit}${RESET}"
    fi
  fi

  if [[ -n "$churn" ]] && has_component "churn"; then
    [[ -n "$parts" ]] && { [[ "$COMPACT" == "True" ]] && parts="$parts " || parts="$parts ${DIM}|${RESET} "; }
    if [[ "$COMPACT" == "True" ]]; then
      parts="${parts}${YELLOW}${churn}${RESET}"
    else
      parts="${parts}${DIM}churn:${RESET}${YELLOW}${churn}${RESET}"
    fi
  fi

  echo -e "{\"output\": \"$parts\", \"components\": [\"grade\", \"cold\", \"hit\", \"churn\"]}"
}

if [[ -f "$CACHE" ]]; then
  render
else
  no_output
fi

# Check if cache is fresh (< 60s)
if [[ -f "$CACHE" ]]; then
  NOW=$(date +%s)
  MTIME=$(stat -c %Y "$CACHE" 2>/dev/null || echo 0)
  AGE=$(( NOW - MTIME ))
  (( AGE < CACHE_TTL )) && exit 0
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
  DATA=$(claudelytics --json cache-stats --session-id "$SID" 2>/dev/null) || exit 0
  TMPFILE=$(mktemp)
  echo "$DATA" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cold = str(round(d['cold_pct'] * 100)) + '%'
hit = str(round(d['hit_pct'] * 100)) + '%'
v = d.get('churn_tokens_per_turn')
churn = '{:.1f}k/t'.format(v / 1000) if v is not None else ''
sys.stdout.write(cold + '\t' + hit + '\t' + churn)
" > "$TMPFILE" && mv "$TMPFILE" "$CACHE" || rm -f "$TMPFILE"
) & disown
