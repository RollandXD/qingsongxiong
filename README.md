# 轻松熊 · QingSongXiong

温暖、精致的 Apple 个人工具箱。AI 额度监控是第一个功能模块，计划支持 Codex、Claude 订阅额度与 DeepSeek API 余额。

**当前公开安装包 preview.1 支持 DeepSeek 官方 API 余额，App 与小组件均已实机通过；main 正在接入 Codex、Claude，尚未完成首版。**

手动免费签名、两类组件、共享 Keychain、重签保留数据与 Shadowrocket 恢复已通过实机检查。自动续签与跨七天稳定性仍待实际观察。

[下载 DeepSeek 预览包](https://github.com/RollandXD/qingsongxiong/releases/tag/v0.1.0-preview.1)。安装或覆盖更新时保留全部 Widget 扩展。连接 DeepSeek 时只在手机 App 输入自己的 API Key，不在聊天或 CI 提供凭据。

## 工程

- iPhone / iOS 27.0+，Swift 6，SwiftUI、WidgetKit、App Intents。
- 八个 Swift Package 模块：基础能力、设计系统、平台实现、AI 领域、AI 数据、AI 共享展示规则、AI 页面、仅主 App 使用的 AI 授权。
- AppShell 统一装配依赖和注册功能；小组件不依赖主 App 页面或交互式登录。
- GitHub 公共仓库标准 `xcode-27` 构建机，Xcode 27.1，固定 XcodeGen 与 Actions 版本。

## 从 Linux 开发

```sh
python3 scripts/check_architecture.py
python3 scripts/check_repository.py
```

提交代码后，Actions 执行 Swift 包测试、模拟器 UI 测试并生成待重签 IPA。`QingSongXiong-needs-signing.ipa` **没有 Apple 开发者签名**，必须由 SideStore 使用你自己的账户重新签名后安装。

有 Mac / 对应 Xcode 的环境还可以执行：

```sh
xcodegen generate --spec project.yml
swift test --package-path Packages/BearKit
```

## 当前验收

- [交付状态](docs/STATUS.md)
- [架构与增加新功能](docs/ARCHITECTURE.md)
- [免费安装与实机验收](docs/INSTALL.md)
- [测试说明](docs/TESTING.md)
- [机器可读的实机门槛](device-gate.json)

## 数据与许可

运行时由手机直接连接厂商，不需要自建服务器。凭据保存在本机 Keychain，共享快照只包含读数、时间和状态。CI 使用演示数据，真实凭据不会进入源码或 CI。

项目采用 Apache-2.0。设计时研究了 [AI Usage Limits](https://github.com/stavrop/ai-usage-limits)，其原始说明见 [UPSTREAM-NOTICE](docs/UPSTREAM-NOTICE.txt)。后续复用其登录实现时继续保留来源与许可。
