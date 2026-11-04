# 轻松熊 · QingSongXiong

温暖、精致的 Apple 个人工具箱。AI 额度监控是第一个功能模块，支持 Codex、Claude 订阅额度与 DeepSeek API 余额。

**当前设计预览 v0.2.0-preview.1（0.2.0/6）已发布。iPhone 16 Pro / iOS 27.0 原生回归、63 项包测试、14 项 UI 测试与安装包校验全部通过。iPhone 16 Pro 真机覆盖更新、账户/读数、两类组件与日常交互也已通过用户确认。**

[下载设计预览与扫码入口](https://github.com/RollandXD/qingsongxiong/releases/tag/v0.2.0-preview.1) · [原速动效影片](https://github.com/RollandXD/qingsongxiong/releases/download/v0.2.0-preview.1/iphone16pro-native-motion-1x.mp4) · [浅深色截图](https://github.com/RollandXD/qingsongxiong/releases/download/v0.2.0-preview.1/iphone16pro-light-dark.png)。演示媒体均为合成数据。

使用同一 SideStore 账号覆盖安装并保留全部 Widget 扩展。Codex、Claude 在官方页面授权；DeepSeek 只在手机安全字段输入 API Key。凭据不进入聊天或 CI。

此前 preview.3 已实机通过三家取数、账户与读数保留、两类组件及日常功能。每日续签自动化完整流程已试跑成功；真实定时触发、锁屏及跨七天观察仍 UNKNOWN。

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
- [模块开发说明](docs/MODULES.md)
- [免费安装与实机验收](docs/INSTALL.md)
- [测试说明](docs/TESTING.md)
- [更新、续签与恢复](docs/MAINTENANCE.md)
- [机器可读的实机门槛](device-gate.json)

## 数据与许可

运行时由手机直接连接厂商，不需要自建服务器。凭据保存在本机 Keychain，共享快照只包含读数、时间和状态。CI 使用演示数据，真实凭据不会进入源码或 CI。

项目采用 Apache-2.0。设计时研究了 [AI Usage Limits](https://github.com/stavrop/ai-usage-limits)，其原始说明见 [UPSTREAM-NOTICE](docs/UPSTREAM-NOTICE.txt)。后续复用其登录实现时继续保留来源与许可。
