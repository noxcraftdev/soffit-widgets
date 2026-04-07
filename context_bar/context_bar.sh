#!/usr/bin/env bash
# Context window usage bar with gradient coloring.
#
# Components: bar, pct, tokens
# bar_style: block (■□◧), dot (●○◐), ascii (#-~)
# Gradient zones: green → orange → red as fill progresses

set -euo pipefail

INPUT=$(cat)

echo "$INPUT" | python3 -c "
import json, sys

try:
    d = json.load(sys.stdin)
except Exception:
    print('{\"output\": \"\", \"components\": [\"bar\", \"pct\", \"tokens\"]}')
    sys.exit(0)

cfg = d.get('config', {})
soffit = d.get('_soffit', {})
palette = cfg.get('palette', {})
icons = cfg.get('icons', {})

compact = cfg.get('compact', False)
components = cfg.get('components', [])
bar_style = cfg.get('bar_style', 'block')

pct = int(soffit.get('pct', 0))
input_tokens = int(soffit.get('input_tokens', 0))
terminal_width = int(soffit.get('terminal_width', 120))

success     = palette.get('success', '')
warning     = palette.get('warning', '')
danger      = palette.get('danger', '')
muted       = palette.get('muted', '')
reset       = palette.get('reset', '')
dim_success = palette.get('dim_success', success)
dim_warning = palette.get('dim_warning', warning)
dim_danger  = palette.get('dim_danger', danger)

data       = d.get('data', {})
ctx_window = (data.get('context_window') or {})
ctx_size   = ctx_window.get('context_window_size') or soffit.get('compact_size')

def fmt_tokens(n):
    n = int(n)
    if n == 0: return '0'
    if n >= 1_000_000: return f'{n/1_000_000:.1f}m'
    if n >= 1_000: return f'{n//1000}k'
    return str(n)

if bar_style == 'dot':
    default_fill, default_empty, default_half = '\u25cf', '\u25cb', '\u25d0'
elif bar_style == 'ascii':
    default_fill, default_empty, default_half = '#', '-', '~'
else:
    default_fill, default_empty, default_half = '\u25a0', '\u25a1', '\u25e7'

fill_ch  = icons.get('bar_fill')  or default_fill
empty_ch = icons.get('bar_empty') or default_empty
half_ch  = icons.get('bar_half')  or default_half

# Responsive bar width: min(12, max(4, terminal_width - 20))
width = min(12, max(4, terminal_width - 20))
pct   = min(100, max(0, pct))

threshold0 = (4 * width + 6) // 12
threshold1 = (9 * width + 6) // 12

fill_f   = pct / 100.0 * width
fill_int = int(fill_f)
frac     = fill_f - fill_int

bar = ''
for pos in range(width):
    if pos < threshold0:
        bright, dim_col = success, dim_success
        half_pos = threshold0 // 2
    elif pos < threshold1:
        bright, dim_col = warning, dim_warning
        half_pos = threshold0 + (threshold1 - threshold0) // 2
    else:
        bright, dim_col = danger, dim_danger
        half_pos = threshold1 + (width - threshold1) // 2

    col = bright if pos >= half_pos else dim_col

    if pos < fill_int:
        bar += col + fill_ch
    elif pos == fill_int and frac > 0.0:
        bar += col + (half_ch if frac < 0.5 else fill_ch)
    else:
        bar += muted + empty_ch

bar += reset

if fill_int >= threshold1:
    label_col = danger
elif fill_int >= threshold0:
    label_col = warning
else:
    label_col = success

SEG = '\U0001fbf0\U0001fbf1\U0001fbf2\U0001fbf3\U0001fbf4\U0001fbf5\U0001fbf6\U0001fbf7\U0001fbf8\U0001fbf9'
def seg_pct(n, col):
    n = min(999, max(0, int(n)))
    digits = ''.join(SEG[int(c)] for c in str(n))
    return f'{col}{digits}\u066a{reset}'

show_all = len(components) == 0
want = lambda c: show_all or c in components

out_parts = []
if want('bar'):
    out_parts.append(bar)
if want('pct'):
    out_parts.append(seg_pct(pct, label_col))
if want('tokens') and not compact:
    denom = fmt_tokens(ctx_size) if ctx_size else '?'
    out_parts.append(f'{muted}{fmt_tokens(input_tokens)}/{denom}{reset}')

output = ' '.join(out_parts)
result = {'output': output, 'components': ['bar', 'pct', 'tokens']}
print(json.dumps(result, ensure_ascii=False))
" 2>/dev/null || echo '{"output": "", "components": ["bar", "pct", "tokens"]}'
