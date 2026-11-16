# Phase 1 — 端到端构建链路

状态：完成（2026-11-15，Asia/Singapore）；公开仓库为 [loliruru/cost-ios](https://github.com/loliruru/cost-ios)。本阶段只验证最小 App 与构建/测试/打包，不开发业务，不执行 SideStore/Apple ID 操作。

## 配置与行为

- `.github/workflows/build.yml` 在 main push、PR 或手动触发时运行，macos-15、30 分钟上限，token 只读，checkout 不持久化凭据，不使用用户 secrets。
- 选择 `/Applications/Xcode_16.4.app/Contents/Developer`；Swift 6 language mode、strict concurrency、iOS 18.0 部署不变。该工具链选择依据 [runner 官方镜像清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)，执行时必须记录实际版本，若路径已移除则明确失败。
- XcodeGen 是工程来源；GRDB 由 SPM 的 7.x 范围解析。复制本次 Package.resolved 到证据 artifact，记录实际 version/revision，不把 from 下界当作已锁定版本。
- 通过 simctl 实际库存，选最低 iOS 18、且不高于当前 simulator SDK 的可用 iPhone；同运行时优先 iPhone 16。写入 udid/runtime/SDK/destination 并启动等待 ready，避免硬编码一个已不存在的模拟器名称。
- 分别 simulator build、hosted Swift Testing、unsigned iphoneos archive。测试覆盖 App host 身份/版本及 GRDB/SQLite 实际链接与 SELECT 1；不创建业务数据库或做 Phase 2 实现。
- ditto 保留可执行权限生成 `Payload/Cost.app/`，跨平台脚本校验 ZIP、Info.plist、arm64 Mach-O、iOS device build platform、unsigned 和权限。输出 SHA-256 与 JSON 证据后上传 `Cost-unsigned-ipa`。
- `Cost-build-evidence-<attempt>` 保存选定的构建日志、xcresult、SPM pin、模拟器和 IPA 报告；失败时也保留已产生证据，不上传整个 runner 目录或任何个人配置。

Actions 使用当前官方 [checkout](https://github.com/actions/checkout) / [upload-artifact](https://github.com/actions/upload-artifact) v7。仓库中无 Apple 账户、签名、配对或 Twelve Data key；IPA 仍需用户侧载工具签名，unsigned 不是已安装验证。

## 本地验证与连接

已完成：Phase 0 静态检查；IPA 校验器 6 项测试，覆盖正确包、arm64 simulator 混淆、错误 Payload 名称、丢失执行权限、已签名 Mach-O、路径穿越。workflow YAML/Bash 语法随本地检查验证。

GitHub CLI 2.104.0 的官方 Windows 下载经发布 checksum 校验，工具只保存在忽略的 `.tools` 中。初始没有 GitHub 远端/CLI 登录，用户指定远端并选择 CLI 浏览器登录。登录开始时 TLS 握手超时，重试兼容客户端设置后登录 loliruru 成功，workflow 写入 scope 已核对；不输出或提交令牌。远端初始公开且为空，已推送 main，无强推或覆盖既有历史。

Windows 查询/等待/下载入口为 `scripts/Read-CIBuild.ps1 -Mode List|Status|Watch|FailedLogs|Artifacts|Evidence|Download -RunId <ID>`（List 不需 RunId）。兼容设置只在子进程中禁用 MLKEM/HTTP2 客户端路径，不关闭 TLS 或证书验证、不改系统代理；脚本只读远端，下载仅写入忽略的 build/downloads。失败日志保存到 build/ci-logs，只打印过滤后的错误上下文。

首轮 [run 43721672166](https://github.com/loliruru/cost-ios/actions/runs/43721672166) 对应 `04e1209`，工程生成、SPM 和模拟器启动通过，模拟器 Build 因 XcodeGen 的默认 AppIcon 引用失败。Phase 0 没有图标资源，因此在 target 级明确清空该引用，正式图标仍在 Phase 9；同时 target 级设 iPhone-only，覆盖 XcodeGen 的 iPhone/iPad 默认设置，并增加静态回归检查。该失败轮不能计入通过。

首轮实际环境：Xcode 16.4 / 16F6、Swift compiler 6.1.2（App `-swift-version 6`）、iOS SDK 18.5、XcodeGen 2.46.0、runner image 20261104.0514.1；GRDB 7.12.0 / `92a554cd0d5e8d67cb18993c6054e73fe42c066c`。

## 最终验收记录

- [x] 指定远端与公开状态核对，推送成功。
- [x] XcodeGen、SPM、simulator Build 全通过。
- [x] hosted Swift tests 通过，xcresult 已保存。
- [x] unsigned device archive 成功。
- [x] IPA 上传成功，下载后的内容/hash 与 run 证据一致。
- [x] 日志与产物检查通过，以本阶段收尾提交交付并停止。

通过轮次为 [run 43722646105](https://github.com/loliruru/cost-ios/actions/runs/43722646105)，源码 SHA `86f60b6015ca379f60ee6bebb014f7ac40c1ebb9`，全部步骤成功，job 用时 5m51s。前述工具链/GRDB 版本保持一致；实际选择 iPhone 16 / iOS 18.5。Swift Testing 的 applicationHostLoads 与 sqliteDependencyExecutes 共 **2 项通过、0 失败**；日志中的 XCTest “Executed 0 tests”是空 XCTest suite，不能误读为 Swift Testing 没运行。

[Cost-unsigned-ipa artifact](https://github.com/loliruru/cost-ios/actions/runs/43722646105/artifacts/14165910336) 含 IPA、SHA256 和校验 JSON。IPA 为 1,283,261 bytes，`Payload/Cost.app/`、com.personal.cost、版本 0.1.0 / build 1、iOS 18.0+、arm64 device executable、无签名/配对或 provisioning 材料。文件 SHA-256：

```text
73f17a8afcbdf69595ecd3d192a6e052488c5cdae7654521a66a586df157d74b
```

下载后由 Windows `verify_ipa.py` 独立解析并与远端 JSON、sha256 文件比对，三者一致。artifact ZIP 的 GitHub digest 与内层 IPA hash 是不同对象：artifact digest 为 `1d6ebab9c3fdbd20da797645bce5d408277ebfc40d68708736e93f98a15350eb`。构建证据 artifact ID 14165202128，保留 toolchain/Package.resolved/日志/xcresult；本地副本在忽略的 `build/downloads/43722646105/`。

日志敏感凭据模式检查通过，没有 Swift 编译错误或警告；Xcode 的 AppIntents metadata 工具因本阶段不依赖 AppIntents.framework 发出 4 条 extraction skipped 提示，不宣称全工具链零 warning，也不为压制提示添加无用框架。该提示未影响 Build/Test/Archive；不是用户功能或凭据问题。

本阶段收尾提交为 `ci(phase-1): end-to-end build pipeline verified`，只更新验收文档和只读监控入口；应用源码、测试、工程、workflow 与通过轮次一致。收尾 push 会再次触发相同 CI，最终结果以 main 最新 run 为准。

2026-11-16 用户报告已通过 Sideloadly 签名安装，打开居中显示 Cost、没有其他元素，与最小验证版一致，手动安装/启动最后一环完成。该结果来自用户确认，不是代理自动安装；正式 App 图标仍待 Phase 9，无主观视觉验收项。用户随后明确批准 Phase 2。
