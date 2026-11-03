# 交付状态

阶段：**手动免费签名与共享能力门槛通过 / DeepSeek 实机通过 / Codex、Claude 授权验证中**。

## 已实现

- 八个 Swift Package 模块与可检查的依赖白名单；AI 共享展示供 App/Widget 复用，交互授权模块只进入主 App。
- 轻松熊原生 App 壳、暖色主题、原创熊形标记、独立功能注册。
- AI 额度入口与平台路由；公开 preview.1 支持 DeepSeek 官方 API 余额，App 和组件已实机验收。
- App Group 跨进程快照、版本检查、旧数据保护、共享 Keychain 探针。
- 总览与单平台两类组件；共享能力与 DeepSeek 业务数据路径已实测。
- 架构检查、领域/存储测试、Debug 扩展性验证和原生 UI 测试。
- 固定工具版本的免费标准 macOS 构建流程与待重签 IPA 打包。
- 第三阶段进行中：三家独立响应解析、DeepSeek 官方只读余额请求、可注入时钟和 HTTP 客户端；21 项包测试与原生构建在 CI `6b3a890` 通过。
- 账户仓储、DeepSeek 安全输入与余额页面、受限 Widget 读取路径、并发/退出/轮换测试在 `6f26d2e` 通过原生 CI。
- 新增 Codex/Claude 系统浏览器授权、手机回环回调、PKCE、令牌续期和订阅适配器。本增量尚待原生 CI 与用户实机授权验证，不标为已通过。

## 验证证据

- Linux 源码架构检查：PASS。
- Linux 源码凭据检查与脚本语法检查：PASS。
- Xcode 工程生成、11 项 Swift 包测试：PASS（CI `578c8ef`）。
- Release 真机目标构建及待重签 IPA 打包：PASS（CI `578c8ef`）。
- 模拟器 UI：3/3 通过，CI `578c8ef` 整体成功且截图导出完成。
- DeepSeek 增量 `6f26d2e`：30 项 Swift 包测试、4 项原生 UI 测试、Release 构建/IPA 打包全部 PASS（[CI 41622637175](https://github.com/RollandXD/qingsongxiong/actions/runs/41622637175)）。
- 浅色首页、实际深色页面与空密钥输入页截图：已人工检查（`6f26d2e`）；大字体、VoiceOver、减少动态效果、降低透明度与真实额度页的完整视觉验收仍待完成。
- 名称兼容修正版 IPA：来源 `578c8ef`，SHA-256、主 App/Widget 基础英文名和中文本地化资源检查通过，已发布 [v0.1.0-verification.2](https://github.com/RollandXD/qingsongxiong/releases/tag/v0.1.0-verification.2)。首包保留历史来源并明确标记已知问题。
- SideStore 0.7.0 登录与首次手动刷新：PASS（2026-11-03 用户确认；先前 -80045 经 Anisette 配置排查后恢复）。
- 首个验证包安装：FAIL（Apple 拒绝中文 `appIdName`）。verification.2 实机安装与启动：PASS（2026-11-03 用户确认）。
- 两类组件、共享容器/Keychain：PASS（2026-11-03 用户确认 App 三项通过，两类组件编号一致且钥匙串可读）。
- 单平台组件路由：PASS（用户将单平台组件设为 Claude，确认跳转正确）。
- 重新签名保留数据、Shadowrocket 恢复：PASS（2026-11-03 用户确认；重签后未重新写入，原编号和共享状态保留）。
- DeepSeek 官方余额：PASS（2026-11-03 用户确认 preview.1 的 App 与 DeepSeek 组件均正确显示；不收集实际金额或密钥）。
- Codex、Claude 手机授权、真实额度和组件：UNKNOWN，等待新增代码原生构建及实机验收。
- 自动续签及跨七天稳定性：UNKNOWN。

## 下一步

用户已完成 verification.2 的手动免费签名与共享能力验收及 preview.1 的 DeepSeek 真机验收。`device-gate.json` 的 verified 仅指手动签名和共享能力范围，自动续签及跨七天稳定性仍为 UNKNOWN。接下来验证 Codex、Claude 授权与真实读数，并完成可访问性、隐私清除和续签维护流程；不宣称首版已完成。

`device-gate.json` 仅记录真实实机结果，不含设备 UDID、Apple 账号或配对文件。
