# Cost iOS

独立的 iOS 原生 Cost 记账应用。开发环境为 Windows；Swift 6 / SwiftUI / iOS 18+，数据库使用 GRDB，工程由 XcodeGen 生成。Android 参考项目只读。

阶段状态与已验证 IPA 见 [实施计划](docs/IMPLEMENTATION_PLAN.md)。原生材质和真机试用步骤见 [Phase 9](docs/PHASE9_NATIVE_APPEARANCE.md)。

先读 [协作规则](AGENTS.md)、[实施计划](docs/IMPLEMENTATION_PLAN.md)、[审计报告](docs/ANDROID_AUDIT.md)和[技术决策](docs/DECISIONS.md)。原始计划保存在 [cost-ios-codex-plan.md](cost-ios-codex-plan.md)。

本地检查（Python 3.12+；PyYAML 仅为开发检查工具，不进入 App）：

```powershell
python -m pip install --target .tools/python -r scripts/requirements-dev.txt
python scripts/verify_foundation.py
python scripts/verify_phase2.py
git diff --check
```

若 Python 不在 PATH，可用 Codex `load_workspace_dependencies` 返回的 Python 可执行文件；不要提交本机绝对运行时路径。

CI 在 main push、指向 main 的 pull request 或手动触发时执行。macOS 使用 Xcode 26.3，安装 iOS 26 和 iOS 18 模拟器运行时。 [Build Cost iOS](https://github.com/loliruru/cost-ios/actions/workflows/build.yml)

```sh
xcodegen generate
xcodebuild -resolvePackageDependencies -project Cost.xcodeproj -scheme Cost
xcodebuild build -project Cost.xcodeproj -scheme Cost -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
python3 scripts/select_simulator.py --runtime-major 26
# 使用 build/simulator.json 中的 destination 运行测试
xcodebuild test -project Cost.xcodeproj -scheme CostTests -destination '<已选择的 destination>' CODE_SIGNING_ALLOWED=NO
```

`project.yml` 同时定义 App、hosted tests、shared schemes 和 SPM GRDB 依赖。生成项目、构建产物、账本、凭据、签名及配对材料均不得入库。SideStore 安装和 Apple 账户操作由用户完成。
