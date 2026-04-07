#!/usr/bin/env bash
# Active agent name.
#
# Shows the name of the currently active agent/tool.

set -euo pipefail

python3 << 'PYEOF'
import json, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

data = d.get('data', {})
cfg = d.get('config', {})
palette = cfg.get('palette', {})
icons = cfg.get('icons', {})
compact = cfg.get('compact', False)

agent = data.get('agent') or {}
name = (agent.get('name') or '').strip()
if not name:
    sys.exit(0)

warning = palette.get('warning', '')
reset = palette.get('reset', '')
icon = icons.get('agent', '\u276f ')

if compact:
    print(f'{warning}{name}{reset}', end='')
else:
    print(f'{warning}{icon}{name}{reset}', end='')
PYEOF
