#!/usr/bin/env bash
# Git branch and status information.
#
# Components: branch, staged, modified, repo, worktree
# Runs git commands against data.workspace.current_dir, caches for 5s.

set -euo pipefail

INPUT=$(cat)

# Extract fields needed for cache key + cwd (fast, no extra process)
eval "$(echo "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cfg    = d.get('config', {})
data   = d.get('data', {})
ws     = data.get('workspace') or {}
compact    = cfg.get('compact', False)
components = ','.join(cfg.get('components', []))
cwd        = ws.get('current_dir', '')
print(f'COMPACT={compact}')
print(f'COMPONENTS=\"{components}\"')
print(f'CWD=\"{cwd}\"')
" 2>/dev/null)"

CWD="${CWD:-$PWD}"
[[ -z "$CWD" ]] && CWD="$PWD"

# FNV-1a hash of cache key
fnv1a() {
  python3 -c "
s='$1'
h=0xcbf29ce484222325
for b in s.encode():
    h ^= b
    h = (h * 0x00000100000001b3) & 0xffffffffffffffff
print(f'{h:016x}')
" 2>/dev/null || echo "00000000"
}

CACHE_KEY="${CWD}:$([ "$COMPACT" = "True" ] && echo c || echo v):${COMPONENTS}"
CACHE_HASH=$(fnv1a "$CACHE_KEY")
CACHE_FILE="/tmp/soffit-git-${CACHE_HASH}"
CACHE_TTL=5

# Check cache freshness
if [[ -f "$CACHE_FILE" ]]; then
  NOW=$(date +%s)
  MTIME=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
  AGE=$(( NOW - MTIME ))
  if (( AGE < CACHE_TTL )); then
    CACHED=$(cat "$CACHE_FILE" 2>/dev/null || true)
    if [[ -n "$CACHED" ]]; then
      echo "$CACHED"
    else
      echo '{"output": "", "components": ["branch", "staged", "modified", "repo", "worktree"]}'
    fi
    exit 0
  fi
fi

# Run git commands
BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || true)
if [[ -z "$BRANCH" ]]; then
  BRANCH=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null | head -c 7 || true)
fi

if [[ -z "$BRANCH" ]]; then
  echo '{"output": "", "components": ["branch", "staged", "modified", "repo", "worktree"]}' \
    | tee "$CACHE_FILE"
  exit 0
fi

STATUS_OUT=$(git -C "$CWD" status --porcelain 2>/dev/null || true)
REMOTE_URL=$(git -C "$CWD" remote get-url origin 2>/dev/null || true)
WORKTREE_OUT=$(git -C "$CWD" worktree list 2>/dev/null || true)
TOPLEVEL=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)

# Assemble output in python3
echo "$INPUT" | python3 -c "
import json, sys, os

try:
    d = json.load(sys.stdin)
except Exception:
    print('{\"output\": \"\", \"components\": [\"branch\", \"staged\", \"modified\", \"repo\", \"worktree\"]}')
    sys.exit(0)

cfg     = d.get('config', {})
palette = cfg.get('palette', {})
icons   = cfg.get('icons', {})

compact    = cfg.get('compact', False)
components = cfg.get('components', [])

subtle  = palette.get('subtle', '')
success = palette.get('success', '')
warning = palette.get('warning', '')
primary = palette.get('primary', '')
accent  = palette.get('accent', '')
reset   = palette.get('reset', '')
italic    = '\x1b[3m'
no_italic = '\x1b[23m'

branch      = '''$BRANCH'''
status_out  = '''$STATUS_OUT'''
remote_url  = '''$REMOTE_URL'''
worktree_out = '''$WORKTREE_OUT'''
toplevel    = '''$TOPLEVEL'''
cwd         = '''$CWD'''

# Count staged / modified
staged   = 0
modified = 0
for line in status_out.splitlines():
    if len(line) < 2:
        continue
    if line[0] in 'AMDRC':
        staged += 1
    if line[1] in 'MD':
        modified += 1

# Parse remote URL -> (url, name)
repo_url = None
repo_name = None
if remote_url:
    url = remote_url.strip()
    if url.startswith('git@'):
        url = url.replace(':', '/', 1).replace('git@', 'https://', 1)
    url = url.rstrip('.git') if url.endswith('.git') else url
    repo_url  = url
    repo_name = url.rsplit('/', 1)[-1] if '/' in url else url

dir_name = os.path.basename(cwd.rstrip('/'))

# Worktree detection
worktree_name = None
wt_lines = [l for l in worktree_out.splitlines() if l.strip()]
if len(wt_lines) > 1 and toplevel:
    raw = os.path.basename(toplevel.rstrip('/'))
    chars = list(raw)
    if len(chars) > 6:
        raw = chars[0] + chars[1] + '..' + chars[-2] + chars[-1]
    worktree_name = raw

show_all = len(components) == 0
want = lambda c: show_all or c in components

branch_icon = icons.get('git_branch') or '\u2387 '
staged_icon = icons.get('git_staged') or '\u2022'

parts = []
if want('branch'):
    parts.append(f'{subtle}{branch_icon}{branch}{reset}')
if want('staged') and staged > 0 and not compact:
    parts.append(f'{success}{staged_icon}{staged}{reset}')
if want('modified') and modified > 0 and not compact:
    parts.append(f'{warning}+{modified}{reset}')
if want('repo') and not compact:
    if repo_url and repo_name:
        parts.append(f'\x1b]8;;{repo_url}\x07{primary}{repo_name}{reset}\x1b]8;;\x07')
    elif dir_name:
        parts.append(f'{primary}{dir_name}{reset}')
if want('worktree') and worktree_name:
    parts.append(f'{italic}{accent}{worktree_name}{no_italic}{reset}')

output = ' '.join(parts)
result = {'output': output, 'components': ['branch', 'staged', 'modified', 'repo', 'worktree']}
print(json.dumps(result, ensure_ascii=False))
" 2>/dev/null | tee "$CACHE_FILE" || {
  echo '{"output": "", "components": ["branch", "staged", "modified", "repo", "worktree"]}' \
    | tee "$CACHE_FILE"
}
