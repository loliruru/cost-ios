# Phase 3 核心账单与基础资料

日期：2026-11-17（Asia/Singapore）。用户已批准 Phase 3；本阶段进行中，未获真机视觉验收，未开始 Phase 4。

## 范围与进度

已写入源码，等待本阶段 macOS Build/Test 验证：

- 原生账单/设置 TabView、按冻结业务日分组、有界 keyset 分页、备注/分类/账户/标签搜索及收支/日期/分类/账户/标签/删除状态筛选。
- 本币快速录入、完整 IDENTITY 快照、稳定 request key、编辑版本校验、软删除/撤销/已删除账单恢复。外币保存明确失败并保留草稿，估值留在 Phase 7。
- Observation ViewModel、系统输入控件、关闭/后台时的有界私有草稿保存与恢复；输入不做异步格式化回写。
- 两级分类、排序、父子停用/恢复约束、全部历史引用删除保护；账户排序/默认/停用；标签 NFKC/空白/小写归一化、同名复用/恢复、编辑冲突与确认删除。
- 内置图标与单个 emoji sequence 校验。受管图片、背景和引用清理须先解决 ADR-006 的格式门禁，尚未实现。
- 可选资金 revision 起点、零与未设置区分、可用金额/投入成本精确派生、同币本金转账、关联损益原子保存/编辑/撤销/恢复、冲突/幂等与资金不足回滚。

没有改动 schema v1、冻结 SQL、seed 或第三方依赖。资金派生使用项目内精确十进制系数，允许结果超过 Int64，不持久化漂移累计余额。读取在同一 SQLite 快照中以游标累加；历史本币/原币匹配优先级与 Android 一致。

## Android 参考与保护

只读核对 AccountFunds Model、Domain Calculator/UseCase、RoomAccountFundsRepository、Domain tests、VisualModels 和 ManageVisualAssetsUseCase。未读取 CSV、数据库、凭据、配对或签名材料，未修改 Android 仓库/安装/配置；不移植个人账户初始化代码或个人 seed。

## 图片能力实验

实验测试 `ImageCodecCapabilityTests.recordSystemImageExchangeCapabilities` 运行于真实 CI 的 iOS Simulator，记录 ImageIO encoder/decoder 清单，并实际尝试 PNG/WebP 编码。只生成 2×2 合成图，不截图、录屏或读取真实图片。第一轮因测试遗漏 Foundation import 编译失败，已修复；以最终 CI 输出为能力证据，不凭文档猜测编码支持。

Android 交换契约为 WebP。若 iOS 系统不能编码，必须在有证据后由用户决定是否例外允许编码依赖或改变交换策略；未获决定前不擅自改格式、扩展名或丢图。

## 验证与剩余门禁

- Windows foundation/schema/seed/层边界检查已运行通过；Windows 不提供 Swift/Xcode 编译结果。
- 已新增资金 Domain/Repository、搜索分页与 Feature ViewModel 全链路测试，等待 macOS CI 执行。
- 必须完成本阶段 Build/Test/unsigned IPA、产物复核、受管视觉和客观无障碍/交互验证。
- 用户手动安装后验收 Light/Dark、最大 Dynamic Type、中文输入/键盘/关闭恢复、VoiceOver、新增→详情→编辑→删除→撤销、基础资料与资金路径；未收到 PASS 前不标记 Phase 3 完成。

后续产物、实际测试数量和限制应写入本文件与实施计划。不得把源码存在或 Phase 2 的 green 当作本阶段验收通过。
