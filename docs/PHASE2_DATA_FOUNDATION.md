# Phase 2 — 数据基础

日期：2026-11-16（Asia/Singapore）。状态：完成，Build/Test/unsigned IPA 与下载复核通过。用户确认 Sideloadly 安装 Phase 1 后居中显示 Cost，与验证版一致，并明确授权 Phase 2；完成后停止，不进入 Phase 3。

## 交付范围

- Model：CurrencyCode、Money（正 Int64/0...18 scale）、DecimalRate（canonical 38/18）、精确系数辅助、发生时间/时区/业务日、主数据与冻结 Fiat/Crypto snapshot。输入严格 ASCII 普通十进制，无损 Foundation Decimal 往返；中间运算精确，最终 HALF_EVEN，溢出/精度/舍入到零显式失败。
- Data：Android v10 语义的 18 个 GRDB storage record、显式 mapper、62 个 SQL guard/索引/外键；iOS application_id/user_version 与 Room 区分。v1_schema/v1_seed 两次原子 migration；未知库/未来版本拒绝，无擦除。
- 私有磁盘 DatabasePool/WAL、foreign keys、busy timeout，数据目录排除自动备份并使用系统文件保护；初始化不阻塞主线程。内存 Queue 和可注入 factory 支持测试，AppContainer 失败不报告 ready 或泄露原始 SQL 错误。
- Domain Repository 协议不依赖 GRDB。实现币种、分类、账户、标签、账单及独立 Fiat/市场缓存的基础读写；跨引用/标签原子更新、唯一 request key 防重、乐观编辑、软删除/恢复、分类引用保护、标签删除回滚及受管损益保护。
- 历史快照与缓存隔离，改币种默认 scale/符号、刷新/删除报价不重估交易。列表有界、区间半开，观察使用 AsyncThrowingStream/ValueObservation，无 Combine。
- Seed：15 币种（11 Fiat 开、4 Crypto 关）取 Android 通用定义；最小“其他支出／其他收入／默认账户”按 iOS 计划初始化，无个人账单、ID、图片或金额。迁移只执行一次，insert-ignore 保留已有 enabled/sort/name/visual。

版本为 0.2.0 / build 2；正常页面仍仅 Cost，数据层后台初始化。数据库初始化失败才显示可重试的通用错误。这里不实现账单管理页面、资金业务、模板/周期调度、网络报价、备份恢复或 Glass 视觉。

## 自动验收

- 本地 Python：实际 SQL 的全部表/列/索引与 v10 快照比对；seed/类型 guard/FK/application ID/version、层依赖及无 Float/Double 金额路径检查。
- Swift Model：各 scale、Int64 边界/溢出、严格小数位、精确 rescale、加减乘除、bankers tie、38/18、失真 Foundation 解析防护；264 组独立 Python precision-120 对照，包含超过 38 位的中间乘积。
- Swift Data：fresh/分步 migration、seed 不覆盖、失败整体回滚/重试、未知未来库保留、WAL/重开/精确字符串、CRUD/FK、20 并发重试、软删除/恢复/半开范围、标签更新失败回滚、主数据停用/删除保护、托管损益保护、缓存历史隔离、异步观察、启动成功/失败。
- GitHub Actions：本地静态门禁 + Simulator Build/Test + unsigned device Archive/IPA 验证，失败按真实日志修复；未运行的 Swift tests 不标通过。

## 实际结果

[GitHub Actions run 43886521271](https://github.com/loliruru/cost-ios/actions/runs/43886521271) 全 green，代码提交 `05ebe9461e78308485c745009d199ec8f5d9ca55`。Simulator Build、36 项 hosted Swift tests、unsigned device Archive、IPA 校验/上传全部通过。36 为 Swift Testing 报告的 test 数；其中两个参数化测试分别遍历 19 个 scale 和 9 个非法输入，独立 oracle 测试内部还运行全部 264 组数值向量，不把向量数冒充 test 数。

工具链：Xcode 16.4 / 16F6；Swift compiler 6.1.2、language mode 6 / Strict Concurrency complete；XcodeGen 2.46.0；iOS/Simulator SDK 18.5；iPhone 16 / iOS 18.5 模拟器。GRDB 7.12.0、revision `92a554cd0d5e8d67cb18993c6054e73fe42c066c`，唯一第三方应用依赖。

| 产物 | 结果 |
|---|---|
| [未签名 IPA](https://github.com/loliruru/cost-ios/actions/runs/43886521271/artifacts/14234224862) | 0.2.0 / build 2；1,318,068 bytes；arm64 / iOS device；最低 iOS 18.0 |
| IPA SHA-256 | `13400602d38726dc7f61918274b7dba3c1c20c86db16181d36569178f0cc9d1b` |
| [构建证据](https://github.com/loliruru/cost-ios/actions/runs/43886521271/artifacts/14234274794) | 保留 toolchain/依赖/构建测试日志、xcresult、IPA verification；artifact 保留 30 天 |

Windows 下载 IPA 后重新运行 `verify_ipa.py`，Payload/Cost.app、Info.plist、arm64 device Mach-O、可执行权限、无签名/描述文件、SHA-256 与 CI JSON/校验文件全部一致。另核对 bundled SQL/seed 和数值 fixture，不包含真实账本。签名与 iPhone 安装仍由用户通过 Sideloadly/SideStore 手动完成，未声称 Phase 2 已在用户真机运行。

本地 `verify_phase2.py`、`verify_foundation.py --android-root <只读参考>`、6 项 IPA 校验器测试和 diff 空白检查通过；35 项忽略探针、Android 53 文件 hash 未变。首次 run 43882547631 的应用编译成功，但 MigrationTests 的 Swift Testing 宏未正确推断闭包 throws；补齐显式 throwing closure 和 require 内部 try 后完整重跑通过，未删除或跳过断言。仅有既有 AppIntents 元数据提取提示与多架构模拟器 destination 提示，没有新增 Swift 源码编译警告。

原生 Git 推送遇到网络连接中断，改用 GitHub Git Data API 上传同一 tree/author/committer/message；核对 tree 和 commit SHA 完全一致后仅 fast-forward 更新远端。工具留在忽略的本机开发目录；未提交凭据或改写历史。收尾仅更新文档并标记 `[skip ci]`，不重复运行已通过的相同 App/Test/工程源代码。

无新增第三方 App 依赖、凭据或权限；不操作 Android 数据/设备，不自动安装到用户 iPhone。本阶段没有主观视觉验收项。ZIP/WebP 与跨 ORM 备份格式验证仍留 Phase 8；业务页面、UseCase 和资金操作在相应后续阶段实施。
