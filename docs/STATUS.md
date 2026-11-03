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
- Xcode 工程生成、Swift 包测试：PASS（CI `4cb519f`）。
- Release 真机目标构建及待重签 IPA 打包：PASS（CI `4cb519f`）。
- 模拟器 UI：3/3 通过，CI `2141f2d` 整体成功且截图导出完成，视觉核验中。
- 验证 IPA：来源 `24082c0`，SHA-256 核对通过，已发布 [v0.1.0-verification.1](https://github.com/RollandXD/qingsongxiong/releases/tag/v0.1.0-verification.1)；主 App 与 Widget 扩展可执行文件齐全。
- SideStore 0.7.0 登录与首次手动刷新：PASS（2026-11-03 用户确认；先前 -80045 经 Anisette 配置排查后恢复）。
- 首个验证包安装：FAIL（Apple 拒绝中文 `appIdName`，尚未进入 App 启动阶段）。修复为英文基础显示名与中文本地化品牌资源，重新构建并验证真实包内资源。
- iPhone 安装、两类组件、共享容器/Keychain：UNKNOWN。
- 重新签名保留数据、Shadowrocket 恢复：UNKNOWN。
- 自动续签及跨七天稳定性：UNKNOWN。

## 下一步

先验证名称兼容修正版 IPA 并更新下载入口，再指导用户通过 `docs/INSTALL.md` 的实机核验。电脑已能识别 iOS 27.0.1；2026-11-03 用户确认原生兼容启动器可正常点击、SideStore 安装成功，开发者信任、手机登录与首次刷新通过。轻松熊共享能力仍待实机验收。门槛未通过前不启用三家真实接入，不宣称首版已完成。

`device-gate.json` 仅记录真实实机结果，不含设备 UDID、Apple 账号或配对文件。
