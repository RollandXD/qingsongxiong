# 交付状态

阶段：**工程骨架 / 免费签名实机验证中**。

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
- Xcode 工程生成、11 项 Swift 包测试：PASS（CI `578c8ef`）。
- Release 真机目标构建及待重签 IPA 打包：PASS（CI `578c8ef`）。
- 模拟器 UI：3/3 通过，CI `578c8ef` 整体成功且截图导出完成。
- 浅色首页与平台详情截图：已人工检查；`2141f2d` 的 signing-dark 附件实际仍为浅色，深色视觉验收保持 UNKNOWN，后续需通过 App 内主题入口验证。
- 名称兼容修正版 IPA：来源 `578c8ef`，SHA-256、主 App/Widget 基础英文名和中文本地化资源检查通过，已发布 [v0.1.0-verification.2](https://github.com/RollandXD/qingsongxiong/releases/tag/v0.1.0-verification.2)。首包保留历史来源并明确标记已知问题。
- SideStore 0.7.0 登录与首次手动刷新：PASS（2026-11-03 用户确认；先前 -80045 经 Anisette 配置排查后恢复）。
- 首个验证包安装：FAIL（Apple 拒绝中文 `appIdName`，尚未进入 App 启动阶段）。已修复并验证真实包内资源；修正版实机结果待用户确认。
- iPhone 安装、两类组件、共享容器/Keychain：UNKNOWN。
- 重新签名保留数据、Shadowrocket 恢复：UNKNOWN。
- 自动续签及跨七天稳定性：UNKNOWN。

## 下一步

已给用户 verification.2 下载二维码与导入步骤，等待安装和启动结果；随后按 `docs/INSTALL.md` 检查两类组件、共享容器、共享 Keychain、重签数据保留与网络恢复。电脑已能识别 iOS 27.0.1；2026-11-03 用户确认原生兼容启动器可正常点击、SideStore 安装成功，开发者信任、手机登录与首次刷新通过。门槛未通过前不启用三家真实接入，不宣称首版已完成。

`device-gate.json` 仅记录真实实机结果，不含设备 UDID、Apple 账号或配对文件。
