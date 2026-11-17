# Cost iOS 实施计划

日期：2026-11-15（Asia/Singapore）。执行顺序来自[原始计划](../cost-ios-codex-plan.md)，一次只做一个获批 Phase，完成提交后停止。Android 的完成状态不等于 iOS 完成。

## 状态总览

| Phase | 目标 | 状态 |
|---:|---|---|
| 0 | 项目初始化与 Android 审计 | 完成（2026-11-15，随本阶段首次提交交付） |
| 1 | Windows→GitHub→macOS→IPA 构建链路 | 完成（2026-11-15，Actions/IPA 下载复核通过） |
| 2 | 精确数值、GRDB、schema、Migration、Repository | 完成（2026-11-16，36 项 Swift tests / Build / IPA 通过） |
| 3 | 账单/分类/账户/标签/受管视觉/可选账户资金 | 进行中（2026-11-17 获批；实现/验证中，图片格式门禁与真机验收待完成） |
| 4 | 快捷模板 | 未开始 |
| 5 | 周期记账 | 未开始 |
| 6 | 统计与异常 | 未开始 |
| 7 | Fiat FX 与 Crypto 基础 | 未开始 |
| 8 | CSV、完整备份与跨平台恢复 | 未开始 |
| 9 | 原生 Glass 与 UI 精修 | 未开始 |
| 10 | 全量测试与稳定性 | 未开始 |

## 共用交付门禁

实现 → 当前阶段检查/测试 → 检查 diff/敏感文件 → 更新状态/决策 → 仅暂存本阶段并创建清晰提交 → 简短汇报 → **停止并等待用户批准下一阶段**。不把未运行测试、默认跳过的真实服务契约或 Android 历史结果标为 iOS 通过。

Phase 0/1 优先。端到端链路未通过，不开发业务。其后各阶段需 macOS Build + 对应 Swift Testing/XCTest；迁移/事务/快照有数据库测试，UI 有客观语义及状态验证；仅美感/材质/动效观感由用户主观真机验收。

## Phase 0 — 项目初始化与 Android 审计

范围：审阅 Android 文档与关键代码、确认 Phase 20/schema v10，建立独立 Git、忽略规则、AGENTS、六份长期文档与额外审计、XcodeGen 配置、空 App/Container、资源/Info.plist、hosted test 源码及完整目录。

验收清单：

- [x] Android 只读审计和 schema/source hash 基线；差异及待验证边界记录。
- [x] AGENTS 与 PRODUCT_SPEC/ARCHITECTURE/DATA_MODEL/DESIGN_SYSTEM/IMPLEMENTATION_PLAN/DECISIONS 齐全。
- [x] 主 App、Core、Feature、Resources、CostTests 目录及最小源文件齐全。
- [x] .gitignore 覆盖构建产物、数据库/导出、凭据、签名与配对。
- [x] YAML/Plist/资源 JSON、相对链接、忽略规则及审计基线检查通过。
- [x] Git 初始化；本阶段以首次提交 `docs(phase-0): iOS project foundation and Android audit` 交付，实际提交标识以 Git 日志为准。

实际验证（2026-11-15）：`scripts/verify_foundation.py --android-root <Android参考目录>` 全部通过：YAML 安全解析及重复键检查、App/Test target 与 shared schemes、Info.plist/资源 JSON、必需文件/目录、文档本地链接、35 个敏感/生成文件忽略探针及仓库候选文件检查。Android 19 份文档（AGENTS + docs 下 18 份）、33 份关键源码/测试、v10 schema 共 53 个 SHA-256 与源文件一致；HEAD 与 tracked diff 未变，原有未跟踪 CSV 保留且未打开。

本地工具检查只发现 Git/Node；Python 由 Codex bundled runtime 提供，PyYAML 6.0.3 仅安装在忽略的 `.tools/python`。首轮忽略探针发现 Windows stdin 的 CRLF 会被 Git 当作路径字符，检查脚本改用 NUL 分隔后重新验证全部通过；不是绕过忽略规则。暂存审查另发现 Windows 的 `backup/` 模式误忽略 Feature/Backup，改为根目录 `/backup/`，并增加每个计划目录必须有可跟踪内容的检查，保证 clone 后结构完整。schema 快照规范为 LF，原始 Android 文件与规范快照分别保存摘要，避免 checkout 行尾差异。

无 Mac/Xcode/Swift 工具链，因此本阶段不运行 Swift 编译、Swift Testing、XcodeGen 生成、IPA 或真机测试；这些属于 Phase 1。Phase 0 无主观视觉验收项。Git diff/staged diff 的空白检查与最终状态在提交时核对。本阶段完成后停止，**尚未开始 Phase 1**。

## Phase 1 — 端到端构建链路验证

用户已明确批准执行本阶段，并指定公开远端 `https://github.com/loliruru/cost-ios.git`。创建 build.yml；把空入口改为 Text("Cost")；确认公开远端、推送；macos-15 安装 XcodeGen、记录实际 Xcode/SDK/GRDB 版本、解析 SPM、Simulator Build、CostTests hosted Test、unsigned iphoneos Archive、打包并上传 IPA。runner 与可用模拟器须在执行时核验，不能盲猜固定运行时。

验收：Actions 全 green；有效 artifact、`Payload/Cost.app/`、设备架构/Info.plist/可执行文件正确；构建日志不含敏感信息。失败按真实日志修复重跑。SideStore/Sideloadly 最后一环由用户手动完成。完成提交 `ci(phase-1): end-to-end build pipeline verified` 后停止。

实际结果（2026-11-15）：[run 43722646105](https://github.com/loliruru/cost-ios/actions/runs/43722646105) 全部 green；XcodeGen/SPM、Simulator Build、2 项 hosted Swift tests、unsigned device Archive、IPA 打包/校验/上传全部通过。Windows 下载后复核 Payload、Info.plist、arm64/iOS device Mach-O、未签名状态、可执行权限及 SHA-256，与 CI JSON/校验文件一致。IPA 1,283,261 bytes，版本 0.1.0 / build 1。工具链、GRDB revision、失败首轮根因、hash、artifact 链接和限制见 [Phase 1 构建链路](PHASE1_BUILD.md)。

本地静态检查（含 11 段 Bash 语法、35 项忽略探针及 Android 53 文件 hash）和 6 项 IPA 校验器测试通过。保留 xcresult 与过滤后日志；没有用户密钥或 Apple 账户注入。以 `ci(phase-1): end-to-end build pipeline verified` 独立收尾提交。此阶段无主观视觉验收项。2026-11-16 用户报告通过 Sideloadly 签名安装成功，打开居中显示 Cost、无其他元素，与最小验证版一致，手动安装/启动最后一环完成；随后明确批准 Phase 2。

## Phase 2 — 数据层基础

Money/DecimalRate、GRDB 初始化/WAL/显式 Migration、Android v10 语义的 18 实体、seed、Domain 协议和 Repository 基础 CRUD。保留视觉、规则标签、恢复 outbox 和资金表，不按简化清单漏表。iOS migration version 独立于 Room；详见 DATA_MODEL。

验收：0...18 scale、严格输入位数、Int64 极值/溢出、精确 rescale、HALF_EVEN、38/18 与中间精度向量、原始 JSON 数字不经 Double；seed 不覆盖用户设置；CRUD/FK/唯一键/事务回滚/软删除/快照/Migration 测试；Actions Build+Test。记录 ZIP/WebP 与跨 ORM 格式待办，不在此实现业务页面。

实际结果（2026-11-16）：[run 43886521271](https://github.com/loliruru/cost-ios/actions/runs/43886521271) 全 green，验证代码提交为 `05ebe9461e78308485c745009d199ec8f5d9ca55`。36 项 hosted Swift tests（含 264 组独立精度向量）、Simulator Build、unsigned device Archive/IPA 均通过；下载后的 Payload/架构/版本/未签名状态和 SHA-256 与 CI 一致。18 表、62 guard、seed/类型/FK/层边界及 Android 53 文件只读基线检查通过。首次测试编译的 throws 标注问题已修复并重跑。实现、产物、限制见 [Phase 2 数据基础](PHASE2_DATA_FOUNDATION.md)。本阶段无主观视觉验收项，完成后停止，Phase 3 未开始。

## Phase 3 — 核心账单与基础资料

2026-11-17 用户明确批准开始。实现与未完成门禁见 [Phase 3 记录](PHASE3_CORE_LEDGER.md)。在本阶段全部验证和真机视觉验收通过前不标完成；不得进入 Phase 4。

分类两级/排序/停用与受引用删除保护；账户默认/停用；标签规范化复用/确认删除；受管 emoji/图片/背景与引用清理；账单列表/搜索/筛选、快速录入、详情/编辑、删除/撤销、原生主 TabView。先实现本币与完整 identity 快照，联网估值仍待 Phase 7；不可写不完整外币账单。

包含 Android 已有可选账户资金：revision 起点、未设置≠零、可用金额/成本、同币本金转账、关联损益原子保存/编辑/撤销/恢复与冲突/幂等保护。实现图片前先验证 ADR-006 的系统编码/交换方案。

验收：全部 CRUD 主路径、资金计算/事务/守恒/旧账不追扣/受管损益保护、引用感知媒体生命周期、输入/IME/恢复/VoiceOver/Dynamic Type。Actions Build+Test；用户真机布局与风格验收后提交停止。

## Phase 4 — 快捷模板

Fiat 模板 CRUD、排序、停用/恢复/确认删除、一键防重和编辑后保存；模板不保存当次估值，引用停用时明确失败。撤销一键记账原子回退 transaction/usage/lastUsed。网络 FX 依赖 Phase 7，当前没有完整估值则保留草稿，不能伪称外币自动保存可用。

验收：并发 request key 防重、usage 只增一次、撤销/失败回滚、稳定四级排序、删除保留历史交易、编辑不回写模板；Build+Test 后独立提交停止。

## Phase 5 — 周期记账

规则 CRUD、六种频率、月末、时区、起止、暂停/恢复/补记策略；occurrence/execution/cursor 原子幂等；前台补处理、BGAppRefreshTask 和本地提醒。后台不承诺准点，规则/模板独立。网络历史/latest 分支在 Phase 7 完成前用固定 Provider 验证，生产无估值则明确待处理。

验收：gap/overlap 的 Android 固定向量、跨月/年/闰年、两种补记、取消/重启/并发生成一次、失败重试/跳过、删除保留已有账单；前台补执行与系统任务验证；Build+Test 后提交停止。

## Phase 6 — 统计与异常

冻结金额 SQL 聚合（防整数溢出）、7/30/90/自定义、自然日补零与均值、分类组成/趋势/收支、环比/同比/partial、混合历史本位币分组。Swift Charts 原生图表与可读摘要；本地有界稳健异常检测、开关/灵敏度与持久反馈。

验收：零消费日、零基准、partial/闰年边界、不同 scale/base、缓存刷新不影响历史；样本不足/过多、排除循环、±20% 正常反馈；有界查询/索引与可访问摘要；Build+Test 后提交停止。

## Phase 7 — 多币种与 Provider

Keychain 设置、Twelve Data Forex v2 `/exchange_rate` dp=11/timezone=UTC、原始 token 精确解析、provider time+5 分钟 freshness、并发去重、typed failure/有界重试、当天 latest/过去 historical/确认 fallback、保存冻结快照。

Crypto 显式启用、独立 `/quote`/price 类型与缓存、实际扣款/单价/市场优先级、历史日期与 stale 确认；本位币/模板/循环仍限 Fiat，无仓位。打通之前阶段的外币模板/周期分支。

验收：精度端到端、TTL 边界、原始数字/429/5xx/取消/无 key/离线、重复请求、历史不可变、Keychain/日志/导出隔离；固定测试优先，真实契约只在安全配置且显式选择时运行；Build+Test 后提交停止。

## Phase 8 — 备份与跨平台兼容

Cost CSV 固定编码及 context_json、冲突原子合并；COSTBK01 ZIP/encryption、17 表/七项设置/图片/manifest、有界 staging、预检确认替换、trusted schema 重放、设置 outbox 和崩溃恢复。使用系统 Files 选择器；不实现任意银行 CSV 或另创不兼容 JSON 格式。

先完成 ZIP/WebP/Room-GRDB 元数据与密码 Unicode 的具体实验，依赖约束无法满足时凭证据请求决定，禁止悄改格式或丢图片。验收 Android→iOS 与 iOS→Android fixture 往返、旧版本迁移、密码/损坏/ZIP 穿越/限额/中断/原子性、资金/规则幂等/图片完整和大数据量；不得为了验收修改 Android 生产仓库或真实账本。

## Phase 9 — Glass 与 UI 精修

支持 iOS 26 SDK 的工具链、原生 glassEffect 与 iOS 18 fallback、Light/Dark、Dynamic Type、SF Symbols、App 图标、触觉、动效、VoiceOver 全路径。材质只用于控制层，先有界假数据样例再接业务。

验收：自动化可访问性/布局/降低透明度与动画测试；用户真机材质/美感/动效 PASS；Build+Test 后提交停止。

## Phase 10 — 完整验证与稳定性

补齐有价值的核心/Repository/UI 测试、全部迁移与备份往返、至少 1000 笔性能和长时间任务、清理警告与最终发行检查。自动 Build+Test 全 green、真机 24 小时无崩溃、数据完整性对照；没有执行的长时间观察不能提前标 PASS。完成后独立提交并报告剩余限制。
