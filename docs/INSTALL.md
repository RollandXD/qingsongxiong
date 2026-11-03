# 免费安装与实机验收

目标设备：iOS 27.0.1 iPhone，日常使用 Shadowrocket。

## 1. 首次准备

按 [SideStore 官方前置条件](https://docs.sidestore.io/docs/installation/prerequisites) 与 [官方安装流程](https://docs.sidestore.io/docs/installation/install) 使用 Linux 版 iloader 的 **Install SideStore (Stable)** 入口。不要把 GitHub 的 latest 标签自动等同于稳定频道。

电脑首次通过数据线连接 iPhone，保持手机解锁，由用户在手机上选择信任、在工具中直接完成 Apple 登录与验证码。配对资料保留在本机工具私有目录，不上传本仓库或聊天。

Arch 需要官方 `usbmuxd` 包。首次安装后重新插入手机，让 udev 为该节点应用官方权限规则。

在自己的图形终端运行 `bash scripts/run_iloader.sh`。启动器校验并提取官方同版本原生包到忽略目录 `.local-tools/`，使用系统 GTK/Wayland 库，并仅为该进程启用 WebKitGTK 兼容设置。不会安装 Debian 包或修改全局图形配置。`bash scripts/run_iloader.sh --check` 可只验证文件及依赖。

这条路径用于处理 AppImage 显示窗口但无法点击等兼容问题；AppImageLauncher 可能自动移动原 AppImage，后续无需再运行旧路径。相关上游说明：[Tauri Linux 图形问题](https://v2.tauri.app/develop/debug/linux-graphics/)、[iloader AppImage 问题](https://github.com/nab138/iloader/issues/576)。

手机首次打开提示“不受信任的开发者”时，前往“设置 → 通用 → VPN 与设备管理”，选择用于签名的 Apple 账号并允许信任/重新启动。再按系统提示开启“设置 → 隐私与安全性 → 开发者模式”。

手机连接 Wi-Fi，按官方前置条件安装 [LocalDevVPN](https://apps.apple.com/app/localdevvpn/id6755608044)，点 Connect 并允许添加 VPN 配置。打开 SideStore，使用 iloader 中的同一个 Apple 账号登录；进入 My Apps，点击 SideStore 旁的剩余天数完成首次刷新。按官方流程，刷新成功可能暂时回到桌面，几秒后可重新打开。若 Shadowrocket 抢回 VPN 连接，续签期间暂停其自动连接，完成后恢复；网络配合仍以实机结果为准。

## 2. 安装验证包

1. 完成 SideStore 登录与首次刷新后，用手机 Safari 打开[验证版发布页](https://github.com/RollandXD/qingsongxiong/releases/tag/v0.1.0-verification.1)，下载 `QingSongXiong-needs-signing.ipa`；校验文件与来源提交见该页。也可从对应 Actions 产物解压获得 IPA 与 SHA256SUMS。
2. 在 SideStore 导入 IPA，**保留 Widget 扩展**，使用自己的免费账户重新签名。
3. 该 IPA 的临时 ad-hoc 签名只携带权限声明，没有 Apple 开发者签名；请以 SideStore 的签名/安装结果判断。
4. 若签名提示共享组或权限错误，记录错误文本并停止；不要移除 Widget 或共享权限来让安装“看起来成功”。

## 3. App 与组件对照

1. 打开轻松熊 → 设置 → 检查 App 与小组件共享能力。
2. 点“写入验证数据”，记录界面上的验证编号。
3. 主屏幕添加“轻松熊·总览”和“轻松熊·单平台”；后者选择任一平台。
4. 两类组件都必须出现相同编号，并显示“钥匙串可读”。只看 App 内通过不算组件通过。
5. 点击单平台组件，应进入对应的 Codex / Claude / DeepSeek 页面。
6. 再次写入后检查组件数据。系统刷新有调度延迟；界面时间应能区分旧读数。

## 4. 续签与网络

按照 SideStore 官方当前流程配置所需本地 VPN/连接。若与 Shadowrocket 不能同时启用，分别验证续签期间的临时切换，以及结束后恢复 Shadowrocket 的步骤。不得把常态关闭代理作为取数条件。

完成一次重新签名后，原验证编号与共享标记仍应存在；随后单独观察自动续签。跨七天结果只有实际经过后才记录。

## 5. 门槛状态

所有必需实机检查通过后再更新 `device-gate.json`。模拟器、CI 成功或 ad-hoc 签名检查不能替代设备验证。失败时报告具体环节、系统状态码和工具版本，不提交账户信息、配对文件或证书。

## SideStore 0.7.0 登录错误 -80045

2026-11-03 实机安装成功，但手机登录返回 `This action cannot be completed at this time. (-80045)`。上游 [问题 #1658](https://github.com/SideStore/SideStore/issues/1658) 有相同现象与社区临时方案：关闭 On-Device Anisette，选择内置 SideStore (New) 服务并关闭自动轮换，再重置 adi.pb（不保留 headers）后登录一次。该方案在本设备上的结果仍为 UNKNOWN。

按[该版本重置实现](https://github.com/SideStore/SideStore/blob/6032424a0e56c1c319762e786099bdd9186a238b/SideStore/Views/Settings/Advanced/UserCustomizations/UserCustomizationsView.swift#L531)说明，重置会退出 SideStore 中的 Apple 登录并清除 Anisette 验证缓存，保留活动签名证书。未确认登录恢复前不撤销证书、不导出配对资料、不替换未知来源的修改版；新错误应单独记录，不把错误码变化算作登录成功。
