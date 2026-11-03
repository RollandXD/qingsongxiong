# 免费安装与实机验收

目标设备：用户的 iOS 27.0.1 iPhone，日常使用 Shadowrocket，尚未安装 SideStore。

## 1. 首次准备

按 [SideStore 官方前置条件](https://docs.sidestore.io/docs/installation/prerequisites) 与 [官方安装流程](https://docs.sidestore.io/docs/installation/install) 使用 Linux 版 iloader 的 **Install SideStore (Stable)** 入口。不要把 GitHub 的 latest 标签自动等同于稳定频道。

电脑首次通过数据线连接 iPhone，保持手机解锁，由用户在手机上选择信任、在工具中直接完成 Apple 登录与验证码。配对资料保留在本机工具私有目录，不上传本仓库或聊天。

Arch 需要官方 `usbmuxd` 包。首次安装后重新插入手机，让 udev 为该节点应用官方权限规则。安装器可用 `python3 scripts/download_iloader.py` 下载到忽略目录 `.local-tools/`，脚本会核验官方发布包的 SHA-256，不运行登录流程。

## 2. 安装验证包

1. 在 GitHub Actions 的成功构建中下载 `QingSongXiong-verification-…` 产物，解压得到 `QingSongXiong-needs-signing.ipa` 与 SHA256SUMS。
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
