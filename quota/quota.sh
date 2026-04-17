#!/usr/bin/env bash
# API rate limit quota bars.
#
# Components: five_hour, seven_day
# Shows remaining percentage with pace marker and reset countdown.

set -euo pipefail

INPUT=$(cat)

echo "$INPUT" | python3 -c "
import json, sys, time, math

try:
    d = json.load(sys.stdin)
except Exception:
    print('{\"output\": \"\", \"components\": [\"five_hour\", \"seven_day\"]}')
    sys.exit(0)

cfg      = d.get('config', {})
soffit   = d.get('_soffit', {})
palette  = cfg.get('palette', {})
icons    = cfg.get('icons', {})
data     = d.get('data', {})
settings = cfg.get('settings', {})

components     = cfg.get('components', [])
bar_style      = cfg.get('bar_style', 'block')
terminal_width = int(soffit.get('terminal_width', 120))

primary = palette.get('primary', '')
warning = palette.get('warning', '')
danger  = palette.get('danger', '')
muted   = palette.get('muted', '')
reset   = palette.get('reset', '')
dim_primary = palette.get('dim_primary', primary)
dim_warning = palette.get('dim_warning', warning)
dim_danger  = palette.get('dim_danger', danger)
italic    = '\x1b[3m'
no_italic = '\x1b[23m'

FIVE_HOURS = 5.0 * 3600.0
SEVEN_DAYS = 7.0 * 24.0 * 3600.0

SEG = '\U0001fbf0\U0001fbf1\U0001fbf2\U0001fbf3\U0001fbf4\U0001fbf5\U0001fbf6\U0001fbf7\U0001fbf8\U0001fbf9'
def seg_pct(n, col):
    n = min(999, max(0, int(n)))
    digits = ''.join(SEG[int(c)] for c in str(n))
    return f'{col}{digits}\u066a{reset}'

def fmt_duration_hm(secs):
    secs = int(max(0, secs))
    mins  = secs // 60
    hours = mins  // 60
    days  = hours // 24
    if days > 0:
        return f'{days}d {hours % 24}h'
    if hours > 0:
        return f'{hours}h {mins % 60:02d}m'
    return f'{mins}m'

def parse_resets_at(val):
    if val is None:
        return 0.0
    if isinstance(val, (int, float)):
        return float(val)
    if isinstance(val, str):
        try:
            return float(val)
        except ValueError:
            pass
        # ISO 8601 parse via datetime
        try:
            from datetime import datetime, timezone
            s = val.strip()
            for fmt in ('%Y-%m-%dT%H:%M:%SZ', '%Y-%m-%dT%H:%M:%S+00:00',
                        '%Y-%m-%dT%H:%M:%S', '%Y-%m-%d %H:%M:%S'):
                try:
                    dt = datetime.strptime(s[:19], '%Y-%m-%dT%H:%M:%S')
                    return dt.replace(tzinfo=timezone.utc).timestamp()
                except Exception:
                    pass
        except Exception:
            pass
    return 0.0

def quota_fill_char(bar_style, icons, zone_f):
    custom = icons.get('quota_fill')
    if custom:
        return custom
    if bar_style == 'dot':
        return '\u25cf'
    if bar_style == 'ascii':
        return '#'
    # block: zone-based
    if zone_f < 0.33:
        return '\u2591'   # ░
    if zone_f < 0.66:
        return '\u2593'   # ▓
    return '\u25a0'       # ■

def usage_bar(pct, width, col, pace_pct, bar_style, icons):
    if bar_style == 'dot':
        empty_ch = icons.get('quota_empty') or '\u25cb'
    elif bar_style == 'ascii':
        empty_ch = icons.get('quota_empty') or '-'
    else:
        empty_ch = icons.get('quota_empty') or '\u25a1'
    pace_ch = icons.get('quota_pace') or '\u25cc'

    pct = min(100, max(0, int(pct)))
    fill_f   = pct / 100.0 * width
    fill_int = int(fill_f)
    frac     = fill_f - fill_int

    pace_seg = int(pace_pct / 100.0 * width) if pace_pct is not None else None

    # pace color based on ratio = pct / pace_pct
    if pace_pct is not None and pace_pct > 0:
        ratio = pct / pace_pct
        if ratio < 0.8:
            pace_col = danger
        elif ratio < 1.0:
            pace_col = warning
        else:
            pace_col = muted
    else:
        pace_col = muted

    bar = ''
    for pos in range(width):
        is_pre_pace = (pace_seg is not None and pos < pace_seg and fill_int > pace_seg)
        effective_col = muted if is_pre_pace else col

        if pos < fill_int:
            ch = quota_fill_char(bar_style, icons, pos / fill_f if fill_f > 0 else 0)
            bar += effective_col + ch
        elif pos == fill_int and frac > 0.0:
            ch = quota_fill_char(bar_style, icons, pos / max(fill_f, 1.0))
            bar += effective_col + ch
        else:
            if pace_seg is not None and pos == pace_seg:
                bar += pace_col + pace_ch
            else:
                bar += muted + empty_ch

    bar += reset

    if pct >= 80:
        label_col = danger
    elif pct >= 50:
        label_col = warning
    else:
        label_col = primary

    return bar, label_col

def quota_color(used, remaining_secs, window_secs):
    if remaining_secs <= 0.0 or window_secs <= 0.0:
        if used >= 80:   return danger
        if used >= 50:   return warning
        return primary
    elapsed = window_secs - remaining_secs
    if elapsed <= 0:
        return primary
    even_pace_used = elapsed / window_secs * 100.0
    per_unit = (100.0 - used) / (100.0 - even_pace_used) if even_pace_used < 100 else 1.0
    if per_unit >= 0.70:  return primary
    if per_unit >= 0.35:  return warning
    return danger

def pace_balance_secs(used, remaining_secs, window_secs):
    elapsed = window_secs - remaining_secs
    if elapsed < 60:
        return None
    balance_pct = (100.0 - used) - (remaining_secs / window_secs * 100.0)
    return round(balance_pct * window_secs / 100.0)

def fmt_pace(secs, window_secs):
    if secs >= 0:
        col = dim_primary
    else:
        deficit_pct = abs(secs) / window_secs * 100.0
        col = dim_danger if deficit_pct >= 15.0 else dim_warning
    sign  = '+' if secs >= 0 else '-'
    hours = abs(secs) // 3600
    seg_h = ''.join(SEG[int(c)] for c in str(hours))
    return f'{italic}{col}{sign}{seg_h}h{no_italic}{reset}'

width = min(12, max(4, terminal_width - 20))
now   = time.time()
show_all = len(components) == 0
want  = lambda c: show_all or c in components

rate_limits = (data.get('rate_limits') or {})

if not rate_limits:
    placeholder = f'{muted}5h: --  |  7d: --{reset}'
    print(json.dumps({'output': placeholder, 'components': ['five_hour', 'seven_day']}, ensure_ascii=False))
    sys.exit(0)

segments = []

show_pace_5h = settings.get('show_pace_5h', True)
show_pace_7d = settings.get('show_pace_7d', True)
for comp, window_secs, label, show_pace in [
    ('five_hour', FIVE_HOURS, '5h', show_pace_5h),
    ('seven_day', SEVEN_DAYS, '7d', show_pace_7d),
]:
    if not want(comp):
        continue
    rl = rate_limits.get(comp)
    if not rl:
        continue
    used = rl.get('used_percentage')
    if used is None:
        continue
    used = float(used)
    remaining_pct = max(0.0, 100.0 - used)

    resets_epoch    = parse_resets_at(rl.get('resets_at'))
    remaining_secs  = max(0.0, resets_epoch - now)

    pace_pct = remaining_secs / window_secs * 100.0 if remaining_secs > 0 else None
    col      = quota_color(used, remaining_secs, window_secs)

    bar, _ = usage_bar(int(remaining_pct), width, col, pace_pct, bar_style, icons)
    pct_str = seg_pct(int(remaining_pct), col)

    pace_part = ''
    if show_pace and pace_pct is not None:
        bal = pace_balance_secs(used, remaining_secs, window_secs)
        if bal is not None:
            pace_part = ' ' + fmt_pace(bal, window_secs)

    reset_part = ''
    if remaining_secs > 0:
        reset_part = f' {muted}{fmt_duration_hm(remaining_secs)}{reset}'

    seg = f'{muted}{label}:{reset} {bar} {pct_str}{pace_part}{reset_part}'
    segments.append(seg)

sep    = f' {muted}|{reset} '
output = sep.join(segments)

# Write quota samples to SQLite for tmux-session sidebar usage bars
import os, sqlite3
_db_dir = os.path.join(os.path.expanduser('~'), '.local', 'state', 'claude-statusline')
_db_path = os.path.join(_db_dir, 'usage.db')
try:
    os.makedirs(_db_dir, exist_ok=True)
    _conn = sqlite3.connect(_db_path)
    _conn.execute('CREATE TABLE IF NOT EXISTS usage_samples (ts INTEGER, fh_used INTEGER, fh_reset INTEGER, sd_used INTEGER, sd_reset INTEGER)')
    fh_rl = rate_limits.get('five_hour') or {}
    sd_rl = rate_limits.get('seven_day') or {}
    fh_u = int(fh_rl.get('used_percentage') or 0)
    sd_u = int(sd_rl.get('used_percentage') or 0)
    fh_r = int(parse_resets_at(fh_rl.get('resets_at')))
    sd_r = int(parse_resets_at(sd_rl.get('resets_at')))
    _conn.execute('INSERT INTO usage_samples VALUES (?, ?, ?, ?, ?)', (int(now), fh_u, fh_r, sd_u, sd_r))
    _conn.execute('DELETE FROM usage_samples WHERE ts < ?', (int(now) - 8 * 86400,))
    _conn.commit()
    _conn.close()
except Exception:
    pass

result = {'output': output, 'components': ['five_hour', 'seven_day']}
print(json.dumps(result, ensure_ascii=False))
" 2>/dev/null || echo '{"output": "", "components": ["five_hour", "seven_day"]}'
