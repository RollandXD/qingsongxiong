# 交付状态

阶段：**手动免费签名与共享门槛、三家手机授权取数通过 / 界面与维护收尾中**。

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
- Codex/Claude 系统浏览器授权、手机回环回调、PKCE、令牌续期和订阅适配器已实现。preview.2 用户确认两家的手机授权与额度读取均成功。
- preview.2 `d85a3b6` 原生 CI：43 项包测试、4 项 UI 测试、Release iPhone 构建与 IPA 校验全部 PASS（[CI 41627496760](https://github.com/RollandXD/qingsongxiong/actions/runs/41627496760)）。浅色授权入口和实际深色截图已检查。
- 新增功能数据清除、开源许可页面、中号总览三列布局及大字体截图测试；本增量尚待原生 CI 和新包验收。
- 复核补充账户更换时缓存写入失败的凭据恢复，以及组件保留有效 Retry-After 的测试；组件存储依赖缩窄为只读协议。本补丁尚待原生 CI。

## 验证证据

- Linux 源码架构检查：PASS。
- 越层依赖反向检查：PASS（临时副本中分别向 Domain 注入 SwiftUI、向 Widget 注入 AIUsageAuth，均被检查脚本拒绝；不修改真实源码）。
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
- Codex、Claude 手机授权与真实额度：PASS（2026-11-03 用户确认 preview.2 两家均成功）。两家的组件真实读数、更新时间与点击跳转：PASS（同日用户确认均正常）。令牌实际过期后的续期仍待实测。
- 自动续签及跨七天稳定性：UNKNOWN。
- SideStore `Refresh All Apps` 快捷指令手动执行：PASS（2026-11-03 用户确认 SideStore 和轻松熊到期时间已更新）。
- 每日自动化配置与完整流程试跑：PASS（2026-11-03 用户确认改用每日触发，整条续签、停用 LocalDevVPN、恢复 Shadowrocket 流程已试跑成功）。没有采用充电触发；实际定时触发、锁屏和跨七天观察仍 UNKNOWN。

## 下一步

用户已完成 verification.2 的手动免费签名与共享能力、preview.1 的 DeepSeek 及 preview.2 的 Codex/Claude 手机授权取数与单平台组件验收。`device-gate.json` 的 verified 仅指手动签名和共享能力范围，自动续签及跨七天稳定性仍为 UNKNOWN。接下来完成新增界面原生验证、总览新布局、可访问性和续签维护流程；不宣称长期运行已验证。

`device-gate.json` 仅记录真实实机结果，不含设备 UDID、Apple 账号或配对文件。
