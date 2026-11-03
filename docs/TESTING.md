# 验证方式

## Linux

```sh
python3 scripts/check_architecture.py
python3 scripts/check_repository.py
bash -n scripts/install_xcodegen.sh scripts/apple_build.sh
```

Linux 没有 Xcode，不能把这些静态检查当作 iOS 编译通过。

## macOS / CI

固定 Xcode 27.1、XcodeGen 2.46.0，使用 Swift 6 语言模式：

- `swift test --package-path Packages/BearKit --parallel`：路由隔离、领域准确性、Decimal、共享快照、并发写入与版本拒绝。
- 原生 UI 测试：首页导航、深色安装验证页面、Debug 功能注册与独立计数状态。
- `--ui-testing` 仅在 Debug 模拟器构建中使用易失凭据容器，避免未签名模拟器的 Keychain 权限影响页面测试；真机始终使用共享 Keychain。安全输入截图只截空字段。
- Release 真机目标构建，产出待重签 IPA；构建不需要真实账户、证书或 Apple 登录。
- UI 截图由 xcresult 导出到 Actions 产物；人工检查后才记录视觉验收。
- 数据层覆盖多币种 Decimal 精度、缺失/无效窗口、模型窗口、限流、请求合并、退出迟到响应与令牌轮换。Widget 测试验证不轮换 token、不写共享快照、退出后拒绝旧结果。

小组件注册、真实 Keychain 共享、签名有效期、Shadowrocket 与续签连接配合必须按 INSTALL 在真机验证。

## 后续阶段

实机门槛通过后再添加真实供应商响应夹具、授权/轮换/限流/退出竞态测试。夹具不得带真实 token、账号邮箱或账户标识。
