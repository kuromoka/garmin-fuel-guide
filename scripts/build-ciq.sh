#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
"$sdk_home/bin/monkeyc" \
  -f "$project_dir/ciq/monkey.jungle" \
  -d fr265 \
  -y "$developer_key" \
  -o "$output_dir/FuelGuide.prg"
