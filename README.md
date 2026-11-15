# Cost iOS

独立的 iOS 原生 Cost 记账应用。开发环境为 Windows；Swift 6 / SwiftUI / iOS 18+，数据库使用 GRDB，工程由 XcodeGen 生成。Android 参考项目只读。

当前只完成 **Phase 0 项目骨架与 Android 审计**。尚无记账功能、CI 构建结果或可安装 IPA；下一阶段是验证 GitHub Actions/macOS 构建链路。

先读 [协作规则](AGENTS.md)、[实施计划](docs/IMPLEMENTATION_PLAN.md)、[审计报告](docs/ANDROID_AUDIT.md)和[技术决策](docs/DECISIONS.md)。原始计划保存在 [cost-ios-codex-plan.md](cost-ios-codex-plan.md)。

本地检查（Python 3.12+；PyYAML 仅为开发检查工具，不进入 App）：

```powershell
python -m pip install --target .tools/python -r scripts/requirements-dev.txt
python scripts/verify_foundation.py
git diff --check
```

若 Python 不在 PATH，可用 Codex `load_workspace_dependencies` 返回的 Python 可执行文件；不要提交本机绝对运行时路径。

macOS 验证入口（Phase 1 执行，以下不是已通过结果）：

```sh
xcodegen generate
xcodebuild -resolvePackageDependencies -project Cost.xcodeproj -scheme Cost
xcodebuild build -project Cost.xcodeproj -scheme Cost -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Cost.xcodeproj -scheme CostTests -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

`project.yml` 同时定义 App、hosted tests、shared schemes 和 SPM GRDB 依赖。生成项目、构建产物、账本、凭据、签名及配对材料均不得入库。SideStore 安装和 Apple 账户操作由用户完成。
