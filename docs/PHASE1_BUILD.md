# Phase 1 — 端到端构建链路

状态：进行中；用户已批准，公开仓库为 [loliruru/cost-ios](https://github.com/loliruru/cost-ios)。本阶段只验证最小 App 与构建/测试/打包，不开发业务，不执行 SideStore/Apple ID 操作。

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

GitHub CLI 2.104.0 的官方 Windows 下载经发布 checksum 校验，工具只保存在忽略的 `.tools` 中。初始没有 GitHub 远端/CLI 登录，用户指定远端并选择 CLI 浏览器登录。登录开始时 TLS 握手超时，重试兼容客户端设置后取得授权码；不输出或提交令牌。最终登录、推送、Actions 与产物结果待下方记录。

Windows 查询/等待/下载入口为 `scripts/Read-CIBuild.ps1 -Mode Status|Watch|FailedLogs|Artifacts|Evidence|Download -RunId <ID>`。兼容设置只在子进程中禁用 MLKEM/HTTP2 客户端路径，不关闭 TLS 或证书验证、不改系统代理；脚本只读远端，下载仅写入忽略的 build/downloads。失败日志保存到 build/ci-logs，只打印过滤后的错误上下文。

首轮 [run 43721672166](https://github.com/loliruru/cost-ios/actions/runs/43721672166) 对应 `04e1209`，工程生成、SPM 和模拟器启动通过，模拟器 Build 因 XcodeGen 的默认 AppIcon 引用失败。Phase 0 没有图标资源，因此在 target 级明确清空该引用，正式图标仍在 Phase 9；同时 target 级设 iPhone-only，覆盖 XcodeGen 的 iPhone/iPad 默认设置，并增加静态回归检查。该失败轮不能计入通过。

首轮实际环境：Xcode 16.4 / 16F6、Swift compiler 6.1.2（App `-swift-version 6`）、iOS SDK 18.5、XcodeGen 2.46.0、runner image 20261104.0514.1；GRDB 7.12.0 / `92a554cd0d5e8d67cb18993c6054e73fe42c066c`。

## 最终验收记录

- [ ] 指定远端与公开状态核对，推送成功。
- [ ] XcodeGen、SPM、simulator Build 全通过。
- [ ] hosted Swift tests 通过，xcresult 已保存。
- [ ] unsigned device archive 成功。
- [ ] IPA 上传成功，下载后的内容/hash 与 run 证据一致。
- [ ] 日志与产物检查通过，独立提交并停止。

当前尚无可宣称通过的远端 run。完成后在这里记录 run URL、源码 SHA、工具链/GRDB 版本、测试数量、IPA 大小与 SHA-256 及实际限制。Phase 2 需用户另行批准；本阶段不要求主观视觉验收。最后的真机 SideStore 安装由用户手动验证。
