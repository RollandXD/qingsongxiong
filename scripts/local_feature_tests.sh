#!/usr/bin/env bash
# Linux 快速回归：原样复制真实的 Foundation/Domain/Presentation 和不依赖 SwiftUI 的控制器。
# 原样运行全部 Domain/Presentation 测试和下列可移植控制器/仓储测试；不是 iOS 构建/像素/UI/Keychain 验收的替代品。
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
harness="$(mktemp -d "${TMPDIR:-/tmp}/bear-feature-tests.XXXXXX")"
trap 'rm -rf "$harness"' EXIT
command -v docker >/dev/null || { printf '%s\n' '需要已安装的 Docker 和 swift:6.2 镜像。' >&2; exit 2; }
mkdir -p "$harness/Sources/AIUsageFeature" "$harness/Sources/AIUsageData" "$harness/Sources/BearPlatform" \
    "$harness/Tests/AIUsageFeatureTests" "$harness/Tests/AIUsageDataTests" \
    "$harness/Tests/AIUsagePresentationTests"
for module in BearFoundation AIUsageDomain AIUsagePresentation; do
    cp -R "$root/Packages/BearKit/Sources/$module" "$harness/Sources/$module"
done
for file in AIUsageModel WidgetReloadPolicy; do
    cp "$root/Packages/BearKit/Sources/AIUsageFeature/$file.swift" "$harness/Sources/AIUsageFeature/"
done
for file in AtomicRecordStore HTTPClient; do
    cp "$root/Packages/BearKit/Sources/BearPlatform/$file.swift" "$harness/Sources/BearPlatform/"
done
for file in DemoUsageRepository DemoUsageHistoryReader DemoRelayRepository UsageHistoryService \
    LiveAIUsageRepository LiveRelayRepository RelayBalanceAdapter DeepSeekAdapter UsageResponseParser WidgetRelayReader \
    UsageStorage RelayStorage WidgetUsageReader; do
    cp "$root/Packages/BearKit/Sources/AIUsageData/$file.swift" "$harness/Sources/AIUsageData/"
done
for file in HistoryReadingTests PrivacyTests; do
    cp "$root/Packages/BearKit/Tests/AIUsageFeatureTests/$file.swift" "$harness/Tests/AIUsageFeatureTests/"
done
# Domain/Presentation 都只依赖 Foundation，完整复制测试，避免新增领域回归只在云端才执行。
for module in AIUsageDomainTests AIUsagePresentationTests; do
    cp -R "$root/Packages/BearKit/Tests/$module" "$harness/Tests/"
done
for file in DemoUsageHistoryReaderTests UsageHistoryServiceTests UsageHistoryIntegrityTests UsageRepositoryTests RelayTests HistoryLifecycleProbe; do
    cp "$root/Packages/BearKit/Tests/AIUsageDataTests/$file.swift" "$harness/Tests/AIUsageDataTests/"
done
cat > "$harness/Package.swift" <<'SWIFT'
// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "BearPortableFeatureTests", targets: [
    .target(name: "BearFoundation"),
    .target(name: "BearPlatform", dependencies: ["BearFoundation"]),
    .target(name: "AIUsageDomain", dependencies: ["BearFoundation"]),
    .target(name: "AIUsagePresentation", dependencies: ["AIUsageDomain"]),
    .target(name: "AIUsageFeature", dependencies: ["AIUsageDomain", "AIUsagePresentation"]),
    .target(name: "AIUsageData", dependencies: ["AIUsageDomain", "BearFoundation", "BearPlatform"]),
    .testTarget(name: "AIUsageDomainTests", dependencies: ["AIUsageDomain"]),
    .testTarget(name: "AIUsagePresentationTests", dependencies: ["AIUsagePresentation", "AIUsageDomain"]),
    .testTarget(name: "AIUsageFeatureTests", dependencies: ["AIUsageFeature", "AIUsageDomain"]),
    .testTarget(name: "AIUsageDataTests", dependencies: ["AIUsageData", "AIUsageDomain", "BearFoundation", "BearPlatform"]),
])
SWIFT
printf '%s\n' '运行全部 Domain/Presentation 及所列控制器/历史回归；iOS 和 SwiftUI 仍须 macOS CI。'
docker volume create bear-feature-tests-scratch >/dev/null
docker run --rm -v "$harness":/harness -v bear-feature-tests-scratch:/scratch \
    -w /harness swift:6.2 swift test --scratch-path /scratch "$@"
