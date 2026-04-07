#!/usr/bin/env bash
# Vim mode indicator.
#
# Shows the current vim mode (NORMAL, INSERT, VISUAL, etc.)

set -euo pipefail

python3 << 'PYEOF'
import json, sys

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

data = d.get('data', {})
palette = d.get('config', {}).get('palette', {})

vim = data.get('vim') or {}
mode = (vim.get('mode') or '').strip()
if not mode:
    sys.exit(0)

accent = palette.get('accent', '')
reset = palette.get('reset', '')

print(f'{accent}{mode}{reset}', end='')
PYEOF
