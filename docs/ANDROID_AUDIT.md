# Android 移植审计

审计日期：2026-11-15（Asia/Singapore）。只读来源 `C:\Dev\Codex\Android\Cost`，HEAD `9f461eb4efb25aa9e64bb7ec1cc9ba50d71f602b`。

## 结论与证据范围

- `docs/IMPLEMENTATION_PLAN.md` 状态总览确认 Phase 0...20（含 4.1、10.1）已完成；最近提交为分类删除，生产历史版本为 1.1.2 / code 4。这里引用已有验证记录，不代表重新构建 Android 或操作其设备。
- `CostDatabase.kt` 的 `@Database(version = 10)`、v1...v10 schema 导出、连续 Migration 与 10.json 一致。18 个实体中 17 个被 `TransferDatabase.LEDGER_TABLES` 导出，另一个是 restore_state。Room 内部元数据不算业务实体。
- Android tracked 工作区开始时无差异；有一份用户原有未跟踪 CSV。未打开、复制、移动、删除或提交该文件；未读取 local.properties、签名、配对、数据库或实际备份。
- 主审计涵盖产品/数据/架构/FX/备份/设计/阶段文档和业务关键源码；附加文档核对当前规则与最新完成结论，历史性能实验/个人迁移记录仅作背景，不把旧等待语句当当前门禁，也不复制个人财务明细。

源文件路径和 SHA-256 记录于 [manifest](reference/android-audit-manifest.json)，无个人数据的 schema 定义快照为 [android-schema-v10.json](reference/android-schema-v10.json)。后续 Android 变化需重做受影响审阅，不自动套用新 hash。

## 文档清单

| Android 文档 | 移植结论 |
|---|---|
| AGENTS.md | 保护 Android、精确金额、冻结快照、分阶段停止和客观自动化验收 |
| docs/PRODUCT_SPEC.md | 账单/主数据、模板、循环、统计/异常、多币种、Crypto、资金、数据携带 |
| docs/DATA_MODEL.md | Money/Decimal、业务日期、v10 实体/约束/索引、软删除与迁移 |
| docs/ARCHITECTURE.md | UDF/构造注入/Repository 边界，映射到 SwiftUI + Observation + GRDB |
| docs/FX_PROVIDER.md | Forex v2、dp=11、provider time+5分钟、有界重试；iOS 凭据改 Keychain |
| docs/BACKUP_FORMAT.md | COSTBK01、CSV 单引号/null、17 表、加密、限制、staging/outbox |
| docs/DESIGN_SYSTEM.md | 内容/结构/控制分层、可访问性、材质克制；Android 光学实现不复用 |
| docs/IMPLEMENTATION_PLAN.md | 最新 Phase 20 完成状态优先于各阶段历史待验收文字 |
| docs/CRYPTO_FOUNDATION.md | 独立 price 路径、用户启用、估值优先级、历史日期、Fiat 模板/循环边界 |
| docs/ACCOUNT_FUNDS_GUIDE.md | 未设置≠零、当前时点起算、本金与收益分离、完整备份 |
| docs/ACCOUNT_FUNDS_PROPOSAL.md | 方案已经批准，旧“待确认”为历史；不复制演示/个人金额 |
| docs/ACCOUNT_FUNDS_IMPLEMENTATION.md | v10 资金表、修订起点、事务/幂等、关联损益保护、备份 |
| docs/CATEGORY_DELETION.md | 已停用/无子项/全部引用保护、事务删除、schema 仍 v10 |
| docs/INPUT_METADATA_FIXES.md | 输入组合状态、显式图标 key、标签删除、重命名历史影响 |
| docs/CATEGORY_ICON_PREVIEW.md | 31 项已确认视觉为 Android 历史，不自动作为 iOS seed 或审美 PASS |
| docs/LIQUID_GLASS_REFINEMENT.md | 原型先验收、稳定内容、有限采样、系统交互；不移植 Shader |
| docs/RELEASE_HARDENING.md | 有界查询/图片、客观无障碍和性能、真实测试限制；数值不是 iOS 性能承诺 |
| docs/PHASE15_HANDOFF.md | 最终结果覆盖旧失败/未完成记录，Android 整体已 PASS |
| docs/PERSONAL_RELEASE.md | Android 个人签名与注入凭据不进入 iOS；不执行旧迁移流程 |

## 关键源码与交叉核对

路径均相对 Android 根目录，完整路径见 manifest：

- `core/model/.../money/Money.kt`、`DecimalRate.kt`、测试：正 magnitude、精确位数、溢出、rescale、38/18 和 HALF_EVEN。
- `core/data/.../database/CostDatabase.kt`、`CurrencySeedData.kt`、`AccountFundsMigration.kt`、schema 10.json：18 实体、约束、11 Fiat/4 Crypto metadata 和默认停用策略。
- `core/domain/.../transaction/ManageTransactionsUseCase.kt`、`fx/DefaultExchangeRateRepository.kt`、`core/data/.../fx/TwelveDataExchangeRateProvider.kt`：实际扣款/手工率优先、当天 latest/过去 historical、显式 fallback、冻结保存、原始数字解析。
- `core/domain/.../template/ManageQuickTemplatesUseCase.kt`、`core/data/.../database/dao/QuickTemplateDao.kt`：稳定四级排序、request key 和 usage 原子边界。
- `core/domain/.../recurring/RecurringScheduleCalculator.kt`、`ProcessRecurringTransactionsUseCase.kt` 及 `RecurringScheduleCalculatorTest.kt`：gap 保留分钟平移、overlap、月末/补记、唯一 occurrence 与冻结估值。
- `core/data/.../database/dao/CategoryDao.kt`、`TagDao.kt`、`TransactionDao.kt`：引用/归档/软删除、确认删除和原子性。
- `core/domain/.../funds/AccountFunds.kt`、`core/data/.../repository/RoomAccountFundsRepository.kt`：起点、精确派生、单快照两侧计算、转账损益保护。
- `core/domain/.../statistics/ObserveStatisticsUseCase.kt`、`anomaly/DetectAnomaliesUseCase.kt`、相关 DAO/Repository：冻结金额、区间/partial、样本有界、反馈语义。
- `core/data/.../backup/BackupEnvelope.kt`、`TransferDatabase.kt`、`LocalDataTransferRepository.kt`、`settings/BackupPreferences.kt`：CSV/header、17 表/七项设置、加密参数、预检/恢复 outbox。

## 原计划差异及处理

| 差异/风险 | 当前决定 | 后续门禁 |
|---|---|---|
| Phase 2 简化列表少 visual_assets/recurring_rule_tags/restore_state，资金/缓存表名不同 | 文档按实际 18 实体映射，保留 17 表备份契约 | Phase 2/8 |
| 账户资金与 Crypto 在原阶段清单描述较少 | 规格保留已有语义，分别归入 Phase 3/7 | 对应业务/精度/原子性测试 |
| gap“下一有效时间”可能被实现成 03:00 | 固定 Android 测试向量为 02:30→03:30 | Phase 5 DST 对照 |
| Foundation Decimal 有限中间精度，SQL 整数聚合可能溢出 | 检测并证明精确，不以 Double/REAL 回避 | Phase 2/6 |
| 完整备份不是裸 ZIP、Room/GRDB 元数据不同 | 保留 envelope/映射/staging，不宣称 live DB 可直换 | Phase 8 双向往返 |
| 仅 GRDB 依赖下的 WebP 编码/ZIP 能力未验证 | 记录具体实验与兼容性待办，不增加第三方库 | 图片实现前与 Phase 8 |
| 根 Package.swift 可能重复依赖来源 | 当前只以 project.yml packages 接入 SPM | Phase 1 解析验证 |
| macOS/Xcode 不在 Windows | 本阶段只做静态检查，Build/Test/IPA 明确未执行 | Phase 1 Actions |

## 保护与可复核性

本次不运行 Android Gradle、ADB、应用或导入导出，不更改 Android 仓库或数据。收尾使用只读 Git diff/status 与 manifest 文件 hash 复核。审计记录与 schema 仅含源码定义，禁止附带真实财务数据、设备标识或凭据。
