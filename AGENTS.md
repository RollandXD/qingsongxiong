# 轻松熊

- 用中文交流。产品名「轻松熊」，标识 `QingSongXiong`，Swift 6，最低 iOS 27.0。
- 修改前读 `docs/STATUS.md` 与 `docs/ARCHITECTURE.md`。手机免费签名与共享能力未通过前，不实现真实厂商登录、取数及正式业务界面。
- 领域模块只能依赖 Foundation 和 BearFoundation；展示层不直接请求网络或访问 Keychain。AppShell 是依赖装配与功能注册入口。
- 新功能拥有自己的领域、数据、展示边界；共享层不接收单个功能的业务模型。
- 不提交密码、token、API Key、配对文件、签名证书、设备标识或真实账户截图。CI 只构建和测试演示数据。
- Git 操作前读 `~/.agents/skills/git-workflow/SKILL.md`，保留用户现场，精确暂存，不添加 AI 署名。
- 只用公开仓库的标准 GitHub 构建机，不启用付费 runner 或开发者服务。
- 运行 `python3 scripts/check_architecture.py`、Swift 包测试和原生构建；没有实际执行的验收写 UNKNOWN。
