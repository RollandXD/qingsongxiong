#!/usr/bin/env bash
set -euo pipefail
mkdir -p output
checks() {
  xcodebuild -version
  swift --version
  python3 scripts/check_architecture.py
  python3 scripts/check_repository.py
  swift test --package-path Packages/BearKit --parallel
}

device_package() {
  xcodebuild build -project QingSongXiong.xcodeproj -scheme QingSongXiong \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath output/DeviceBuild CODE_SIGNING_ALLOWED=NO
  python3 scripts/package_ipa.py output/DeviceBuild/Build/Products/Release-iphoneos/QingSongXiong.app output
}

ui_tests() {
  local simulator_id
  simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json,sys
data=json.load(sys.stdin)["devices"]
for runtime,devices in data.items():
    if "iOS-27-1" in runtime:
        for device in devices:
            if device["name"].startswith("iPhone"):
                print(device["udid"]);sys.exit(0)
sys.exit("iOS 27.1 iPhone simulator unavailable")
')"
  local result=0
  xcodebuild test -project QingSongXiong.xcodeproj -scheme QingSongXiong \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath output/DerivedData -resultBundlePath output/UITests.xcresult \
    CODE_SIGNING_ALLOWED=NO || result=$?
  if [[ -d output/UITests.xcresult ]]; then
    xcrun xcresulttool export attachments --help
    xcrun xcresulttool export attachments --path output/UITests.xcresult --output-path output/screenshots
  fi
  return "$result"
}

case "${1:-all}" in
  checks) checks ;;
  device) device_package ;;
  ui) ui_tests ;;
  all) checks; device_package; ui_tests ;;
  *) printf '%s\n' 'Usage: apple_build.sh [checks|device|ui|all]' >&2; exit 2 ;;
esac
