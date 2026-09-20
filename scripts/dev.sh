#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
if [[ -x "$project_dir/.tools/node/bin/node" && -f "$project_dir/.tools/pnpm/node_modules/pnpm/bin/pnpm.mjs" ]]; then
  export PATH="$project_dir/.tools/node/bin:$project_dir/.tools/pnpm/node_modules/.bin:$PATH"
  exec "$project_dir/.tools/node/bin/node" "$project_dir/.tools/pnpm/node_modules/pnpm/bin/pnpm.mjs" "$@"
fi
exec pnpm "$@"
