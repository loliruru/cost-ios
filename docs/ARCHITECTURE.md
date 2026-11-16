# Cost iOS 架构

状态：Phase 2 数据基础已完成，macOS Build 与 36 项 hosted Swift tests 通过。已加入精确 Model、Repository 协议、GRDB/迁移/存储 mapper 和 App 依赖装配；尚无业务 UI、网络 Provider、主导航或后台任务。验证证据见 [Phase 2](PHASE2_DATA_FOUNDATION.md)。

## 技术与边界

Swift 6 / Strict Concurrency，iOS 18+，SwiftUI + Observation `@Observable`，MVVM + Domain/UseCase，GRDB/SQLite，URLSession async/await，Swift Charts，Keychain Services，UserNotifications/BGTaskScheduler，Swift Testing + XCTest。GRDB 是唯一第三方应用依赖。不引入 SwiftData、Combine、第三方 HTTP/DI/图表库。

```text
Feature -> Core/Domain -> Core/Model
Feature -> Core/DesignSystem
Core/Data -> Core/Domain + Core/Model
App -> 组装 Data 实现、Domain 协议与 Feature
```

首版为一个 App target 内的目录边界；不假称目录已实现编译隔离。Domain 只依赖 Foundation/Model，不依赖 SwiftUI、UIKit、GRDB、URLSession、Keychain 或具体系统调度。Entity、网络 DTO 与 View model 显式映射，不向上透传。Feature 不相互访问实现类。

## Composition root 与状态流

`CostApp` 为入口，持有 `@MainActor @Observable AppContainer`。启动时异步打开私有数据库并组装各个 Domain Repository 协议，防止重复初始化；持久化失败不报告 ready，也不向用户输出 SQL/金额或原始异常。正常页面继续只显示 Cost。后续 Feature 通过构造参数接收所需协议；Provider、Clock、IANA zone、ID 生成器、文件存储和后台协调器也由 App 组装，不在 Domain 访问全局 Service Locator。

Feature View 观察 `@MainActor @Observable` ViewModel 的页面状态并发送明确事件；ViewModel 验证展示输入，调用 UseCase/协议，将结果映射为可展示状态。导航只传稳定 ID。输入文本、选区、IME composition 保留在合适的 UI 编辑状态，异步结果不能覆盖更新的输入；保存时捕获不可变草稿。幂等键随草稿恢复，不重放无键写入。

写路径：事件 → ViewModel → UseCase 业务校验/精确估值 → Repository 原子事务 → 观察失效 → 新展示状态。读路径使用 GRDB 有界查询/ValueObservation 与可取消任务，聚合结果由 Domain 补零、比较和解释。视图生命周期结束时取消观察，避免过期结果覆盖新筛选。

## 并发与数据库

数据库在 Data 层封装，以 GRDB DatabasePool/WAL 提供一致快照及串行写入；Phase 2 在 GRDB 7.12.0 上验证 async read/write 与可取消 ValueObservation 流，内存测试使用 DatabaseQueue。UI MainActor 不同步执行数据库、图片、备份或网络工作。跨隔离边界传不可变 Sendable 值；不以 unchecked Sendable 或关闭严格并发掩盖问题。

显式 GRDB DatabaseMigrator 维护 iOS schema 历史；启用 foreign keys、唯一键、约束/必要 trigger 和事务，禁止 destructive migration。保留 Android 表/列语义，备份通过映射而非宣称两个 ORM 文件可直接互换。运行时约束也必须进入迁移/导入校验，Room schema JSON 本身不含全部约束。

账单/标签、模板账单/使用统计/撤销、周期 occurrence/transaction/cursor、默认账户切换、分类删除引用复核、转账/损益及恢复均有单一事务边界。资金用同一读取快照派生，不持久化累计余额。

设置使用 typed preferences repository，普通小型非敏感值可落 UserDefaults；核心关系数据在 SQLite。恢复设置 outbox 在暴露业务 Repository/后台协调器前重放。API Key 仅 Keychain，绝不存 UserDefaults/SQLite。备份/恢复与周期执行共享维护互斥；媒体清理与引用变更有独立维护边界。

## 精确数值与统计

Int64 minor units 与字符串 Decimal rate/price，禁用 Double/Float。Foundation Decimal 输入必须经 canonical text 无损往返；乘除采用项目内十进制整数系数，允许超过 38 位的精确中间积，最终仅一次 HALF_EVEN，再检查正数与 Int64 溢出。Phase 2 已通过 Android 数值边界与 264 组 precision-120 独立对照；没有新增数值库。统计多行聚合仍在 Phase 6 实现。

统计按 local epoch day 半开区间和冻结本位币查询，有界 bucket/样本并精确累加；SQLite SUM(Int64) 也有溢出，不能改成 REAL/TOTAL 绕过。详见[数据模型](DATA_MODEL.md)。

## Provider 与失败

Domain 定义独立 Fiat ExchangeRateProvider/Repository 与 CryptoPriceProvider/Repository；Data 使用 URLSession 适配原始十进制 token、DTO、限长 HTTPS transport。Provider 不写交易，Repository 管理有方向缓存、并发请求去重、freshness、typed failure 和有界重试，UseCase 最终冻结快照。

无 key 不发请求。offline/timeout/unauthorized/rateLimited/serverError/invalidPayload/noHistoricalData/notConfigured 为可行动状态；不暴露 URL 中的 key、响应全文或内部堆栈。429/5xx/timeout 的有界退避及 Retry-After 按 Android 行为移植；取消不吞掉、不变成业务成功。

## 周期与平台适配

BGAppRefreshTask 为尽力触发器，UserNotifications 只提醒；真正生成入口统一经过 Domain occurrence 协调器。每次前台启动/恢复补处理到期规则，尊重用户补记策略与唯一 occurrence key，跨前台/后台并发只提交一次。后台到期取消保留可恢复状态。仅在 Phase 5 加入实际 task identifier/权限与 Info.plist 配置。

NavigationStack、TabView、Sheets 负责系统导航，路由/草稿恢复和系统交互在 Feature/App。Glass 的可用性、材质、系统可访问性与触觉策略集中 DesignSystem，Feature 不散落平台判断。

媒体通过 PhotosPicker/系统文件选择器进入 Data 受管存储，有界读取、去 EXIF、下采样、静态副本、稳定 ID/hash 和相对路径；staging → 文件发布 → 引用事务，失败补偿，零引用才回收。WebP 跨平台读写限制是未解决工程边界，见[决策](DECISIONS.md)。

## 工程与测试

`project.yml` 是唯一工程与 SPM 配置，显式 Cost/CostTests shared schemes。测试为 hosted Swift Testing target。`.xcodeproj`/workspace 为生成产物；不维护重复的根 Package.swift 依赖图，原因见 ADR-002。

Windows：YAML/Plist/JSON、文件/链接、忽略规则、审计基线、workflow Bash 语法和 IPA 校验器测试。macOS Actions（Phase 1）：XcodeGen → SPM resolve → simulator build/test → unsigned device archive → IPA 结构检查与 artifact。实际构建/测试证据见 [Phase 1](PHASE1_BUILD.md)，不以本地静态检查代替编译。

后续测试覆盖 Money/Decimal/日期/统计/异常 Domain、GRDB CRUD/所有 Migration/事务/快照、固定 Provider 响应/错误、SwiftUI 关键流程和可访问性、后台补记、备份失败/恢复往返。Clock、Zone、ID、Provider 均可替换；正常测试不依赖真实网络。Android 历史验证结果只能作为参考。
