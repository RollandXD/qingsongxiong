# 交付状态

阶段：**工程骨架 / 免费签名实机验证前**。

## 已实现

- 六个 Swift Package 模块与可检查的依赖白名单。
- 轻松熊原生 App 壳、暖色主题、原创熊形标记、独立功能注册。
- AI 额度入口与平台路由；真实取数明确保持关闭。
- App Group 跨进程快照、版本检查、旧数据保护、共享 Keychain 探针。
- 总览与单平台两类安装验证组件。
- 架构检查、领域/存储测试、Debug 扩展性验证和原生 UI 测试。
- 固定工具版本的免费标准 macOS 构建流程与待重签 IPA 打包。

## 验证证据

- Linux 源码架构检查：PASS。
- Linux 源码凭据检查与脚本语法检查：PASS。
- Xcode 构建、Swift 测试、模拟器 UI：PENDING，需以真实 CI 结果更新。
- iPhone 安装、两类组件、共享容器/Keychain：UNKNOWN。
- 重新签名保留数据、Shadowrocket 恢复：UNKNOWN。
- 自动续签及跨七天稳定性：UNKNOWN。

## 下一步

完成云端真实编译，下载验证 IPA；指导用户安装 SideStore 并通过 `docs/INSTALL.md` 的实机核验。门槛未通过前不启用三家真实接入，不宣称首版已完成。

`device-gate.json` 仅记录真实实机结果，不含设备 UDID、Apple 账号或配对文件。
