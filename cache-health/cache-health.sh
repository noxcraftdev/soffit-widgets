#!/usr/bin/env bash
# Claude cache efficiency per session — cold%, hit%, churn rate
#
# Requires: claudelytics in PATH
# Data source: claudelytics --json cache-stats --session-id <uuid>
# Cache: stale-while-revalidate, 60s TTL, refresh locked for 30s

set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"

INPUT=$(cat)

# Pre-initialize so set -u doesn't abort if eval produces no output
COMPACT=False COMPONENTS="" ORANGE="" GREEN="" YELLOW="" DIM="" RESET="" SID=""

eval "$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cfg = d.get('config', {})
theme = cfg.get('theme', {})
data = d.get('data', {})
print(f'COMPACT={cfg.get(\"compact\", False)}')
print(f'COMPONENTS=\"{\",\".join(cfg.get(\"components\", []))}\"')
print(f'ORANGE=\"{theme.get(\"orange\", \"\")}\"')
print(f'GREEN=\"{theme.get(\"green\", \"\")}\"')
print(f'YELLOW=\"{theme.get(\"yellow\", \"\")}\"')
print(f'DIM=\"{theme.get(\"dim\", \"\")}\"')
print(f'RESET=\"{theme.get(\"reset\", \"\")}\"')
print(f'SID=\"{data.get(\"session_id\", \"\")}\"')
" 2>/dev/null)"

no_output() {
  echo '{"output": "--", "components": ["cold", "hit", "churn"]}'
}

[[ -z "$SID" ]] && { no_output; exit 0; }
command -v claudelytics &>/dev/null || { no_output; exit 0; }

CACHE="/tmp/soffit-cache-health-$SID"
LOCK="/tmp/soffit-cache-health-$SID.lock"

# Render from cached raw data, applying current theme colors on each call
render() {
  local raw
  raw=$(cat "$CACHE" 2>/dev/null) || return 1
  local cold hit churn
  cold=$(echo "$raw" | cut -f1)
  hit=$(echo "$raw" | cut -f2)
  churn=$(echo "$raw" | cut -f3)

  local parts=""
  local show_all=true
  [[ -n "$COMPONENTS" ]] && show_all=false

  if $show_all || echo "$COMPONENTS" | grep -q "cold"; then
    if [[ "$COMPACT" == "True" ]]; then
      parts="${ORANGE}${cold}${RESET}"
    else
      parts="${DIM}cold:${RESET}${ORANGE}${cold}${RESET}"
    fi
  fi

  if $show_all || echo "$COMPONENTS" | grep -q "hit"; then
    [[ -n "$parts" ]] && { [[ "$COMPACT" == "True" ]] && parts="$parts " || parts="$parts ${DIM}|${RESET} "; }
    if [[ "$COMPACT" == "True" ]]; then
      parts="${parts}${GREEN}${hit}${RESET}"
    else
      parts="${parts}${DIM}hit:${RESET}${GREEN}${hit}${RESET}"
    fi
  fi

  if [[ -n "$churn" ]] && { $show_all || echo "$COMPONENTS" | grep -q "churn"; }; then
    [[ -n "$parts" ]] && { [[ "$COMPACT" == "True" ]] && parts="$parts " || parts="$parts ${DIM}|${RESET} "; }
    if [[ "$COMPACT" == "True" ]]; then
      parts="${parts}${YELLOW}${churn}${RESET}"
    else
      parts="${parts}${DIM}churn:${RESET}${YELLOW}${churn}${RESET}"
    fi
  fi

  echo -e "{\"output\": \"$parts\", \"components\": [\"cold\", \"hit\", \"churn\"]}"
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
  DATA=$(claudelytics --json cache-stats --session-id "$SID" 2>/dev/null) || exit 0
  TMPFILE=$(mktemp)
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
cold = str(round(d['cold_pct'] * 100)) + '%'
hit = str(round(d['hit_pct'] * 100)) + '%'
v = d.get('churn_tokens_per_turn')
churn = '{:.1f}k/t'.format(v / 1000) if v is not None else ''
sys.stdout.write(cold + '\t' + hit + '\t' + churn)
" "$DATA" > "$TMPFILE" && mv "$TMPFILE" "$CACHE" || rm -f "$TMPFILE"
) & disown
