# 轻松熊 · QingSongXiong

温暖、精致的 Apple 个人工具箱。AI 额度监控是第一个功能模块，计划支持 Codex、Claude 订阅额度与 DeepSeek API 余额。

**当前交付阶段：免费安装与共享能力验证版。真实账户接入尚未启用。**

这个版本用于确认：独立 App 和两类主屏幕组件能否通过免费签名安装、共享数据、共享 Keychain、重新签名后保留数据，以及续签所需连接与 Shadowrocket 能否配合使用。没有验证过的行为不标为已完成。

[下载名称兼容修正版验证包](https://github.com/RollandXD/qingsongxiong/releases/tag/v0.1.0-verification.2)。安装前先完成 SideStore 的登录与首次刷新，并阅读下方实机验收步骤；首个验证包已标记中文 App ID 注册兼容问题。

## 工程

- iPhone / iOS 27.0+，Swift 6，SwiftUI、WidgetKit、App Intents。
- 六个 Swift Package 模块：基础能力、设计系统、平台实现、AI 领域、AI 数据、AI 展示。
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

首版运行时由手机连接厂商，不需要自建服务器。验证版只写入无敏感信息的本地标记，不接触真实 AI 登录信息。真实凭据不会进入源码或 CI。

项目采用 Apache-2.0。设计时研究了 [AI Usage Limits](https://github.com/stavrop/ai-usage-limits)，其原始说明见 [UPSTREAM-NOTICE](docs/UPSTREAM-NOTICE.txt)。后续复用其登录实现时继续保留来源与许可。
