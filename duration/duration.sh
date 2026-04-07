#!/usr/bin/env bash
# Session duration with time-based color thresholds.
#
# >= 2h: danger, >= 1h: warning, >= 30m: muted, < 30m: subtle

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

cost = data.get('cost') or {}
ms = cost.get('total_duration_ms')
if ms is None:
    sys.exit(0)

ms = int(ms)
reset = palette.get('reset', '')

if ms >= 7_200_000:
    color = palette.get('danger', '')
elif ms >= 3_600_000:
    color = palette.get('warning', '')
elif ms >= 1_800_000:
    color = palette.get('muted', '')
else:
    color = palette.get('subtle', '')

s = ms // 1000
if s == 0:
    fmt = '0s'
elif s < 60:
    fmt = f'{s}s'
elif s < 3600:
    fmt = f'{s // 60}m{s % 60:02d}s'
else:
    fmt = f'{s // 3600}h{(s % 3600) // 60:02d}m'

if compact:
    print(f'{color}{fmt}{reset}', end='')
else:
    icon = icons.get('duration', '\u23f1 ')
    print(f'{color}{icon}{fmt}{reset}', end='')
PYEOF
