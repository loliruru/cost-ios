# Cost iOS 决策记录

日期：2026-11-15（Asia/Singapore）。已确定的技术约束来自原始用户计划；未解决项不代表本阶段可以新增依赖或改变业务。

## ADR-001 — Swift 6 / SwiftUI / GRDB

采用 Swift 6 Strict Concurrency、iOS 18+、Observation、MVVM + Domain/UseCase 和 GRDB/SQLite。替代方案 SwiftData 不适合本项目需要的显式 SQL 聚合、跨表事务、复杂约束和可审查迁移，因此不采用。GRDB 是唯一第三方应用依赖；网络、图表、通知、密钥优先使用系统框架。

GRDB 不会自动保证任意 SQL 的编译期正确性；仍需 schema、约束、查询与 Migration 测试。[GRDB 7.0.0 manifest](https://github.com/groue/GRDB.swift/blob/v7.0.0/Package.swift)声明 Swift tools 6.0 与 GRDB product，适合作为计划要求的依赖下界；`from: 7.0.0` 允许兼容 7.x 更新，不是精确版本锁定。Phase 1 记录实际解析版本与工具链；若需要可复现 pin，由工程唯一配置确定策略。

## ADR-002 — project.yml 为唯一工程与依赖来源

用 XcodeGen packages 定义 SPM GRDB，显式 App/Test targets 和两个 shared schemes；生成工程不入库。根 Package.swift 在原计划目录示意中出现，但不在 Phase 0 任务清单中；当前没有独立 Swift package target，故不增加第二份依赖配置或空壳包。应用仍通过 SPM 解析 GRDB，架构不变。将来确需独立 package 时先记录边界。

Info.plist 为手写元数据，project.yml 只引用，并从 source resources 排除，防止重复 CopyBundle。测试使用 hosted CostTests，TEST_HOST 为 iPhone App 的可执行路径。项目配置形式按 [XcodeGen Project Spec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)；Windows YAML 检查不能代替 macOS XcodeGen/xcodebuild。

## ADR-003 — Android 审计优先于简化清单

业务基线固定 Android HEAD `9f461eb4efb25aa9e64bb7ec1cc9ba50d71f602b`，Phase 20 / Room v10。实际 18 个实体，其中 17 表是完整备份账本，restore_state 是不导出的设置 outbox。保留 visual_assets、recurring_rule_tags、资金表及其真实 SQL 名字，不按原计划简化表名丢字段。

账户资金/删除保护/受管视觉并入 Phase 2 数据和 Phase 3 功能；Crypto 基础并入 Phase 7；完整兼容性在 Phase 8 验证。阶段顺序不变；Phase 0 仅冻结规格，Phase 2 已建立数据基础，完整业务仍在相应阶段。

DST gap 以 Android atZone 和现有测试的保留分钟平移为准：纽约 02:30→03:30，overlap 选较早 offset。该项澄清原计划“推进到下一有效时刻”的歧义，不另猜规则。历史文档中的“等待批准”以最新完成状态覆盖，不能把 Android 历史授权当作 iOS 后续阶段授权。

## ADR-004 — 精确数值需对齐 BigDecimal

Int64 minor units、0...18 scale、rate precision/scale 38/18、HALF_EVEN 与原始 token 解析已锁定。Foundation Decimal 的有限中间精度不能直接视为 Java BigDecimal 等价；Phase 2 用显式运算错误、字符串往返与边界向量验证，禁止静默中间舍入。若合法 Android 输入需要更宽中间运算，优先在项目内做精确十进制整数辅助，不能未经批准添加数值依赖或缩小产品规则。

SQLite 聚合同样需要溢出设计，不能将 SUM 溢出转为 REAL 或 TOTAL 来“修复”。Phase 2 已完成 Money/DecimalRate 精确运算门禁（见 ADR-010）；统计聚合在 Phase 6 实现。

## ADR-005 — 用户持有凭据与手动侧载

iOS API Key 由用户在 Settings 输入、存 Keychain。无 key 返回 notConfigured 且不联网。公开源码/unsigned IPA 不带 Android 个人开发 key、Apple 账号、证书或配对材料。SideStore 的首次安装、配对、Apple ID 登录、签名与定期刷新由用户执行；本阶段不登录或操作设备。

Windows 只写源码；macOS GitHub Actions 做工程生成、SPM、模拟器 Build/Test、unsigned device Archive 与 IPA 检查。Phase 1 才创建 workflow、确认远端及运行。SideStore 当前兼容性/签名限制以安装时实际官方说明验证，本阶段不把原计划中的时效信息当成已核验现状。

## ADR-006 — 备份双向兼容与平台限制（待验证）

冻结 Android COSTBK01/envelope v1、CSV 编码、17 表、七项设置、图片、AES-GCM/PBKDF2 参数和恢复 outbox 语义。GRDB live DB 不可直接宣称 Android Room 可打开：还涉及 user_version、Room identity、runtime triggers/indices 及 trusted staging 重放。Phase 8 需生成兼容的交换 SQLite 或显式映射，并用双向真实格式 fixture 验证。

仅 GRDB 依赖的约束下，ZIP 容器和 Android WebP 的 iOS 受管图片编码尚无验证结论。不能擅自新增 ZIP/WebP 库、仅改文件扩展名、丢弃图片或将 JSON 当作已有完整备份。Phase 3 处理图片前、Phase 8 编写导出前分别做系统能力与格式实验；若系统 API 不满足要求，完成具体兼容性证据和选项后再请求用户决定。Phase 0 不因此停下其他已授权基础工作。

## ADR-007 — 原生材质与部署版本分离

最低部署始终 iOS 18；iOS 26 原生 glassEffect 必须同时具备支持它的 SDK 和运行期保护，旧系统回退 ultraThinMaterial/高对比 surface。平台判断集中 DesignSystem。Android 的 Shader、调度与 Material 栈只供语义参考，不移植实现。

## ADR-008 — 阶段验证与诚实状态

Phase 0 只做审计、独立 Git、文档、最小工程、hosted test 源码及本地静态检查；当时未运行 Swift 编译/测试。不凭 YAML 成功声称 XcodeGen/IPA 通过。Phase 0/1 完成且构建链路通过前不写业务。每阶段提交后按用户原计划停止，由用户明确批准下一阶段。

## ADR-009 — Phase 1 已验证工具链与 target 预设

2026-11-15 用户授权 Phase 1 并指定 loliruru/cost-ios 公开远端。实际验证 Xcode 16.4 / Swift compiler 6.1.2、Swift 6 language mode、XcodeGen 2.46.0、iOS SDK 18.5、GRDB 7.12.0。完整 Build/Test/unsigned Archive/IPA 往返证据见 [Phase 1](PHASE1_BUILD.md)，不把此次实际解析版本误称为 7.x 范围已永久 pin。

XcodeGen target 预设会指定 AppIcon 和 iPhone/iPad 家族，project 级 family 不能覆盖 target 预设。因此在 App target 明确 iPhone-only，并将尚未创建的 AppIcon 名称清空；Phase 9 加图标资产后再显式选择。这个修复保留全部构建/测试门禁，不用占位商业素材或提前进行正式图标设计。

## ADR-010 — Phase 2 精确中间数与 iOS schema v1

2026-11-16 用户确认 Sideloadly 安装/启动成功并批准 Phase 2。Money/DecimalRate 的输入经 Foundation Decimal 与 canonical text 往返检查；乘除中间系数使用项目内十进制整数加/减/乘/长除，最后一次按余数和奇偶完成 HALF_EVEN，避免 Foundation Decimal 的有限精度先行舍入。没有 Float/Double 金额路径或新依赖；264 个 precision-120 Python Decimal 向量作为独立 oracle，包含大于 38 位中间乘积的合法结果。

首个 iOS 数据版本为 v1（v1_schema/v1_seed），保留 Android v10 的 18 实体、列/索引及运行时业务约束，附加严格 INTEGER/TEXT 类型 guard 和资金标量校验，不复制 Room 内部身份表。未知数据库、未来版本或未知迁移拒绝打开，永不使用 destructive migration。SQLite 金额汇率字段与 Domain 显式映射；异步 read/write、ValueObservation AsyncSequence 不引入 Combine。

Android 通用库只初始化币种，用户 iOS 计划还要求默认分类/账户。采用非个人最小 seed（其他支出、其他收入、默认账户），不复制个人初始化 ID 或真实金额；insert-ignore、迁移一次，不覆盖用户选择。完整业务/受管图片/备份兼容仍按后续 Phase 实现，不把表存在当作功能完成。

## ADR-011 — 用户批准最小 WebP 编码依赖

2026-11-17 的 iOS 18.5 Simulator 实验 [run 44097781406](https://github.com/loliruru/cost-ios/actions/runs/44097781406) 实际记录 ImageIO 支持 WebP 解码、不提供 WebP encoder；2×2 PNG 编码/回读通过，WebP destination 创建失败。37 项测试、Build/Archive/IPA 通过，实验只生成合成图，不截图或读取用户图片。

用户在本阶段明确选择“允许引入最小 WebP 编码依赖，保留原有交换格式”，例外放宽仅 GRDB 约束。采用 [SDWebImage/libwebp-Xcode 1.6.0](https://github.com/SDWebImage/libwebp-Xcode/tree/1.6.0)，以 project.yml exactVersion 固定；其 Package.swift 只有 libwebp C source target，没有其他 package 依赖，子模块指向 webmproject/libwebp。不引入 SDWebImage、Swift-WebP 或网络图片框架。BSD-3-Clause 许可证随 App 资源分发；CI 记录 wrapper 的实际 revision 并断言依赖树仅 GRDB + libwebp。

CI 实际解析证据：GRDB 7.12.0 / `92a554cd0d5e8d67cb18993c6054e73fe42c066c`；libwebp-Xcode 1.6.0 / `2b5256c29ff4e20f2a0d5ee863b62b1a22144434`，没有第三个 package。仅依赖解析成功不代表本阶段应用 Build/Test 通过。

编码仅在 Data 媒体适配层使用；ImageIO 检查尺寸、静态解码/方向校正与下采样，sRGB raw RGBA 去元数据、解除 alpha 预乘后调用 lossless WebP 编码。稳定 UUID 相对路径、kind/hash/processing version 去重；草稿 owner lease 与维护锁防止清理未提交文件；类别/账户引用在同一删除事务复核。完整备份容器与双向数据库交换仍属 Phase 8，本实验不代表完整备份已兼容。
