#!/usr/bin/env bash
# Run a command with a Node that satisfies this repository's `engines` floor
# (^22.19.0 || >=24.0.0). Intended for git hooks, which are executed through
# `sh -c` and inherit whatever toolchain the invoking shell happens to expose.
#
# Why this exists: on a machine that has Node through nvm but no `default`
# alias, `pnpm run typecheck` fails with `sh: 1: pnpm: not found` (127). Even if
# a `pnpm` is found, Node 20 fails the build because tsdown's native config
# loader needs type stripping. Resolving the toolchain here keeps the hook
# independent of the caller's shell setup.
#
# Resolution order:
#   1. the `node` already on PATH, when it satisfies the floor;
#   2. otherwise the highest `$NVM_DIR/versions/node/v*` that satisfies it;
#   3. `corepack` provides pnpm at the version pinned by `packageManager`.
#
# Usage: scripts/with-project-node.sh <command> [args...]
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 22.19 <= v < 23, or v >= 24.
version_ok() {
  printf '%s' "$1" | grep -qE '^v(22\.(19|[2-9][0-9])|2[4-9]|[3-9][0-9])\.'
}

node_ok() {
  command -v node >/dev/null 2>&1 || return 1
  version_ok "$(node -v 2>/dev/null || true)"
}

if ! node_ok; then
  nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  best=''
  for dir in "$nvm_dir"/versions/node/v*/bin; do
    [ -x "$dir/node" ] || continue
    version_ok "$("$dir/node" -v 2>/dev/null || true)" || continue
    if [ -z "$best" ] || [ "$(printf '%s\n%s\n' "$best" "$dir" | sort -V | tail -1)" = "$dir" ]; then
      best="$dir"
    fi
  done
  if [ -n "$best" ]; then
    PATH="$best:$PATH"
    export PATH
  fi
fi

if ! node_ok; then
  current="$(command -v node >/dev/null 2>&1 && node -v || echo 'none')"
  echo "with-project-node: no Node satisfying ^22.19 || >=24 (found: $current)." >&2
  echo "  Install one with: nvm install 24" >&2
  exit 1
fi

cd "$repo_dir"
exec "$@"
