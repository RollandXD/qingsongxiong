#!/usr/bin/env bash
# 本地快速类型检查：本机没有 Xcode/Swift 时，用 Docker 里的 Swift 工具链
# 真正编译一遍不依赖 SwiftUI 的模块（BearFoundation / AIUsageDomain / AIUsagePresentation）。
#
# 为什么值得：CI 一轮 20–30 分钟，而漏 import、写错 API 名这类错误
# 只值 2 秒。先把纯逻辑层在本地编译干净，再让 CI 去跑构建和原生 UI 测试。
#
# 限制（务必牢记）：AIUsageFeature / AppShell 依赖 SwiftUI，Linux 上没有，
# 这两个模块的改动仍然只能靠 macOS runner 验证。
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sources="$root/Packages/BearKit/Sources"
harness="$(mktemp -d "${TMPDIR:-/tmp}/bear-typecheck.XXXXXX")"
trap 'rm -rf "$harness"' EXIT

if ! command -v docker >/dev/null; then
    printf '%s\n' '需要 Docker：本机没有 Swift 工具链，借容器里的 swift:6.2 做类型检查。' >&2
    exit 2
fi

mkdir -p "$harness/Sources"
for module in BearFoundation AIUsageDomain AIUsagePresentation; do
    cp -R "$sources/$module" "$harness/Sources/$module"
done

cat > "$harness/Package.swift" <<'SWIFT'
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BearTypecheck",
    targets: [
        .target(name: "BearFoundation"),
        .target(name: "AIUsageDomain", dependencies: ["BearFoundation"]),
        .target(name: "AIUsagePresentation",
                dependencies: ["AIUsageDomain", "BearFoundation"]),
    ]
)
SWIFT

# 命名卷当 scratch，避免容器以 root 写入仓库目录。
docker volume create bear-typecheck-scratch >/dev/null
docker run --rm \
    -v "$harness":/harness \
    -v bear-typecheck-scratch:/scratch \
    -w /harness \
    swift:6.2 \
    swift build --scratch-path /scratch "$@"
