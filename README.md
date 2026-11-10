# 轻松熊 · QingSongXiong

温暖、精致的 Apple 个人工具箱。AI 额度监控是第一个功能模块，支持 Codex、Claude 订阅额度与 DeepSeek API 余额。

**当前发布：v0.4.0-preview.1（0.4.0/8）**，来源分支 `claude/ios-honey-redesign`。本版以双格蜜罐、回满预览时间尺和余额列表重做首页，设置移到右上角，详情与小组件同步调整。完整 Apple 流水线通过：103 项 Swift 包测试、19 项原生 UI 测试、Release 与待重签 IPA 校验；61 张合成数据原生截图及动效抽帧已检查。**本版真机覆盖安装与真实中转余额仍待验证**。

[下载与扫码入口](https://github.com/RollandXD/qingsongxiong/releases/tag/v0.4.0-preview.1) · [直接下载 IPA](https://github.com/RollandXD/qingsongxiong/releases/download/v0.4.0-preview.1/QingSongXiong-needs-signing.ipa) · [原速影片](https://github.com/RollandXD/qingsongxiong/releases/download/v0.4.0-preview.1/iphone16pro-native-motion-1x.mp4) · [浅深色截图](https://github.com/RollandXD/qingsongxiong/releases/download/v0.4.0-preview.1/iphone16pro-light-dark.png)。媒体均为合成数据；Widget 图片是共享原生布局预览，不是系统宿主实拍。精选截图包共 57 张，已移除原始设备标识。

上一已实机验收版本 [v0.2.0-preview.1（0.2.0/6）](https://github.com/RollandXD/qingsongxiong/releases/tag/v0.2.0-preview.1) 保留为恢复参考；其 iPhone 16 Pro 覆盖更新、账户/读数、两类组件与日常交互已由用户确认，不将历史真机结果套用于本版。

使用同一 SideStore 账号覆盖安装并保留全部 Widget 扩展。Codex、Claude 在官方页面授权；DeepSeek 只在手机安全字段输入 API Key。凭据不进入聊天或 CI。

此前 preview.3 已实机通过三家取数、账户与读数保留、两类组件及日常功能。每日续签自动化完整流程已试跑成功；真实定时触发、锁屏及跨七天观察仍 UNKNOWN。

## 0.4.0 的蜜罐首页

- Codex / Claude 每家一只双格蜜罐，5 小时与本周额度独立表达，不把比例相加；状态卡提示当前最紧窗口。
- 按住回满时间尺预览未来状态，松手恢复实测读数；已过重置时间的缓存仅提示「待刷新确认」，不自动冒充 100% 已回满。
- 余额列表保留账户与币种边界；设置位于右上角，移除底部 TabView。三家详情与主屏小组件沿用同一展示规则。
- 说明及倒计时支持换行，蜜罐文字稳定底色；原生审计保留 4.5:1 门槛，越界元素先有限滚动，再按完整截图复核。
- [完整 CI 42769159302](https://github.com/RollandXD/qingsongxiong/actions/runs/42769159302) 对应构建 `f3ba5895e95c9974409bfd2c5807779a06aed021`；tag 固定到此提交，不指向后续文档。原速 51.26 秒、0.25× 205.03 秒，均为 1,399 帧；不据此声称真机 120Hz 达标。

## 延续 0.3.0 的刷新与中转

- 前台每 5 分钟检查；主 App 仅在读数、可用性、账户或失败状态变化时定向通知两类组件，时间戳变化不触发额外 reload。
- 组件申请 15 分钟时间线；倒计时由系统文字自行更新。主屏刷新按钮主动取数，受限 Reader 不续期 token、不写共享快照。订阅 token 过期仍需打开 App。
- `BGAppRefresh` 申请不早于 15 分钟，三家与中转并行检查；系统决定是否、何时实际触发。免费签名、低电量、后台权限下的频率仍 **UNKNOWN**，不承诺精确周期。
- 首页「中转额度」→ 管理/添加账户，模板固定 `https://api.apikey.fan`，默认 `/user/balance`；可选 `/v1/usage`。先验证再保存，失败不更换原账户，编辑时空 Key 保留原值。
- API Key 只在手机安全输入，存入独立共享 Keychain service；拒绝所有重定向，不发模型请求，不访问网页 Cookie。不同账户和币种不合计，负值不截零，未返回的状态不猜测。
- 单平台组件可配置独立中转账户；大号总览附中转余额。锁屏提供圆形、矩形、单行布局。真实系统着色、交互刷新与后台周期待用户覆盖安装后观察。

## 工程

- iPhone / iOS 27.0+，Swift 6，SwiftUI、WidgetKit、App Intents。
- 八个 Swift Package 模块：基础能力、设计系统、平台实现、AI 领域、AI 数据、AI 共享展示规则、AI 页面、仅主 App 使用的 AI 授权。
- AppShell 统一装配依赖和注册功能；小组件不依赖主 App 页面或交互式登录。
- GitHub 公共仓库标准 `xcode-27` 构建机，Xcode 27.1，固定 XcodeGen 与 Actions 版本。

## 从 Linux 开发

```sh
python3 scripts/check_architecture.py
python3 scripts/check_repository.py
```

提交代码后，Actions 执行 Swift 包测试、模拟器 UI 测试并生成待重签 IPA。`QingSongXiong-needs-signing.ipa` **没有 Apple 开发者签名**，必须由 SideStore 使用你自己的账户重新签名后安装。

有 Mac / 对应 Xcode 的环境还可以执行：

```sh
xcodegen generate --spec project.yml
swift test --package-path Packages/BearKit
```

## 当前验收

- [交付状态](docs/STATUS.md)
- [架构与增加新功能](docs/ARCHITECTURE.md)
- [模块开发说明](docs/MODULES.md)
- [免费安装与实机验收](docs/INSTALL.md)
- [测试说明](docs/TESTING.md)
- [更新、续签与恢复](docs/MAINTENANCE.md)
- [机器可读的实机门槛](device-gate.json)

## 数据与许可

运行时由手机直接连接厂商，不需要自建服务器。凭据保存在本机 Keychain，共享快照只包含读数、时间和状态。CI 使用演示数据，真实凭据不会进入源码或 CI。

项目采用 Apache-2.0。设计时研究了 [AI Usage Limits](https://github.com/stavrop/ai-usage-limits)，其原始说明见 [UPSTREAM-NOTICE](docs/UPSTREAM-NOTICE.txt)。后续复用其登录实现时继续保留来源与许可。
