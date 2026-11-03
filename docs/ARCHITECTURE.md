# 架构与扩展

轻松熊是模块化个人工具箱。AI 额度是首个功能；AppShell 不承担厂商解析、凭据保管或额度业务。

## 依赖边界

| 模块 | 职责 | 可依赖的项目模块 |
| --- | --- | --- |
| BearFoundation | 功能元数据、路由描述、基础存储契约 | 无 |
| BearDesignSystem | 熊形标记、主题、通用状态组件 | BearFoundation |
| BearPlatform | 原子共享存储、Keychain、签名探针 | BearFoundation |
| AIUsageDomain | 平台标识、额度/余额模型、仓储接口、业务路由 | BearFoundation |
| AIUsageData | 仓储实现；目前真实接入受实机门槛限制 | AIUsageDomain、BearPlatform |
| AIUsageFeature | SwiftUI 页面与展示状态 | AIUsageDomain、BearDesignSystem |

AppShell 是组合根：将仓储注入功能页面，创建功能注册表与全局导航。`architecture.json` 和 `check_architecture.py` 同时核对源码 import 与 Swift Package 依赖。

Widget 仅依赖领域、平台的受限读取能力和通用设计资源。交互式 OAuth 驱动将来只加入主 App 路径；Widget 不轮换 refresh token。

## 新增功能

1. 新建自己的 Domain / Data / Feature 模块，声明最小依赖与测试。
2. 在 `AppComposition` 注册稳定功能 ID、入口及路由处理；不修改 AI 核心。
3. 更新依赖白名单，由 CI 阻止越层引用。
4. 新功能的配置、Keychain service 和共享快照使用独立命名空间。

Debug 构建带 `--counter-proof` 启动参数时注册本地计数工具；UI 测试验证入口与独立状态。Release 编译不会包含此工具。

## 跨进程数据

共享快照有 schemaVersion，使用文件锁和原子写入；旧时间戳不能覆盖新结果。未知格式保留并报错，不静默当作空数据。领域层不包含 UI 色彩、图标或系统凭据 API。

Keychain 共享组的团队前缀优先从本 App 的安装描述文件解析，必要时查询系统默认访问组，不硬编码作者的 Team ID。App Group 先尝试描述文件中匹配本项目命名空间的组，再兼容签名工具的 `ALTAppGroups` 元数据与原始组名；只使用系统授予的容器。描述文件中的账号和设备列表不进入诊断或日志。

## 演进

首版只声明 iPhone 支持。将来可共享领域与数据核心，分别设计 iPad、Mac 的界面与平台适配。只有已出现的跨功能能力进入共享层，不预建数据库、动态插件或账号后台。
