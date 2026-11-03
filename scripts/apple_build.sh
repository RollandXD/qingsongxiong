#!/usr/bin/env bash
set -euo pipefail
mkdir -p output
xcodebuild -version
swift --version
python3 scripts/check_architecture.py
python3 scripts/check_repository.py
swift test --package-path Packages/BearKit --parallel

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
xcodebuild test -project QingSongXiong.xcodeproj -scheme QingSongXiong \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath output/DerivedData -resultBundlePath output/UITests.xcresult \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build -project QingSongXiong.xcodeproj -scheme QingSongXiong \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath output/DeviceBuild CODE_SIGNING_ALLOWED=NO
python3 scripts/package_ipa.py output/DeviceBuild/Build/Products/Release-iphoneos/QingSongXiong.app output
xcrun xcresulttool export attachments --help
xcrun xcresulttool export attachments --path output/UITests.xcresult --output-path output/screenshots
