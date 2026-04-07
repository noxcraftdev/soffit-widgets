#!/usr/bin/env bash
# Shortest unique session ID prefix.
#
# Scans ~/.claude/projects for session JSONL files and computes
# the shortest prefix of the current session ID that is unique.

set -euo pipefail

INPUT=$(cat)
export SOFFIT_INPUT="$INPUT"

python3 << 'PYEOF'
import json, sys, os, glob, time

try:
    d = json.loads(os.environ.get('SOFFIT_INPUT', '{}'))
except Exception:
    sys.exit(0)

data = d.get('data', {})
palette = d.get('config', {}).get('palette', {})

sid = (data.get('session_id') or '').strip()
if not sid:
    sys.exit(0)

muted = palette.get('muted', '')
reset = palette.get('reset', '')

# Collect all session IDs from ~/.claude/projects (cached 30s)
CACHE_PATH = '/tmp/soffit-sid-cache'
all_sids = []

try:
    mtime = os.path.getmtime(CACHE_PATH)
    if time.time() - mtime < 30:
        with open(CACHE_PATH) as f:
            all_sids = [l.strip() for l in f if l.strip()]
except (OSError, ValueError):
    pass

if not all_sids:
    home = os.path.expanduser('~')
    projects_dir = os.path.join(home, '.claude', 'projects')
    if os.path.isdir(projects_dir):
        for root, dirs, files in os.walk(projects_dir):
            depth = root[len(projects_dir):].count(os.sep)
            if depth >= 3:
                dirs.clear()
                continue
            for f in files:
                if f.endswith('.jsonl'):
                    all_sids.append(f[:-6])
    try:
        with open(CACHE_PATH, 'w') as f:
            f.write('\n'.join(all_sids))
    except OSError:
        pass

# Find shortest unique prefix (min 3 chars)
others = [s for s in all_sids if s != sid]
prefix = sid
for length in range(3, len(sid) + 1):
    candidate = sid[:length]
    if not any(o.startswith(candidate) for o in others):
        prefix = candidate
        break

print(f'{muted}{prefix}{reset}', end='')
PYEOF
