# 交付状态

当前已发布：**v0.3.0-preview.1（0.3.0/7）**，来源分支 **`codex/ios-polish-relay`**。完整原生回归、Release IPA 和合成数据视觉验收已通过；**本版真机覆盖安装及真实中转余额尚未验证**，不把模拟器验收冒充真机结果。

[下载与扫码入口](https://github.com/RollandXD/qingsongxiong/releases/tag/v0.3.0-preview.1) · [机器可读验收](https://github.com/RollandXD/qingsongxiong/releases/download/v0.3.0-preview.1/verification.json)

## 0.3.0 设计与刷新预览 1（2026-11-09）

范围：温润纸感与玻璃首页/详情、一次性状态动效、主屏与锁屏组件、交互刷新、语义变化定向 reload、BGAppRefresh，以及 APIKEY.FAN 两个审核接口和手机内中转账户管理。

来源提交 `eb5777d3622fd273bc4897b2bf7627e7372652f7`，源码树 `dda2ba0754b252e435d3d0338c3ed2733f59a0ec`；发布 tag 固定到实际构建提交，不把后续媒体工具或文档提交冒充构建来源。Xcode 27.1，iPhone 16 Pro 模拟器实际 iOS 27.2，截图 1206×2622，最低系统要求仍为 iOS 27.0。

| 验证 | 当前证据 |
| --- | --- |
| Linux 架构、源码凭据与 Shell 语法 | PASS |
| 影片剪辑合同 | CI 的 5 项 PASS；本机新增 VFR 回归后 6/6 PASS |
| Swift 包测试 | 87/87 PASS（7 个并行子进程计数求和） |
| 原生 UI | 19/19 PASS，完整 run 成功 |
| Release iPhone IPA | App / Widget 均 0.3.0/7；后台声明及 Widget 齐全，无合成演示入口 |
| 首页/三家详情、窗口、余额、中转浅深色截图 | 32 张合成数据原生截图人工检查 PASS |
| 组件、三种锁屏布局与交互路径 | 共享原生布局预览及自动测试 PASS；真实系统宿主行为待真机 |
| 原速与 0.25× 动效 | 同次 CI 原始录像重导，均保留 1,658 帧；动作路径抽帧复核 PASS，不据此声称 120Hz 性能达标 |
| 新版真机覆盖安装、原账户/读数保留、真实中转余额 | UNKNOWN |
| 系统着色、组件实际交互与免费签名 BG 频率 | UNKNOWN；观察 1–2 天，15 分钟只是申请 |
| 低电量行为、120Hz 真机手感 | UNKNOWN |

证据：[完整 CI 42667595375](https://github.com/RollandXD/qingsongxiong/actions/runs/42667595375)、[发布页](https://github.com/RollandXD/qingsongxiong/releases/tag/v0.3.0-preview.1)、随包 `verification.json` 与 `SHA256SUMS.txt`。原生对比度审计的截图采样回退与限制见 [测试说明](TESTING.md)，不宣称整页 WCAG 认证。

IPA SHA-256：`6008ff7dec4335a5b75f0b104f7138da345ea649be635caf84212f20a4442a05`。发布的 12 个附件已按 GitHub 远端 digest 与本地 SHA-256 逐一核对。媒体只用合成数据，发布截图清单不含 xcresult 原始设备标识；Widget 图不是系统主屏或锁屏实拍。

媒体导出单独修复于 `dc8dfd73d6af511724131981b674c9769ff67759`：保留 VFR 与 demux 时间基，纠正原始录像被自动编码成每 4 秒一帧的问题。发布影片在 Linux / FFmpeg n9.0.2 从同次成功 CI 的原始录像重导，原速 105.48 秒、慢放 421.86 秒，未改动或重打 IPA。此后 App、Widget、资源及 Swift 测试均与已通过 CI 的构建来源相同。

### 后续与恢复

交付编号 `qingsongxiong-ios-polish-relay`：实现、自动回归和下载安装包由本轮交付完成；用户同一 SideStore 账号**覆盖安装、不先卸载**，确认原账户/读数保留后再填 APIKEY.FAN Key，观察组件和后台 1–2 天。不要求额外手动测试无障碍模式。安全、安装及观察范围见 [安装说明](INSTALL.md) 与 [维护说明](MAINTENANCE.md)。

本分支提交并推送，不擅自合并 `main`、不改写历史。上一已实机验收的 `v0.2.0-preview.1` 保留为恢复参考，恢复也用原账号覆盖。`device-gate.json` 仍只表示历史手动签名和共享能力已通过，不把本次 UNKNOWN 改成 verified。

独立交付的结果、验收标准、负责方和下一步以本页及发布附件为准，后续验证按交付编号 `qingsongxiong-ios-polish-relay` 接续。

## 0.2.0 设计预览 1 历史结果（2026-11-04）

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

## 0.2.0 历史实现范围

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
