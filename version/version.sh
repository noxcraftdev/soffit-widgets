#!/usr/bin/env bash
# Version and model display with update indicator.
#
# Components: update, version, model
# Shows Claude Code version (superscript), model name (subscript),
# and an update indicator when new versions are available.

set -euo pipefail

python3 << 'PYEOF'
import json, sys, os, re, time, subprocess

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

data = d.get('data', {})
cfg = d.get('config', {})
soffit = d.get('_soffit', {})
palette = cfg.get('palette', {})
icons = cfg.get('icons', {})
compact = cfg.get('compact', False)
components = cfg.get('components', [])
use_unicode = soffit.get('use_unicode_text', True)

version = (data.get('version') or '').strip()
if not version:
    sys.exit(0)

model_obj = data.get('model') or {}
model_raw = model_obj.get('display_name', '')
model = re.sub(r'\s*\((\d+\w*)\s+context\)', r' \1', model_raw).lower()

accent = palette.get('accent', '')
muted = palette.get('muted', '')
warning = palette.get('warning', '')
reset = palette.get('reset', '')

# Superscript/subscript maps
SUP_FROM = '0123456789.abcdefghijklmnoprstuvwxyz'
SUP_TO = '\u2070\u00b9\u00b2\u00b3\u2074\u2075\u2076\u2077\u2078\u2079\u00b7\u1d43\u1d47\u1d9c\u1d48\u1d49\u1da0\u1d4d\u02b0\u2071\u02b2\u1d4f\u02e1\u1d50\u207f\u1d52\u1d56\u02b3\u02e2\u1d57\u1d58\u1d5b\u02b7\u02e3\u02b8\u1d9c'
# Note: SUP_TO has some approximations for missing chars

SUB_FROM = '0123456789.aehijklmnoprstuvx'
SUB_TO = '\u2080\u2081\u2082\u2083\u2084\u2085\u2086\u2087\u2088\u2089.\u2090\u2091\u2095\u1d62\u2c7c\u2096\u2097\u2098\u2099\u2092\u209a\u1d63\u209b\u209c\u1d64\u1d65\u2093'

def superscript(s):
    return ''.join(SUP_TO[SUP_FROM.index(c)] if c in SUP_FROM else c for c in s)

def subscript(s):
    return ''.join(SUB_TO[SUB_FROM.index(c)] if c in SUB_FROM else c for c in s)

# Check for updates via cache files
def read_cache(path, ttl=3600.0):
    try:
        mtime = os.path.getmtime(path)
        if time.time() - mtime < ttl * 2:  # stale-while-revalidate
            with open(path) as f:
                return f.read().strip() or None
    except (OSError, ValueError):
        return None

def needs_refresh(path, ttl=3600.0):
    try:
        mtime = os.path.getmtime(path)
        return (time.time() - mtime) > ttl
    except (OSError, ValueError):
        return True

def spawn_bg(lock_path, arg):
    lock = lock_path
    if os.path.exists(lock):
        try:
            age = time.time() - os.path.getmtime(lock)
            if age < 30:
                return
        except OSError:
            pass
        try:
            os.remove(lock)
        except OSError:
            pass
    try:
        open(lock, 'w').close()
    except OSError:
        return
    try:
        exe = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'soffit') if '__file__' in dir() else 'soffit'
        subprocess.Popen(
            ['soffit', arg],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass

VERSION_CACHE = '/tmp/soffit-version-cache'
VERSION_LOCK = '/tmp/soffit-version-lock'
SELF_VERSION_CACHE = '/tmp/soffit-self-version-cache'
SELF_VERSION_LOCK = '/tmp/soffit-self-version-lock'

latest = read_cache(VERSION_CACHE)
if needs_refresh(VERSION_CACHE):
    spawn_bg(VERSION_LOCK, 'fetch-version')

latest_self = read_cache(SELF_VERSION_CACHE)
if needs_refresh(SELF_VERSION_CACHE):
    spawn_bg(SELF_VERSION_LOCK, 'fetch-self-version')

has_update = bool(latest and latest != version)
# Note: can't easily check soffit version from bash, so just check if cache has a value
has_self_update = bool(latest_self)

# Active components
defaults = ['update', 'version', 'model']
active = components if components else defaults

parts = []
for comp in active:
    if comp == 'update' and (has_update or has_self_update):
        icon = icons.get('update', '\u2191 ')
        parts.append(f'{warning}{icon}{reset}')
    elif comp == 'version':
        if compact or not use_unicode:
            parts.append(f'{muted}{version}{reset}')
        else:
            parts.append(f'{muted}{superscript(version)}{reset}')
    elif comp == 'model' and model:
        if compact or not use_unicode:
            parts.append(f'{accent}{model}{reset}')
        else:
            parts.append(f'{accent}{subscript(model)}{reset}')

if not parts:
    sys.exit(0)

output = ''.join(parts)
result = {
    'output': output,
    'components': defaults,
    'parts': {}
}

# Build parts dict for compose
for comp in defaults:
    if comp == 'update' and (has_update or has_self_update):
        icon = icons.get('update', '\u2191 ')
        result['parts']['update'] = f'{warning}{icon}{reset}'
    elif comp == 'version':
        if compact or not use_unicode:
            result['parts']['version'] = f'{muted}{version}{reset}'
        else:
            result['parts']['version'] = f'{muted}{superscript(version)}{reset}'
    elif comp == 'model' and model:
        if compact or not use_unicode:
            result['parts']['model'] = f'{accent}{model}{reset}'
        else:
            result['parts']['model'] = f'{accent}{subscript(model)}{reset}'

print(json.dumps(result), end='')
PYEOF
