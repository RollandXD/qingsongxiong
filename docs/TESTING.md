# 验证方式

## Linux

```sh
python3 scripts/check_architecture.py
python3 scripts/check_repository.py
bash -n scripts/install_xcodegen.sh scripts/apple_build.sh
```

Linux 检查验证源码边界、凭据排除和脚本语法；原生编译由 Xcode 执行。

## macOS / CI

固定 Xcode 27.1、XcodeGen 2.46.0，Swift 6 严格并发。主验收默认 iPhone 16 Pro。select_simulator.py 按机型匹配兼容的 iOS 27 运行时并实际创建设备，缺少目标机型直接报错；设备创建在编译前核验，启动在编译后执行。

Xcode 27.1 与模拟器 iOS 27.0 是两项独立事实。当前镜像中的 iOS 27.1 为 Duo 专属，不用于 iPhone 16 Pro 验收。可手动触发 Apple 运行时按需诊断，核对镜像变化。

- swift test --package-path Packages/BearKit --parallel：路由隔离、领域数值、Decimal、共享存储与版本拒绝、并发、退出迟到响应、令牌轮换、授权回调、展示映射、交互状态和刷新反馈。
- 原生 UI：账户安全入口、隐私清除、安装检查、功能注册、浅深色描述/trait/文字截断/对比度审计、大字体可达性、窗口焦点与单一展开、余额分币种、部分刷新失败、详情与前后台，以及四种组件密度。
- --ui-testing 仅在 Debug 模拟器使用易失凭据容器，避免未签名模拟器的 Keychain 权限干扰；真机使用共享 Keychain。安全输入截图只截空字段。
- --demo-usage 的合成场景包括 normal、stale、exhausted、missing、reconnect、partial、multi-currency；--widget-demo 与 Widget 使用同一份原生布局。Release 不包含这些演示入口。
- Release 构建与待重签 IPA 校验不需要真实账号、证书或 Apple 登录。打包核对英文签名名、中文本地化、版本与许可。

## 截图与原速影片

xcresult 导出截图和测试附件，经人工检查才记录视觉验收。simctl 录像显式选择 primary 显示屏，并要求实际生成文件。

用 MP4 creation_time 与 BEAR_MOTION_START/END 时间戳裁出动作片段；只裁剪与缩放分辨率，不加速。进程启动时间不等于首帧时间，不能直接用 recording.json 的 startedAt 计算裁剪偏移。媒体只使用合成或脱敏数据。

Widget 开发预览验证密度和展示规则；真实注册、Keychain 共享、系统着色、签名与刷新调度分别记录实际证据，不以布局预览替代。

## 0.2.0 设计预览 1 结果（2026-11-04）

来源 1f35bab：63 项包测试、14 项 UI 测试、Release 与 IPA 校验全 PASS，见 [原生 CI](https://github.com/RollandXD/qingsongxiong/actions/runs/41752016088)。已人工检查 iPhone 16 Pro / iOS 27.0 的首页浅深色、独立窗口与模型限制、余额组成、四种组件密度及原速影片，截图为 1206×2622。

用户确认 iPhone 16 Pro 覆盖更新、账户/读数保留、两类 Widget 和日常展开/刷新/返回手感均正常。Widget 系统着色外观未单独专项验收，透明度适配已实现。用户已免除手动真机无障碍模式测试，基本兼容由实现及上述自动审计负责。

实际令牌过期续期、每日自动化的真实定时/锁屏触发和跨七天稳定性仍 UNKNOWN，状态见 STATUS。历史构建证据可从 Git 与 Actions 回查。
