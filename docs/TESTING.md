# 验证方式

## Linux

```sh
python3 scripts/check_architecture.py
python3 scripts/check_repository.py
python3 -m unittest discover -s scripts -p 'test_*.py'
bash -n scripts/install_xcodegen.sh scripts/apple_build.sh
```

Linux 检查验证源码边界、凭据排除和脚本语法；原生编译由 Xcode 执行。

## macOS / CI

固定 Xcode 27.1、XcodeGen 2.46.0，Swift 6 严格并发。主验收默认 iPhone 16 Pro。select_simulator.py 按机型匹配兼容的 iOS 27 运行时并实际创建设备，缺少目标机型直接报错；设备创建在编译前核验，启动在编译后执行。

Xcode 27.1 与模拟器 iOS 27.0 是两项独立事实。当前镜像中的 iOS 27.1 为 Duo 专属，不用于 iPhone 16 Pro 验收。可手动触发 Apple 运行时按需诊断，核对镜像变化。

- swift test --package-path Packages/BearKit --parallel：路由隔离、领域数值、Decimal、共享存储与版本拒绝、并发、退出迟到响应、令牌轮换、授权回调、展示映射、交互状态和刷新反馈。
- 原生 UI：账户安全入口、隐私清除、安装检查、功能注册、浅深色描述/trait/文字截断/对比度审计、大字体可达性、窗口焦点与单一展开、余额分币种、部分刷新失败、详情与前后台；组件覆盖总览、单平台、余额、三类锁屏和中转预览。
- 中转测试：两个 APIKEY.FAN 合同端点、Decimal、0/负值、nullish fallback、显式 false、401/403、429 与禁重定向；先验证再替换、失败回滚、凭据槽回收与隐私清除。Widget 不写盘、删除不复活，旧快照的有效 Retry-After 不被主动刷新绕过。
- 动效巡览：真实下拉、刷新成功/失败/未变化、阈值切换、窗口展开和切换、详情往返、前后台、中转余额；另测减弱动态效果。
- --ui-testing 仅在 Debug 模拟器使用易失凭据容器，避免未签名模拟器的 Keychain 权限干扰；真机使用共享 Keychain。安全输入截图只截空字段。
- --demo-usage 的合成场景包括 normal、stale、exhausted、missing、reconnect、partial、multi-currency；--widget-demo 与 Widget 使用同一份原生布局。Release 不包含这些演示入口。
- Release 构建与待重签 IPA 校验不需要真实账号、证书或 Apple 登录。打包核对英文签名名、中文本地化、版本与许可。

## 截图与动效影片

`apple.yml` 的 `workflow_dispatch` 可指定 `ui_tests` 为 `DesignUITests/testMotionTourAtNormalSpeed` 一类完整测试标识；留空跑全部。诊断命令使用短查询，不用 `gh run watch` 长时间阻塞会话。

xcresult 导出截图和测试附件，经人工检查才记录视觉验收。simctl 录像显式选择 primary 显示屏，并要求实际生成文件。

用 MP4 creation_time 与 BEAR_MOTION_START/END 时间戳裁出动作片段。1× 保持真实速度，另输出明确标为 0.25× 的逐帧检查版本，绝不用慢放片冒充真实手感。`export_motion.py` 校验区间与合成标记，定向运行或失败缺少结束标记时不伪造影片；5 项 Python 测试核对裁剪合同。进程启动时间不等于首帧时间，不能直接用 recording.json 的 startedAt 计算偏移。媒体只使用合成数据。

Widget 开发预览验证密度和展示规则；真实注册、Keychain 共享、系统着色、签名与刷新调度分别记录实际证据，不以布局预览替代。

## 0.2.0 设计预览 1 结果（2026-11-04）

来源 1f35bab：63 项包测试、14 项 UI 测试、Release 与 IPA 校验全 PASS，见 [原生 CI](https://github.com/RollandXD/qingsongxiong/actions/runs/41752016088)。已人工检查 iPhone 16 Pro / iOS 27.0 的首页浅深色、独立窗口与模型限制、余额组成、四种组件密度及原速影片，截图为 1206×2622。

用户确认 iPhone 16 Pro 覆盖更新、账户/读数保留、两类 Widget 和日常展开/刷新/返回手感均正常。Widget 系统着色外观未单独专项验收，透明度适配已实现。用户已免除手动真机无障碍模式测试，基本兼容由实现及上述自动审计负责。

实际令牌过期续期、每日自动化的真实定时/锁屏触发和跨七天稳定性仍 UNKNOWN，状态见 STATUS。历史构建证据可从 Git 与 Actions 回查。
