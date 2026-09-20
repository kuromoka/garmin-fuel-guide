#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk_home="${CIQ_SDK_HOME:-$project_dir/.tools/ciq-sdk}"
if [[ -x "$project_dir/.tools/java/Contents/Home/bin/java" ]]; then
  export PATH="$project_dir/.tools/java/Contents/Home/bin:$PATH"
fi
if [[ ! -x "$sdk_home/bin/monkeyc" ]]; then
  echo "Set CIQ_SDK_HOME to the SDK directory." >&2
  exit 1
fi
developer_key="${CIQ_DEVELOPER_KEY:-$project_dir/.tools/developer_key.der}"
mkdir -p "$project_dir/ciq/build"
"$sdk_home/bin/monkeyc" -f "$project_dir/ciq/tests.jungle" -d fr265 -y "$developer_key" -t -o "$project_dir/ciq/build/FuelGuide-tests.prg"
"$sdk_home/bin/connectiq"
# This SDK may return 1 even after a completed passing test run.
# Accept only its explicit nonempty all-passing summary; never mask failed tests.
test_log="$project_dir/ciq/build/test-ciq.log"
set +e
"$sdk_home/bin/monkeydo" "$project_dir/ciq/build/FuelGuide-tests.prg" fr265 -t 2>&1 | tee "$test_log"
runner_status=${PIPESTATUS[0]}
set -e
if [[ "$runner_status" -le 1 ]] && grep -Eq '^PASSED \(passed=[1-9][0-9]*, failed=0, errors=0\)$' "$test_log" && ! grep -Eq '^FAILED |^ERROR$|^FAIL$' "$test_log"; then
  exit 0
fi
exit 1
