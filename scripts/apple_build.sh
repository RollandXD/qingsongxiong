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

simulator() {
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
  printf '%s' "$simulator_id" > output/simulator-id.txt
  if ! xcrun simctl list devices booted --json | grep -q "$simulator_id"; then
    xcrun simctl boot "$simulator_id"
  fi
}

ui_tests() {
  simulator
  local simulator_id result=0 recorder_pid
  simulator_id="$(cat output/simulator-id.txt)"
  xcodebuild build-for-testing -project QingSongXiong.xcodeproj -scheme QingSongXiong \
    -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath output/DerivedData CODE_SIGNING_ALLOWED=NO
  xcrun simctl bootstatus "$simulator_id" -b
  xcrun simctl io "$simulator_id" recordVideo --help > output/recording-help.txt 2>&1 || true
  python3 -c 'import json,time;json.dump({"startedAt":time.time(),"speed":1,"data":"synthetic"},open("output/recording.json","w"))'
  xcrun simctl io "$simulator_id" recordVideo --codec=h264 output/native-motion.mp4 > output/recording.log 2>&1 &
  recorder_pid=$!
  xcodebuild test-without-building -project QingSongXiong.xcodeproj -scheme QingSongXiong \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
  -parallel-testing-enabled NO \
  -derivedDataPath output/DerivedData -resultBundlePath output/UITests.xcresult \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tee output/ui-tests.log || result=$?
  kill -INT "$recorder_pid" 2>/dev/null || true
  wait "$recorder_pid" || true
  return "$result"
}

screenshots() {
  if [[ ! -d output/UITests.xcresult ]]; then
    printf '%s\n' 'No native UI result bundle available; screenshots remain unverified.'
    return 0
  fi
  xcrun xcresulttool export attachments --help
  xcrun xcresulttool export attachments --path output/UITests.xcresult --output-path output/screenshots
}

case "${1:-all}" in
  checks) checks ;;
  prewarm) simulator ;;
  device) device_package ;;
  ui) ui_tests ;;
  screenshots) screenshots ;;
  all) checks; device_package; ui_tests; screenshots ;;
  *) printf '%s\n' 'Usage: apple_build.sh [checks|prewarm|device|ui|screenshots|all]' >&2; exit 2 ;;
esac
