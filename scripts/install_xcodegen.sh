#!/usr/bin/env bash
set -euo pipefail
version=2.46.0
checksum=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
tools_dir="${RUNNER_TEMP:?}/bear-tools"
mkdir -p "$tools_dir"
curl --fail --silent --show-error --location \
  "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip" \
  --output "$tools_dir/xcodegen.zip"
printf '%s  %s\n' "$checksum" "$tools_dir/xcodegen.zip" | shasum -a 256 --check
unzip -q -o "$tools_dir/xcodegen.zip" -d "$tools_dir"
tool="$tools_dir/xcodegen/bin/xcodegen"
"$tool" --version
"$tool" generate --help
"$tool" generate --spec project.yml
