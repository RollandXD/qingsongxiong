#!/usr/bin/env bash
set -euo pipefail
mkdir -p output
checks() {
  xcodebuild -version
  swift --version
  python3 scripts/check_architecture.py
  python3 scripts/check_repository.py
  python3 -m unittest discover -s scripts -p 'test_*.py'
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
  simulator_id="$(python3 scripts/select_simulator.py)"
  printf '%s' "$simulator_id" > output/simulator-id.txt
}

ui_tests() {
  if [[ ! -s output/simulator-id.txt ]]; then simulator; fi
  local simulator_id result=0 recorder_pid
  # macOS Bash 3.2 在 set -u 下不能展开空数组；默认明确选择整个 UI target。
  local -a selection=("-only-testing:QingSongXiongUITests")
  if [[ -n "${BEAR_UI_TEST:-}" ]]; then selection=("-only-testing:QingSongXiongUITests/${BEAR_UI_TEST}"); fi
  simulator_id="$(cat output/simulator-id.txt)"
  xcodebuild build-for-testing -project QingSongXiong.xcodeproj -scheme QingSongXiong \
    -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath output/DerivedData CODE_SIGNING_ALLOWED=NO
  if ! xcrun simctl list devices booted --json | grep -q "$simulator_id"; then
    xcrun simctl boot "$simulator_id"
  fi
  xcrun simctl bootstatus "$simulator_id" -b
  xcrun simctl io "$simulator_id" enumerate > output/displays.txt
  python3 -c 'import json,time;json.dump({"startedAt":time.time(),"speed":1,"data":"synthetic"},open("output/recording.json","w"))'
  xcrun simctl io "$simulator_id" recordVideo --display=primary --codec=h264 output/native-motion.mp4 > output/recording.log 2>&1 &
  recorder_pid=$!
  # 即使命令展开、测试或脚本异常退出，也不能遗留录像进程拖到 CI 超时。
  trap "kill -INT $recorder_pid 2>/dev/null || true; kill -TERM $recorder_pid 2>/dev/null || true" EXIT
  xcodebuild test-without-building -project QingSongXiong.xcodeproj -scheme QingSongXiong \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
  -parallel-testing-enabled NO "${selection[@]}" \
  -derivedDataPath output/DerivedData -resultBundlePath output/UITests.xcresult \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tee output/ui-tests.log || result=$?
  kill -INT "$recorder_pid" 2>/dev/null || true
  wait "$recorder_pid" || true
  trap - EXIT
  if [[ ! -s output/native-motion.mp4 ]]; then
    cat output/recording.log >&2
    result=1
  fi
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
  select-simulator) simulator ;;
  device) device_package ;;
  ui) ui_tests ;;
  screenshots) screenshots ;;
  all) checks; device_package; ui_tests; screenshots ;;
  *) printf '%s\n' 'Usage: apple_build.sh [checks|select-simulator|device|ui|screenshots|all]' >&2; exit 2 ;;
esac
