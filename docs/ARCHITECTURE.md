# 架构与扩展

轻松熊是模块化个人工具箱。AI 额度是首个功能；AppShell 不承担厂商解析、凭据保管或额度业务。

## 依赖边界

| 模块 | 职责 | 可依赖的项目模块 |
| --- | --- | --- |
| BearFoundation | 功能元数据、路由描述、基础存储契约 | 无 |
| BearDesignSystem | 熊形标记、主题、通用状态组件 | BearFoundation |
| BearPlatform | 原子共享存储、Keychain、签名探针 | BearFoundation |
| AIUsageDomain | 平台标识、额度/余额模型、仓储接口、业务路由 | BearFoundation |
| AIUsageData | 供应商适配、账户仓储与缓存、受限组件读取 | AIUsageDomain、BearFoundation、BearPlatform |
| AIUsagePresentation | App 与 Widget 复用的平台名称、符号与数值展示规则 | AIUsageDomain |
| AIUsageAuth | PKCE、手机回调、授权交换、主 App 令牌续期 | AIUsageData、AIUsageDomain、BearFoundation、BearPlatform |
| AIUsageFeature | SwiftUI 页面与展示状态 | AIUsageDomain、AIUsagePresentation、BearDesignSystem |

AppShell 是组合根：将仓储注入功能页面，创建功能注册表与全局导航。`architecture.json` 和 `check_architecture.py` 同时核对源码 import 与 Swift Package 依赖。

Widget 依赖领域、AIUsagePresentation、平台与数据层的受限读取能力和通用设计资源。`WidgetUsageReader` 使用未过期凭据独立取数，不轮换 refresh token、不写共享快照；凭据过期时提示打开 App。读取完成后再次检查账户 sessionID，防止退出后的迟到结果重新显示。

Widget 读取器仅持有 `UsageCredentialReading`、`UsageStateReading`，这两个协议没有保存或删除能力；主 App 仓储持有扩展了写入能力的 Store 协议。选择较新的组件读数时，仍保留同一账户另一份状态中的有效 Retry-After 期限。

`AIUsageAuth` 仅链接到主 App，Widget 禁止导入授权模块或浏览器框架。系统浏览器桥接由 AppShell 装配，不包含厂商协议。授权回调只监听手机 IPv4 回环地址，使用独立随机 state 与 PKCE；拒绝错误路径、来源和重复 state，退出时取消等待与网络任务。授权码与 refresh token 请求不自动重试，避免重复消费。

Codex、Claude 订阅额度读取参考上游手机端实现，部分接口不属于公开稳定 API，必须单独实机验证。Claude 的授权请求包含上游所需的 `org:create_api_key user:profile`，不调用创建密钥或模型接口；续期仅重放服务实际授予的 scope。未验证的 JWT 内容仅用于额度请求的账户头，不据此判定身份或权限。

`LiveAIUsageRepository` 是主 App 唯一的快照与令牌写入者。每个平台独立的代次与请求任务用于合并并发刷新、取消退出请求、拒绝旧账户结果。轮换出的 refresh token 在后续额度请求之前保存，失败保留原快照及其真实时间；限流按服务端 Retry-After 阻止过早请求。`UsageCredentialStore`、`UsageStateStore`、`HTTPClient`、`BearClock` 可分别替换。

## 新增功能

具体注册字段、数据隔离与验收步骤见 [模块开发说明](MODULES.md)。

1. 新建自己的 Domain / Data / Feature 模块，声明最小依赖与测试。
2. 在 `AppComposition` 注册稳定功能 ID、入口及路由处理；不修改 AI 核心。
3. 更新依赖白名单，由 CI 阻止越层引用。
4. 新功能的配置、Keychain service 和共享快照使用独立命名空间。

Debug 构建带 `--counter-proof` 启动参数时注册本地计数工具；UI 测试验证入口与独立状态。Release 编译不会包含此工具。

## 跨进程数据

共享快照有 schemaVersion，使用文件锁和原子写入；旧时间戳不能覆盖新结果。未知格式保留并报错，不静默当作空数据。领域层不包含 UI 色彩、图标或系统凭据 API。

Keychain 共享组的团队前缀优先从本 App 的安装描述文件解析，必要时查询系统默认访问组，不硬编码作者的 Team ID。App Group 先尝试描述文件中匹配本项目命名空间的组，再兼容签名工具的 `ALTAppGroups` 元数据与原始组名；只使用系统授予的容器。描述文件中的账号和设备列表不进入诊断或日志。

## 刷新协调与中转（0.3.0 候选）

- `AIUsageFeature/WidgetReloadPolicy.swift` 对平台按 windows、balances、availability、connection、failure 和 sessionID 生成语义签名；仅刷新时间变化不通知 Widget。`RelayModel` 同样比较账户、余额、可用性和失败，不因普通轮询反复 reload。组合根仅定向刷新 `QingSongXiong.Overview` / `QingSongXiong.Provider`，不使用 `reloadAllTimelines`。
- App 的 `Scene.backgroundTask(.appRefresh(...))` 在启动阶段注册后台处理，SwiftUI 将系统到期映射为 Task cancellation；仓储取消底层请求并拒绝迟到写回。每次过期检查先从共享缓存加载账户，后台冷启动不依赖首页出现；新读数和未连接账户不重复请求。进入后台和每次任务开始时申请下一次，`earliestBeginDate` 为 15 分钟而非实际执行承诺。iOS 27 使用 `submitTaskRequest(_:)` 捕获完整提交错误。
- 中转保留在既有 AI 额度领域内，不扩展三家的 `ProviderID`。`RelayAccount` 的 UUID 为稳定账户 ID，sessionID 是每次凭据替换的新代次；手机先请求验证，再提交新凭据槽和账户目录，失败不替换旧账户。
- 共享 `relay-states.json` 含 schemaVersion、账户和快照，不含 Key。Key 存独立 Keychain service `io.github.rollandxd.qingsongxiong.ai-usage.relay`。退役与待提交凭据槽有持久化恢复目录：先记目录再写 Key，最终提交才激活；提交和回滚同时失败仍可由隐私清除重试，不能遗失新槽。
- `RelayBalanceAdapter` 固定 APIKEY.FAN origin 与两个白名单端点；生产客户端禁用重定向，解析 Decimal 和显式可用状态，401/403 要求换 Key，429 复用 Retry-After。错误不展示服务器原文。
- `WidgetRelayReader` 与 `WidgetUsageReader` 只拿只读存储协议：可网络取数和维护进程内缓存，但不能续期或写共享快照；返回前再次确认账户代次。AppEntity 只暴露账户 ID 与名称，不暴露密钥。
- `BearDesignSystem/EnvironmentValues.bearReduceMotion` 合并系统只读辅助功能与可写测试覆盖值；测试只能加强减弱动效，不能关闭用户启用的系统偏好。关键帧使用值捕获，不在 Sendable 闭包中读取 MainActor 隔离属性。

## 演进

首版只声明 iPhone 支持。将来可共享领域与数据核心，分别设计 iPad、Mac 的界面与平台适配。只有已出现的跨功能能力进入共享层，不预建数据库、动态插件或账号后台。

## 额度展示与动效

AIUsagePresentation 提供 Foundation-only 的窗口类别、最低剩余通用窗口、精确 Decimal 余额组成和明确时间参数的旧读数判断。模型/代码审查窗口独立标注，未知限制保留原名；无完整一致数据不绘制余额占比。

BearDesignSystem 仅提供语义色、通用条形/弧形/组成图形与动效参数，不包含厂商规则。AIUsageFeature 的 DashboardInteraction 保存临时展开/焦点，账户 sessionID 改变时清空；数值动画限于同一账户、同一窗口。SharedUI/WidgetMetricContent.swift 同时编入 App 的 Debug 演示和 Widget，依赖白名单禁止访问仓储、授权或主 App 页面；数据由各组合根注入。

只有 Debug 模拟器的 --demo-usage / --widget-demo 会使用 DemoUsageRepository。该仓储只在内存生成合成数据，Release 不包含它，真机路径仍使用现有 Keychain 和共享缓存。
