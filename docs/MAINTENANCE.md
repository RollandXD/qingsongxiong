# 更新、续签与恢复

## 覆盖更新

从项目 Release 下载 IPA 和 SHA256SUMS.txt，在电脑可用 `sha256sum -c SHA256SUMS.txt` 核对。CI 产物短期保留，已发布的预览包从 Release 获取。安装包没有 Apple 开发者签名，由自己的 SideStore 账户重新签名。

使用同一签名账户覆盖现有轻松熊，保留全部 Widget 扩展与共享权限。不要为排错先删除 App；卸载会丢失共享文件，钥匙串保留行为也不能代替可靠备份。更换签名账户可能改变共享权限，须重新验收。

更新或续签后检查：App 可打开、已有账户仍连接、组件时间及跳转正常。若安装提示权限或 Bundle ID 错误，保留错误文字、版本与来源提交，不提供 Apple 密码、配对资料或凭据。

## 手动续签

1. 在 SideStore 显示的到期时间之前操作，保持手机解锁并连接 Wi-Fi。
2. 临时切换至 LocalDevVPN，按 SideStore 官方流程在 My Apps 手动刷新 SideStore 和轻松熊。
3. 在 SideStore 确认到期时间实际更新，再恢复 Shadowrocket，并检查轻松熊网络读取。

本设备在 2026-11-03 已验证手动刷新、轻松熊共享数据保留和 Shadowrocket 恢复。不据此推断后台或跨七天有效。

## 自动续签的验收

先验证动作，再安排触发时间。手动连接 LocalDevVPN、打开一次 SideStore，然后在「快捷指令」中添加 SideStore 的 `Refresh All Apps` 动作并手动执行。成功标准是 SideStore 与轻松熊的到期时间实际更新，不能只看通知。

SideStore 0.7.0 的不同构建存在 [快捷指令参数错误 #1613](https://github.com/SideStore/SideStore/issues/1613) 和 [进程未驻留时登录状态错误 #1584](https://github.com/SideStore/SideStore/issues/1584)。这些是上游问题报告，不代表本设备必然失败。若发生，记录完整错误与构建号，保留可用的手动路径，不改装未知分支或撤销证书。

只有单次动作通过后，才在手机选择适合自己的触发条件，并逐步加入 LocalDevVPN 连接和 Shadowrocket 恢复。锁屏、网络断开、SideStore 被清理后的运行，以及真正超过七天的有效性，都需要实际观察；当前状态 UNKNOWN。

## 读取与授权恢复

- 网络失败或限流：保留带时间的旧读数，按提示等待后刷新，不把旧值当作当前额度。
- 提示打开 App 更新授权：打开主 App 刷新；组件不会并发轮换 refresh token。
- 授权已失效：在平台详情重新连接，在官方页面完成登录。
- 退出账户：取消正在进行的登录与请求，并清除该平台凭据和缓存。设置中的功能数据清除会逐一处理全部平台，并报告未能清除的情况。
- 重置时间已过：等待真实请求确认，不自行把额度当作恢复。

App 无法打开或 SideStore 已失效时，先按 [SideStore 当前安装文档](https://docs.sidestore.io/docs/installation/install) 恢复 SideStore，再用同一账户覆盖安装轻松熊；不要为恢复而删除尚有数据的轻松熊。恢复后重新检查共享权限与账户状态。这个完整到期恢复流程尚未实测。
