# 交付状态

当前已发布：**v0.2.0-preview.1（0.2.0/6）**，原生回归及 iPhone 16 Pro 真机日常验收通过。

当前开发：**`codex/ios-polish-relay` 上的 0.3.0/7 候选，尚未发布，不能当成已验收交付**。

## 0.3.0 候选验收（2026-11-09）

范围：温润纸感与玻璃首页/详情、完整一次性状态动效、锁屏组件与交互刷新、按语义变化定向 reload、BGAppRefresh、APIKEY.FAN 两个审核接口、手机内中转账户管理与 Keychain。

| 验证 | 当前证据 |
| --- | --- |
| Linux 架构、源码凭据、Shell 语法 | PASS |
| 影片剪辑合同 | 5 项 Python 测试 PASS |
| Swift 包测试 | f46c36d 的 79 项 PASS；新增限流与恢复目录回归待 Apple 重跑 |
| Release iPhone IPA | f46c36d 构建 PASS；App/Widget 均 0.3.0/7，后台声明齐全，无合成演示入口 |
| 完整原生 UI、浅深色截图、原速/0.25× 影片 | 进行中，尚未验收 |
| 新版真机覆盖安装、真实中转余额、锁屏/着色/交互刷新 | UNKNOWN |
| 免费签名下 BG 实际频率、低电量行为、120Hz 手感 | UNKNOWN；15 分钟仅申请，不是承诺 |

当前 Apple 验证：[42649832709](https://github.com/RollandXD/qingsongxiong/actions/runs/42649832709)。全部媒体只使用合成账户。最终交付必须绑定完整回归通过的源码与 IPA 摘要；以下为上一发布版历史证据。

## 本版结果（2026-11-04）

来源提交 `1f35bab73f20d8ccf9857b7bafdf0eb99e532a2d`，源码树 `fb3e96f2d780f2e0692a769116a31ddebc96b731`。Xcode 27.1 构建，最低 iOS 27.0。主验收设备为 iPhone 16 Pro，实际模拟器系统 iOS 27.0，截图 1206×2622。

| 验证 | 结果 |
| --- | --- |
| Linux 架构、源码凭据与脚本语法 | PASS |
| Swift 包测试 | 63/63 PASS |
| 原生 UI 回归 | 14/14 PASS |
| Release iPhone 构建、待重签 IPA 与 SHA-256 | PASS |
| 基础英文签名名、中文品牌、组件版本与许可 | PASS |
| Release 不含合成演示入口 | PASS |
| 已连接/未连接首页浅深色描述、trait、文字截断、对比度审计 | PASS |
| 大字体下连接操作可达 | PASS |
| 窗口展开、焦点、单一展开、收起、余额分币种、部分失败、详情与前后台 | PASS |
| 原生截图与原速动效影片人工检查 | PASS |

证据：[原生 CI 41752016088](https://github.com/RollandXD/qingsongxiong/actions/runs/41752016088)、[设计预览发布页](https://github.com/RollandXD/qingsongxiong/releases/tag/v0.2.0-preview.1)、[构建验收记录](https://github.com/RollandXD/qingsongxiong/releases/download/v0.2.0-preview.1/verification.json)。截图和影片均使用合成数据；Widget 截图是共享原生布局的开发预览，真实组件已由用户在覆盖更新后确认正常。

IPA SHA-256：`261bcd658d36142b00141d9d75a5efa10da0ae400432bf0abdb1539362dc3167`。发布的 12 个文件远端摘要与本地逐一核对一致。

## 实现范围

- 暖中性色表面与三家剩余量优先首页；两条额度图形独立表达限制。
- 通用窗口最低剩余量作为摘要；代码审查与模型专属限制独立标注。点击窗口展开、对照、原位收起，同一时间只展开一家。
- DeepSeek 使用 Decimal 金额；完整一致时绘制赠送/充值组成，多币种分别显示。
- 原生玻璃操作控件、系统 zoom 详情转场、短暂入场与真实数据过渡、轻触觉；静止时不持续播放装饰动画。
- 主动刷新分别说明更新、核实未变与失败；旧数据保留时间和标记；连接成功但首次读取失败不误导重新登录。
- 总览中/大号、单平台小/中号复用展示模型和独立密度布局。着色模式按透明度区分轨道与填充，真实系统着色外观尚待真机确认。
- 八个 Swift Package 模块及依赖白名单；共享展示不访问网络或 Keychain，Widget 不依赖主 App 页面或交互登录。Debug 计数工具注册验证通过，Release 不展示。
- 账户、仓储、凭据、缓存格式、Bundle ID、Widget kind 与共享命名空间保持兼容。

## 已有真机证据

2026-11-03 用户确认：SideStore 0.7.0 首次刷新、免费签名、App/Widget 共享容器与 Keychain、组件跳转、重签保留数据、Shadowrocket 恢复均通过；三家手机授权取数与单平台组件真实读数/时间/跳转通过；preview.3（0.1.0/5）覆盖更新、两类组件各尺寸与日常功能正常。

每日快捷指令自动化完整流程已试跑成功：切换 LocalDevVPN、刷新 SideStore/轻松熊、停用 LocalDevVPN、恢复 Shadowrocket。真正的定时触发、锁屏和跨七天观察，以及实际令牌过期后的续期仍 UNKNOWN。`device-gate.json` 的 verified 只覆盖已确认的手动签名与共享能力。

## 真机验收与恢复

- 2026-11-04 用户确认 iPhone 16 Pro 覆盖更新、原账户与读数保留、两类组件及窗口展开/刷新/返回手感均正常。证据：[真机验收记录](https://github.com/RollandXD/qingsongxiong/releases/download/v0.2.0-preview.1/device-verification-2026-11-04.json)。
- 不再安排用户手动测试无障碍模式；实现保留基本兼容，以上自动审计已通过。
- 先前 UI 回归的页脚截断、返回定位与收起点击问题已复验修正。曾误用 Duo，现严格匹配 iPhone 16 Pro，并按机型选择兼容的 iOS 27 运行时；Xcode 版本不等同于模拟器系统版本。
- 上一实机验收版本为 [preview.3](https://github.com/RollandXD/qingsongxiong/releases/tag/v0.1.0-preview.3)，来源 `0d30c46`。恢复时保留已有数据，按维护指南用同账号覆盖处理，不先卸载。
