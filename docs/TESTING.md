# 验证方式

## Linux

```sh
python3 scripts/check_architecture.py
python3 scripts/check_repository.py
python3 -m unittest discover -s scripts -p 'test_*.py'
bash -n scripts/install_xcodegen.sh scripts/apple_build.sh
```

Linux 检查验证源码边界、凭据排除和脚本语法；原生编译由 Xcode 执行。

Linux 开发机已安装 Docker 与 `swift:6.2` 镜像时，推送前还应执行：

```sh
./scripts/local_typecheck.sh
./scripts/local_feature_tests.sh
```

前者编译 Foundation／Domain／Presentation；后者原样运行全部 Domain／Presentation 测试，以及脚本中明确列出的可移植控制器、仓储和历史测试。不要仅按新增功能挑选领域测试，否则接口语义调整后，旧回归要到 CI 才暴露。它们不覆盖 SwiftUI、UIKit、Keychain、原生像素与手势，不能替代 macOS 整包和原生 UI 验收。

## macOS / CI

固定 Xcode 27.1、XcodeGen 2.46.0，Swift 6 严格并发。主验收默认 iPhone 16 Pro。select_simulator.py 按机型匹配兼容的 iOS 27 运行时并实际创建设备，缺少目标机型直接报错；设备创建在编译前核验，启动在编译后执行。

Xcode 版本与模拟器版本是两项独立事实：0.2.0 的历史验收使用 iOS 27.0，本轮原生回归实际使用 iOS 27.2；每次以产物中的 `simulator-profile.json` 为准。选择器严格匹配 iPhone 16 Pro 和兼容的 iOS 27 运行时，不用 Duo 替代；缺少目标即失败。可手动触发 Apple 运行时按需诊断，核对镜像变化。

- swift test --package-path Packages/BearKit --parallel：路由隔离、领域数值、Decimal、共享存储与版本拒绝、并发、退出迟到响应、令牌轮换、授权回调、展示映射、交互状态和刷新反馈。
- 原生 UI：账户安全入口、隐私清除、安装检查、功能注册、浅深色描述/trait/文字截断/对比度审计、大字体可达性、窗口焦点与单一展开、余额分币种、部分刷新失败、详情与前后台；组件覆盖总览、单平台、余额、三类锁屏和中转预览。
- 中转测试：两个 APIKEY.FAN 合同端点、Decimal、0/负值、nullish fallback、显式 false、401/403、429 与禁重定向；先验证再替换、失败回滚、凭据槽回收与隐私清除。Widget 不写盘、删除不复活，旧快照的有效 Retry-After 不被主动刷新绕过。
- 动效巡览：真实下拉、刷新成功/失败/未变化、阈值切换、窗口展开和切换、详情往返、前后台、中转余额；另测减弱动态效果。
- --ui-testing 仅在 Debug 模拟器使用易失凭据容器，避免未签名模拟器的 Keychain 权限干扰；真机使用共享 Keychain。安全输入截图只截空字段。
- --demo-usage 的合成场景包括 normal、stale、exhausted、missing、reconnect、partial、multi-currency；--widget-demo 与 Widget 使用同一份原生布局。Release 不包含这些演示入口。
- Release 构建与待重签 IPA 校验不需要真实账号、证书或 Apple 登录。打包核对英文签名名、中文本地化、版本与许可。

## 截图与动效影片

`apple.yml` 的 `workflow_dispatch` 可指定 `ui_tests` 为 `DesignUITests/testMotionTourAtNormalSpeed` 一类完整测试标识；留空跑全部。诊断命令使用短查询，不用 `gh run watch` 长时间阻塞会话。

xcresult 导出截图和测试附件，经人工检查才记录视觉验收。simctl 录像显式选择 primary 显示屏，并要求实际生成文件。完整 UI 步骤预算 35 分钟、Apple job 预算 50 分钟：19 项原生回归曾全部通过，但模拟器准备与回归总耗时约 26 分钟，旧 25 分钟外层限制仍将整条流水线判为超时失败；扩大预算后必须整轮重跑，不沿用失败 run 发布。

用 MP4 creation_time 与 BEAR_MOTION_START/END 时间戳裁出动作片段。1× 保持真实速度，另输出明确标为 0.25× 的逐帧检查版本，绝不用慢放片冒充真实手感。`export_motion.py` 校验区间与合成标记，定向运行或失败缺少结束标记时不伪造影片；5 项 Python 测试核对裁剪合同，另 1 项在 FFmpeg/ffprobe 可用时实际验证帧数保留及四倍时间戳。导出显式使用 `-fps_mode vfr -enc_time_base demux`：simctl 原始录像的名义帧率可能只有 0.25fps，但 PTS 仍含密集动态帧，仅设置 VFR 而不保留时间基仍会丢帧。进程启动时间不等于首帧时间，不能直接用 recording.json 的 startedAt 计算偏移。媒体只使用合成数据。

Widget 开发预览验证密度和展示规则；真实注册、Keychain 共享、系统着色、签名与刷新调度分别记录实际证据，不以布局预览替代。

### 玻璃表面的文字对比度复核

原生审计仍覆盖元素描述、trait、文字截断与 contrast。原生 OCR 对短中文、动态倒计时或玻璃合成层报 contrast 时，仅允许用**该元素当时的实际截图**复核：取局部边缘中位底色，识别主/次/状态文字的语义墨色，以 WCAG 公式计算至少 4.5:1。原生审计若返回可滚动内容中尚未完整入屏的元素，先最多滚动 3 次使其完整入屏，并保存 `contrast-revealed-element` 附件；仍越界、无滚动容器、墨色样本不足或不能核实就继续失败。不裁出越界文字的可见部分冒充完整复核。图表系列色不算文字墨色，其他审计类型不走此例外。

`RenderedContrastTests` 用高/低对比、浅底、渐变、无可识别墨色及四边越界样本验证门禁。滚动可能销毁 SwiftUI 的旧 AX binding；重新定位仍要求标识／文字、类型与原横向槽位／尺寸一致，且只有一个候选。左右两罐同名“5 小时”不能互相替代，同槽位多处重复时不得按 y 最近者猜测；相关回归同时覆盖唯一与歧义候选。该复核是采样级补充，不代表整页 WCAG 认证，也不替代实际浅深色截图检查。审计回退会在 CI 输出 `BEAR_RENDERED_CONTRAST`，低对比与不能核实分别输出 `BEAR_RENDERED_LOW` / `BEAR_RENDERED_UNRESOLVED`，不得静默跳过。

## 0.3.0 设计与刷新预览 1 结果（2026-11-09）

[完整 CI 42667595375](https://github.com/RollandXD/qingsongxiong/actions/runs/42667595375) 成功；构建来源 `eb5777d3622fd273bc4897b2bf7627e7372652f7`，87 项包测试、19 项原生 UI、Release 与 IPA 校验通过。Swift 包并行进程的测试数为 `5 + 2 + 16 + 14 + 3 + 36 + 11 = 87`，不能取单个进程最大值或重复相加原生总计。

实际运行 iPhone 16 Pro / iOS 27.2，浅深色首页、三家详情、组件/锁屏共享布局、中转增删改等 32 张合成截图人工检查通过。原生审计及减弱动效回归保留。

同次 CI 原始录像含 9,890 帧，但原导出按静止段名义帧率只留下 27 帧巡览。媒体工具修复 `dc8dfd73d6af511724131981b674c9769ff67759` 不修改 App / Widget；Linux FFmpeg n9.0.2 重导保留 1,658 帧，原速 105.478333 秒、慢放 421.858333 秒，6 项本地媒体测试通过。发布包仍为完整绿灯 CI 原包；重导来源与原始录像摘要记录在发布附件 `verification.json`。影片可用于状态变化和动作路径复核，不代表 120Hz 性能认证。

新版真机覆盖安装、真实 APIKEY.FAN 读数、系统着色与组件宿主交互、免费签名后台实际频率及低电量行为仍 UNKNOWN。自动回归通过不替代这些结果。

## 0.2.0 设计预览 1 结果（2026-11-04）

来源 1f35bab：63 项包测试、14 项 UI 测试、Release 与 IPA 校验全 PASS，见 [原生 CI](https://github.com/RollandXD/qingsongxiong/actions/runs/41752016088)。已人工检查 iPhone 16 Pro / iOS 27.0 的首页浅深色、独立窗口与模型限制、余额组成、四种组件密度及原速影片，截图为 1206×2622。

用户确认 iPhone 16 Pro 覆盖更新、账户/读数保留、两类 Widget 和日常展开/刷新/返回手感均正常。Widget 系统着色外观未单独专项验收，透明度适配已实现。用户已免除手动真机无障碍模式测试，基本兼容由实现及上述自动审计负责。

实际令牌过期续期、每日自动化的真实定时/锁屏触发和跨七天稳定性仍 UNKNOWN，状态见 STATUS。历史构建证据可从 Git 与 Actions 回查。
