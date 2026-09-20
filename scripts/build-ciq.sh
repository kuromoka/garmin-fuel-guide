#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
personal_build=false
if [[ $# -gt 0 ]]; then
  if [[ "$1" == "--personal" && $# -eq 1 ]]; then
    personal_build=true
  else
    echo "Usage: $0 [--personal]" >&2
    exit 2
  fi
fi
sdk_home="${CIQ_SDK_HOME:-}"
if [[ -x "$project_dir/.tools/java/Contents/Home/bin/java" ]]; then
  export PATH="$project_dir/.tools/java/Contents/Home/bin:$PATH"
fi

if [[ -z "$sdk_home" && -x "$project_dir/.tools/ciq-sdk/bin/monkeyc" ]]; then
  sdk_home="$project_dir/.tools/ciq-sdk"
fi

current_sdk_cfg="$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"
if [[ -z "$sdk_home" && -f "$current_sdk_cfg" ]]; then
  configured_sdk="$(<"$current_sdk_cfg")"
  if [[ -x "$configured_sdk/bin/monkeyc" ]]; then
    sdk_home="$configured_sdk"
  fi
fi

if [[ -z "$sdk_home" ]]; then
  for candidate in \
    "/Applications/Garmin/ConnectIQ" \
    "$HOME/Library/Application Support/Garmin/ConnectIQ" \
    "$HOME/Library/Application Support/Garmin/ConnectIQ SDK"; do
    if [[ -x "$candidate/bin/monkeyc" ]]; then
      sdk_home="$candidate"
      break
    fi
  done
fi

if [[ -z "$sdk_home" || ! -x "$sdk_home/bin/monkeyc" ]]; then
  echo "Connect IQ SDK was not found. Install it, or set CIQ_SDK_HOME to its directory containing bin/monkeyc." >&2
  exit 1
fi

developer_key="${CIQ_DEVELOPER_KEY:-$project_dir/.tools/developer_key.der}"
if [[ ! -f "$developer_key" ]]; then
  echo "CIQ_DEVELOPER_KEY must point to your Connect IQ developer key file." >&2
  exit 1
fi

output_dir="$project_dir/ciq/build"
mkdir -p "$output_dir"
if [[ "$personal_build" == true ]]; then
  node_bin="node"
  if [[ -x "$project_dir/.tools/node/bin/node" ]]; then
    node_bin="$project_dir/.tools/node/bin/node"
  fi
  "$node_bin" "$project_dir/scripts/prepare-personal.ts"
  umask 077
  build_log="$output_dir/personal-build.log"
  touch "$build_log"
  chmod 600 "$build_log"
  rm -f "$output_dir/FuelGuide-personal.prg"
  if ! "$sdk_home/bin/monkeyc" \
    -f "$output_dir/personal-project/monkey.jungle" \
    -d fr265 \
    -y "$developer_key" \
    -o "$output_dir/FuelGuide-personal.prg" >"$build_log" 2>&1; then
    echo "Personal build failed. See ciq/build/personal-build.log locally for details." >&2
    exit 1
  fi
  echo "Personal build successful."
  exit 0
fi
"$sdk_home/bin/monkeyc" \
  -f "$project_dir/ciq/monkey.jungle" \
  -d fr265 \
  -y "$developer_key" \
  -o "$output_dir/FuelGuide.prg"
