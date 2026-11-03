# 增加一个工具模块

先给功能分配稳定 ID，例如 `notes`。ID 用于路由、设置和数据命名空间，发布后不随显示名称改变。不要把功能模型或厂商协议搬入 BearFoundation。

## 建立编译边界

在 `Packages/BearKit` 新增 `NotesDomain`、`NotesData`、`NotesFeature`，并在 Package.swift 声明产品、target 和最小依赖。

- Domain 定义纯业务值、错误与仓储协议，只使用 Foundation 和确实通用的基础契约。
- Data 实现仓储，通过注入的存储、网络和时钟完成工作，不引用页面。
- Feature 使用 Domain 协议，负责页面和展示状态；不读取 Keychain 或直接调用 URLSession。

在 `architecture.json` 为每个新 target 增加 import 白名单，运行 `python3 scripts/check_architecture.py`。Mac CI 同时读取真实 Swift Package 依赖，因此只把 import 藏在其他文件里不能绕过边界。

## 在组合根注册

`AppShell/QingSongXiongApp.swift` 的 `AppComposition` 创建平台实现与功能依赖，再增加一项 `AppFeatureEntry`。注册项包括：

| 字段 | 模块需要提供的内容 |
| --- | --- |
| descriptor | 稳定 ID、显示名称、系统入口符号 |
| home | 模块首页，由自己的 Feature 层构建 |
| settings | 模块设置或账户入口 |
| clearLocalData | 取消工作、清除本模块私有状态的异步操作，失败返回 false |
| handle | 解释分配给本模块的路由片段，拒绝不认识的路径 |

App 壳负责分发功能 ID，不解释 Notes 的业务参数；Notes 也不直接引用 AIUsage 内部实现。新功能的汇总内容通过自己的入口提供，首页随已注册功能数量展示工具入口。若需要改变全局首页布局，在 App 壳处理，不在 AI 模块堆分支。

现有 Debug `--counter-proof` 会注册独立计数工具。原生 UI 测试进入该工具并增加计数，验证注册和状态隔离；Release 不包含这个工具。新增功能时可以沿用这种独立装配与验证方式。

## 隔离数据与并发

使用自己的 Keychain service、文件 namespace 与设置前缀。不要共用 `ai-usage.*` 或 `bear.appearance`，不要清除整个共享目录来实现“清除本模块”。

会跨 await 的请求必须保留账户/操作代次，并在写回前检查是否仍然有效；取消请求不能代替这个检查。失败读数保留原时间，未知值不变成零。若一次操作涉及多个存储，明确提交顺序与失败恢复，例如账户更换时缓存写入失败应恢复原凭据。

## 增加小组件

组件复用业务模型与展示规则，单独适配密度与系统着色。不要链接交互登录或主 App 页面。需要凭据轮换的功能由主 App 统一负责，组件提示打开 App；避免不同进程竞争刷新令牌。

为新功能声明独立 widget kind、App Intent 和路由。已发布 kind 与 Bundle ID 不随界面名称变化。共享权限必须通过真实签名后在手机验证，模拟器结果不能代替。

## 验证与交付

覆盖功能本身的缺失、失败、取消和竞争路径；UI 自动化只使用演示数据，安全输入截图保持为空。执行架构、凭据检查、Swift 包测试及适用的原生 UI 测试；再发布带来源提交、校验和及明确实测范围的待重签 IPA。

未知项写入 STATUS。自动续签、锁屏后台运行和跨七天稳定性必须依据实际观察，不能从一次安装或一次快捷指令成功推断。
