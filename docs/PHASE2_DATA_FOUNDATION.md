# Phase 2 — 数据基础

日期：2026-11-16（Asia/Singapore）。状态：实现已写入，正在验证，尚未完成。用户确认 Sideloadly 安装 Phase 1 后居中显示 Cost，与验证版一致，并明确授权 Phase 2；不进入 Phase 3。

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

当前本地 SQL 验证已通过，Swift 编译/测试与远端结果待记录。无新增第三方 App 依赖、凭据或权限；不操作 Android 数据/设备，不自动安装到用户 iPhone。本阶段没有主观视觉验收项。
