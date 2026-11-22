# Cost iOS 数据模型与 Android v10 映射

状态：Phase 2 数据基础已完成并通过 macOS Build/Test；iOS schema v1 独立于 Android Room v10。实际结果见 [Phase 2](PHASE2_DATA_FOUNDATION.md)。来源：Android `CostDatabase.kt`、导出 `10.json`、Domain/DAO/备份代码与测试；快照见 [schema](reference/android-schema-v10.json)，文件摘要见[审计 manifest](reference/android-audit-manifest.json)。Room identity hash 为 `3be6bf322210390fb222f35c65d4a343`；iOS 不冒充此 Room identity。

Phase 3 在原 v1 表上增加账单搜索、账户资金和受管视觉业务 Repository，没有修改冻结 schema/seed 或注册新 Migration。实际验证状态见 [Phase 3](PHASE3_CORE_LEDGER.md)。资金总额以项目内精确有符号十进制派生，可超过 Int64；媒体 processing_version=1，mime 为 image/webp，UUID 私有相对路径，原图仅短暂存在于私有临时 staging。

## 不变量与精确数值

Money = `minorUnits: Int64`、`currencyCode: String`、`scale: Int`。交易金额为正数，方向由 income/expense 表达；scale 0...18。字符串输入只接受普通非负十进制数字形式（首尾空白可去掉），交易必须 >0；拒绝负号、指数、超出币种 scale 的小数与 Int64 溢出，不静默截断或经过 Double。即使额外小数位全为零也按 Android MoneyParser 的位数校验拒绝。不同币种不可相加，不同 scale 必须先显式精确 rescale；缩小 scale 需要舍入则失败，放大溢出则失败。

DecimalRate/price 为正的规范普通十进制文本，去前导/尾随零，precision ≤38、scale ≤18。存 TEXT，不存 SQLite REAL。Provider 原始 JSON number 以 token 文本读取，不经过 JSONDecoder Double 或先转换 NSNumber.doubleValue。Foundation Decimal 的可表示性、中间精度、溢出/下溢必须检查；输入 38 位合法不意味着乘积 38 位内。Phase 2 用 Android 边界向量验证最终值及错误，禁止中间静默舍入。

`rateBasePerOriginal = 1 original → N base`；最终 `convertedBaseMajor = originalMajor × rate`，按本位币 scale HALF_EVEN（bankers）舍入后精确转 Int64，溢出或舍入到零失败。实际扣款金额直接冻结；审计 rate 以 actual/original、18 位小数 HALF_EVEN 反推，不能再换算覆盖实际金额。同币种保存 rate=1/provider=IDENTITY/method=IDENTITY，金额与 scale 一致，Provider 时间为空。

资金起点金额可为零（开启时非负，关闭时 null）；本金可零、损益可带符号、到账不得负。这些字段不用只允许正交易金额的 Money 强行表达。资金及统计多行累加用精确十进制/受检查整数，SQLite `SUM` 的 Int64 溢出必须处理，不允许用 REAL、TOTAL 或 Double。不同本位币/scale 不直接累加。

## ID、日期与 DST

稳定字符串 ID，可注入生成器。created/updated/provider/fetched 时间为 UTC epoch milliseconds Int64。发生时间同时存 instant、IANA occurred_zone_id、冻结 occurred_local_epoch_day；编辑时间/时区同事务更新业务日期。

报表区间 `[startEpochDay, endEpochDayExclusive)`，不依赖设备当前时区重分历史日。周期保存 zone、本地分钟、开始/结束日与月末策略。**源码/测试优先于“下一有效时刻”的笼统表述**：Android `LocalDateTime.atZone` 在 gap 按缺口长度向前平移，保留分钟；纽约 2026-03-08 02:30 → 03:30 / `2026-03-08T07:30:00Z`。overlap 选较早 offset，纽约 2026-11-01 01:30 → `2026-11-01T05:30:00Z`。Swift Calendar 实现必须用这两个测试向量证明等价，不能默认变成 03:00。

## 表清单

Android 有 **18 个 Room 实体 = 17 个导出账本表 + restore_state**。不把 Room 内部表计为 iOS 业务实体。iOS ORM 迁移版本独立；目标语义与以下 SQL 名字对齐，完整字段/PK/FK/索引见 schema 快照。运行时 triggers/partial index 还需参考 CostDatabase/AccountFundsMigration。

| Android 实际表 | 关键字段/约束与 iOS 语义 |
|---|---|
| currencies | code PK；asset_type、display_name、symbol、default_scale、is_enabled、sort_order、metadata_version；seed 重放不覆盖用户选择 |
| visual_assets | id；kind、私有 relative_path、mime、宽高、byte_size、SHA256、processing_version、created_at；路径唯一，同 kind/hash/version 去重，无图片 BLOB |
| categories | id、name、transaction_type、parent_id、icon/color、icon_source/emoji/icon_asset_id/background_asset_id/background_focus、sort/archive、时间；最多两级、同类型、引用限制 |
| accounts | id、name、currency_code、视觉、sort/default/archive、时间；运行时 partial unique index 保证最多一个默认项 |
| tags | id、name、normalized_name 唯一、color/archive、时间；规范名算法与复用语义见产品规格 |
| transactions | 完整交易字段见下节；正金额、完整冻结估值、nullable unique request_key、软删除 |
| transaction_tags | (transaction_id, tag_id) 复合主键，反向索引；写入与账单原子完成 |
| fx_quotes | id、original/base code、rate_text、provider_id、data timestamp、历史 epoch day、fetched/expiry、LATEST/HISTORICAL；provider/pair/kind/data timestamp 唯一 |
| crypto_price_quotes | (asset_code, base_code, provider_id) PK，price_text、venue、data/fetched/expiry；独立于 Fiat |
| quick_templates | id/name/icon、type、amount_minor/scale/currency、category/account/note、sort、usage/last_used、archive、时间；无交易 FX 快照 |
| quick_template_tags | (template_id, tag_id) PK |
| recurring_rules | id/name/enabled、起止 epoch day、local minutes、zone、next/last evaluated、rule_version、catch_up_policy、frequency、interval、weekdays_mask、day/month/month_day_policy、账单 payload、时间 |
| recurring_rule_tags | (rule_id, tag_id) PK；原计划 Phase 2 列表遗漏，必须保留 |
| recurring_executions | id、rule_id、scheduled_at、status、transaction_id、attempt_count、last_error、时间；(rule_id, scheduled_at) 唯一 |
| anomaly_feedback | id、feedback_type、kind、nullable category_id、base_currency_code、amount_minor_text、base_scale、feature_version、created_at；精确金额文本，不级联丢反馈 |
| account_fund_openings | id/account、每账户唯一递增 revision、kind、enabled、currency/scale、nullable amount_minor、started_at/created_at；追加式，不覆写余额 |
| account_transfers | id、唯一 request_key、from/to account 与 kind、currency/scale、principal/profit、profit category/transaction、occurred_at/zone、note、created/updated/deleted；两侧与损益原子保护 |
| restore_state | id/settings；恢复事务设置 outbox，不导出为账本 |

原计划 `fiat_fx_cache/market_price_cache/account_opening_revisions/internal_transfers` 分别映射到 `fx_quotes/crypto_price_quotes/account_fund_openings/account_transfers`，不另建重复含义的表。

## 交易快照

保留 `transaction_type`、`original_amount_minor`、`original_scale`、`original_currency_code`、`base_currency_code`、`base_scale`、`exchange_rate_text`、`converted_base_amount_minor`、`rate_data_timestamp`、`rate_fetched_at`、`rate_provider`、`valuation_method`、`category_id`、`account_id`、`occurred_at_epoch_millis`、`occurred_zone_id`、`occurred_local_epoch_day`、`note`、`source_type`、`source_id`、`request_key`、`created_at_epoch_millis`、`updated_at_epoch_millis`、`deleted_at_epoch_millis`。

Crypto 扩展为 nullable `crypto_price_text/kind/source/venue/pair/data_timestamp/fetched_at`。Fiat 行这些字段全空；Crypto 保留实际单价/实际结算/市场参考语义，pair 为 asset/base、base 为 Fiat，并与通用 rate/source/time 保持一致。

Fiat valuation method：IDENTITY、ACTUAL_SETTLEMENT、MANUAL_RATE、LATEST_RATE、HISTORICAL_RATE、CURRENT_FALLBACK、CACHED_FALLBACK；Crypto 增加 MARKET_PRICE/CACHED_MARKET_PRICE 及独立 price kind。Provider 估值必须有数据时间/抓取时间；实际扣款和手工率不污染市场缓存。

source_type 为 MANUAL/TEMPLATE/RECURRING。手工 source_id 为空，其余保留历史来源标识，删除模板/规则不级联删除交易。软删除只设置 deleted_at；恢复清空，所有活动查询显式排除已删除行。分类/账户名称视觉不冻结，按稳定主数据引用渲染。

## 事务、缓存与约束

账单标签、模板一键/usage/撤销、周期 transaction/execution/cursor、转账/损益、默认账户、分类/标签删除与恢复都在 Repository 单事务内处理。规则执行状态 PENDING/CREATED/SKIPPED/FAILED_RETRYABLE/FAILED_FINAL，成功关联 transaction，失败保存有界错误，不存敏感响应。

资金只纳入起点后的事件，同毫秒按 createdAt 判别；受管损益不能单独改动。编辑 expectedUpdatedAt 防止覆盖，重复 request key 不双写。停用/删除边界见产品规格。

Fiat latest 的 expiresAt = provider data timestamp + 300000 ms，`now <= expiresAt` fresh；重新抓取不延长旧数据。historical 返回的 UTC 日必须匹配请求日，缓存有方向；不能简单反转已舍入 rate。Crypto 独立缓存/venue，fresh/stale 同时验证数据、获取、过期时间。历史交易复制值，不引用可变缓存。

索引覆盖 local day/type、category/day、account/day、base/day、source、唯一 request key、cross-ref 反向、rule/enabled/next、唯一 occurrence、provider/pair/date/expiry；v9 的 `(occurred_at_epoch_millis,id)` 支持最近列表。具体采用 query plan/有界数据验证，不盲目复制无用索引。

## Seed 与迁移

| 初始状态 | code 与 defaultScale |
|---|---|
| Fiat 启用 | CNY 2、USD 2、JPY 0、EUR 2、GBP 2、HKD 2、KRW 0、SGD 2、AUD 2、CAD 2、CHF 2 |
| Crypto 停用 | USDT 6、USDC 6、BTC 8、ETH 18 |

稳定 code/ID，insert-ignore，不覆盖 enabled/sort 或用户名称/图标。Android 通用数据库实际仅 seed 币种；iOS 原计划另要求默认分类/账户，因此 iOS 使用明确的非个人最小 seed：“其他支出”“其他收入”“默认账户”，稳定 ID 为 seed-expense-other/seed-income-other/seed-default-account。没有个人 ID、图片、账单或金额；账户资金不设置，seed 时间为确定的 epoch 0 元数据。用户编辑/停用的已有记录不覆盖，迁移只执行一次，不在每次启动重建被删除的默认资料。

Android v1 核心账本；v2 受管视觉；v3 Fiat FX；v4 模板；v5 循环；v6 异常反馈；v7 Crypto；v8 restore outbox；v9 最近索引；v10 账户资金。Android 导出 v1...v10 和显式 Migration 当前存在；iOS 不运行或修改 Android 迁移。Phase 0 冻结无个人数据的 v10 schema 证据；Phase 2 已运行 iOS 新库、分步 seed、失败回滚/重试和拒绝未来库的迁移测试。

GRDB 版本与 Android Room user_version 不共享：iOS v1 注册 v1_schema / v1_seed 两个原子 migration，application_id = 1129272137（COSI）、user_version = 1，历史存 grdb_migrations。未知应用 ID/版本/migration 或外来数据库拒绝打开，不自动擦除。资源 CostSchemaV1.sql 冻结 18 表及索引，62 个 guard 包含 Android 运行时约束、每表 INSERT/UPDATE 类型检查及资金标量校验；SQL NULL 不能绕过验证。GRDB DatabasePool 为私有磁盘库启用 WAL，内存 Queue 用于测试。

Phase 8 从审计的 Room DDL 生成 v10 交换库，包含 Room identity、索引和 user_version。iOS 导入把数据重放到冻结的 GRDB schema；iOS 应用内部仍使用独立的 schema 和 migration 历史。

## 统计与异常数据

按冻结 baseCurrency 和 local epoch day 查询；收入/支出分别正数求和，净额 income−expense。日均包含零账单日；月/季/年返回 partial，环比等长，比值基准为零返回不可用。同币种不同 scale 先精确归一化。

异常只读最多 120 天（90 基线+30 候选）、活动支出、指定本位币；单笔投影及日/叶分类聚合分别最多读 2001 行，用第 2001 行判定超 2000 安全上限，不能截断后作结论。反馈与算法版本分开，更新算法不清用户反馈，结果不持久化为账本事实。

## 备份契约（Phase 8）

完整文件头由 ASCII `COSTBK01` 和一个模式字节组成。模式 0 为明文 ZIP。模式 1 在 ZIP 密文前写入 16 字节 salt 和 12 字节 nonce。密钥使用 PBKDF2-HMAC-SHA256 派生 600000 次，长度为 256 位。AES-GCM 使用 128 位 tag，整个加密头作为 AAD。每次导出生成随机 salt 和 nonce。新密码按 Android 的 12...1024 个 UTF-16 代码单元限制校验，使用原始 UTF-8 序列派生密钥。

ZIP 内 database.sqlite/settings.json/manifest.json/visual_assets/*.webp，manifest 校验 version/schema/size/SHA256。17 张账本表在 TransferDatabase 的依赖顺序导出，restore_state/Room/系统调度内部表不导出为账本。

七项设置白名单来自 BackupPreferences。字符串为 `base_currency_code/theme_mode/glass_quality/anomaly_sensitivity`，布尔值为 `dynamic_color_enabled/reduce_motion_enabled/anomaly_enabled`。保留缺省字段及 Android 枚举值语义，拒绝未知字段和错误类型，JSON 上限为 8192 字节。iOS 应用本位币、主题和异常选项，并保存其他兼容值供后续导出。

限制：编码和展开总量 256 MiB、DB 128 MiB、每图片 8 MiB、最多 4096 entries；CSV 32 MiB、100000 笔、单元 256 KiB。拒绝未知版本/条目、重名、路径穿越、坏 checksum/引用/SQL/图片。明文 checksum 只能检测损坏，不代表认证。

Android 在独立库中升级 schema 1...10。iOS 依据冻结的版本列清单只读源库，并在受信 staging 中应用缺省值、当前约束及领域校验。恢复使用新图片文件名，账本及设置 outbox 在同一事务提交。交付和验证记录见 [Phase 8](PHASE8_PORTABLE_DATA.md)。
