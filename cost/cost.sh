#!/usr/bin/env bash
# Session, daily, and weekly cost display with budget coloring.
#
# Components: session, today, week
# Reads cost data from stdin and /tmp/soffit-cost-* cache files.
# Triggers background soffit refresh-cost when cache is stale.

set -euo pipefail

INPUT=$(cat)
export SOFFIT_INPUT="$INPUT"

python3 << 'PYEOF'
import json, sys, os, time, subprocess

try:
    d = json.loads(os.environ.get('SOFFIT_INPUT', '{}'))
except Exception:
    sys.exit(0)

data = d.get('data', {})
cfg = d.get('config', {})
palette = cfg.get('palette', {})
icons = cfg.get('icons', {})
compact = cfg.get('compact', False)
components = cfg.get('components', [])
settings = cfg.get('settings', {})

success = palette.get('success', '')
warning = palette.get('warning', '')
danger = palette.get('danger', '')
muted = palette.get('muted', '')
reset = palette.get('reset', '')

sid = (data.get('session_id') or '').strip()

# Cost formatting
def fmt_cost(usd):
    if usd <= 0:
        return '$0'
    if usd >= 0.01:
        return f'${usd:.2f}'
    return f'${usd:.4f}'

def color_for_budget(ratio):
    if ratio >= 1.0:
        return danger
    if ratio >= 0.7:
        return warning
    return success

# Cache file paths (same as Rust paths module)
DAILY_CACHE = '/tmp/soffit-cost-daily'
SESSION_CACHE = f'/tmp/soffit-cost-session-{sid}' if sid else ''
COST_LOCK = '/tmp/soffit-cost-lock'

def read_cache(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except (OSError, ValueError):
        return None

def needs_refresh(path, ttl=60.0):
    try:
        mtime = os.path.getmtime(path)
        return (time.time() - mtime) > ttl
    except (OSError, ValueError):
        return True

def spawn_cost_refresh():
    if os.path.exists(COST_LOCK):
        try:
            age = time.time() - os.path.getmtime(COST_LOCK)
            if age < 30:
                return
        except OSError:
            pass
        try:
            os.remove(COST_LOCK)
        except OSError:
            pass
    try:
        open(COST_LOCK, 'w').close()
    except OSError:
        return
    try:
        cmd = ['soffit', 'refresh-cost']
        if sid:
            cmd.append(sid)
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except OSError:
        pass

# Parse daily cache: format is "week_usd,target,today_usd"
daily_raw = read_cache(DAILY_CACHE)
daily_parsed = None
if daily_raw:
    try:
        parts = [float(p) for p in daily_raw.split(',')]
        if len(parts) >= 3:
            daily_parsed = (parts[2], parts[0], parts[1])  # (today, week, target)
    except (ValueError, IndexError):
        pass

if daily_parsed is None or needs_refresh(DAILY_CACHE):
    spawn_cost_refresh()

icon = icons.get('cost', '\U0001f4b8 ')

if daily_parsed is None:
    print(f'{icon}{muted}--{reset}', end='')
    sys.exit(0)

today_usd, week_usd, target = daily_parsed

# Session cost: prefer stdin value, fall back to cache
session_cost = None
cost_data = data.get('cost') or {}
total = cost_data.get('total_cost_usd')
if total is not None and total > 0:
    session_cost = total
elif sid and SESSION_CACHE:
    raw = read_cache(SESSION_CACHE)
    if raw:
        try:
            session_cost = float(raw)
        except ValueError:
            pass

daily_pace = target / 7.0 if target > 0 else 300.0 / 7.0
today_col = color_for_budget(today_usd / daily_pace)
week_col = color_for_budget(week_usd / max(target, 1.0))

# Active components
defaults = ['session', 'today', 'week']
active = components if components else defaults

parts_list = []
parts_dict = {}
for comp in active:
    if comp == 'session' and session_cost is not None:
        s = f'{muted}{fmt_cost(session_cost)}{reset}'
        parts_list.append(s)
        parts_dict['session'] = s
    elif comp == 'today':
        s = f'{today_col}{fmt_cost(today_usd)}{reset}'
        parts_list.append(s)
        parts_dict['today'] = s
    elif comp == 'week':
        s = f'{week_col}{fmt_cost(week_usd)}{reset}'
        parts_list.append(s)
        parts_dict['week'] = s

if not parts_list:
    sys.exit(0)

sep = ' ' if compact else ' | '
body = sep.join(parts_list)
output = body if compact else f'{icon}{body}'

result = {
    'output': output,
    'components': defaults,
    'parts': parts_dict,
}
print(json.dumps(result), end='')
PYEOF
