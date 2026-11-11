#!/usr/bin/env bash
# Linux 快速回归：原样复制真实的 Foundation/Domain/Presentation 和不依赖 SwiftUI 的控制器。
# 只验证明确列出的源文件与测试，不是 iOS 构建/像素/UI/Keychain 验收的替代品。
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
harness="$(mktemp -d "${TMPDIR:-/tmp}/bear-feature-tests.XXXXXX")"
trap 'rm -rf "$harness"' EXIT
command -v docker >/dev/null || { printf '%s\n' '需要已安装的 Docker 和 swift:6.2 镜像。' >&2; exit 2; }
mkdir -p "$harness/Sources/AIUsageFeature" "$harness/Sources/AIUsageData" \
    "$harness/Tests/AIUsageFeatureTests" "$harness/Tests/AIUsageDataTests"
for module in BearFoundation AIUsageDomain AIUsagePresentation; do
    cp -R "$root/Packages/BearKit/Sources/$module" "$harness/Sources/$module"
done
for file in AIUsageModel WidgetReloadPolicy; do
    cp "$root/Packages/BearKit/Sources/AIUsageFeature/$file.swift" "$harness/Sources/AIUsageFeature/"
done
for file in DemoUsageRepository DemoUsageHistoryReader; do
    cp "$root/Packages/BearKit/Sources/AIUsageData/$file.swift" "$harness/Sources/AIUsageData/"
done
for file in HistoryReadingTests PrivacyTests; do
    cp "$root/Packages/BearKit/Tests/AIUsageFeatureTests/$file.swift" "$harness/Tests/AIUsageFeatureTests/"
done
cp "$root/Packages/BearKit/Tests/AIUsageDataTests/DemoUsageHistoryReaderTests.swift" "$harness/Tests/AIUsageDataTests/"
cat > "$harness/Package.swift" <<'SWIFT'
// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "BearPortableFeatureTests", targets: [
    .target(name: "BearFoundation"),
    .target(name: "AIUsageDomain", dependencies: ["BearFoundation"]),
    .target(name: "AIUsagePresentation", dependencies: ["AIUsageDomain"]),
    .target(name: "AIUsageFeature", dependencies: ["AIUsageDomain", "AIUsagePresentation"]),
    .target(name: "AIUsageData", dependencies: ["AIUsageDomain"]),
    .testTarget(name: "AIUsageFeatureTests", dependencies: ["AIUsageFeature", "AIUsageDomain"]),
    .testTarget(name: "AIUsageDataTests", dependencies: ["AIUsageData", "AIUsageDomain"]),
])
SWIFT
printf '%s\n' '仅运行原样源码的可移植控制器/历史回归；iOS 和 SwiftUI 仍须 macOS CI。'
docker volume create bear-feature-tests-scratch >/dev/null
docker run --rm -v "$harness":/harness -v bear-feature-tests-scratch:/scratch \
    -w /harness swift:6.2 swift test --scratch-path /scratch "$@"
