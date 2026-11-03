# 交付状态

阶段：**手动免费签名与共享能力门槛通过 / 进入真实平台接入**。

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
- 首个验证包安装：FAIL（Apple 拒绝中文 `appIdName`）。verification.2 实机安装与启动：PASS（2026-11-03 用户确认）。
- 两类组件、共享容器/Keychain：PASS（2026-11-03 用户确认 App 三项通过，两类组件编号一致且钥匙串可读）。
- 单平台组件路由：PASS（用户将单平台组件设为 Claude，确认跳转正确）。
- 重新签名保留数据、Shadowrocket 恢复：PASS（2026-11-03 用户确认；重签后未重新写入，原编号和共享状态保留）。
- 自动续签及跨七天稳定性：UNKNOWN。

## 下一步

用户已完成 verification.2 的手动免费签名与共享能力验收。`device-gate.json` 的 verified 仅指这一范围，自动续签及跨七天稳定性仍为 UNKNOWN。开始逐家手机取数接入、凭据生命周期与正式界面；完成后仍须使用新包进行真实账户验收，不宣称首版已完成。

`device-gate.json` 仅记录真实实机结果，不含设备 UDID、Apple 账号或配对文件。
