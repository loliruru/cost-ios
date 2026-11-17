# Phase 3 核心账单与基础资料

日期：2026-11-17（Asia/Singapore）。用户已批准 Phase 3；本阶段进行中，未获真机视觉验收，未开始 Phase 4。

## 范围与进度

已写入源码，等待本阶段 macOS Build/Test 验证：

- 原生账单/设置 TabView、按冻结业务日分组、有界 keyset 分页、备注/分类/账户/标签搜索及收支/日期/分类/账户/标签/删除状态筛选。
- 本币快速录入、完整 IDENTITY 快照、稳定 request key、编辑版本校验、软删除/撤销/已删除账单恢复。外币保存明确失败并保留草稿，估值留在 Phase 7。
- Observation ViewModel、系统输入控件、关闭/后台时的有界私有草稿保存与恢复；输入不做异步格式化回写。
- 两级分类、排序、父子停用/恢复约束、全部历史引用删除保护；账户排序/默认/停用；标签 NFKC/空白/小写归一化、同名复用/恢复、编辑冲突与确认删除。
- 内置图标与单个 emoji sequence 校验；受管 WebP 图片/背景、方向/焦点、去元数据/去重、owner lease、历史引用保护、零引用清理与损坏/缺失回退。
- 可选资金 revision 起点、零与未设置区分、可用金额/投入成本精确派生、同币本金转账、关联损益原子保存/编辑/撤销/恢复、冲突/幂等与资金不足回滚。

没有改动 schema v1、冻结 SQL 或 seed。仅按用户明确批准增加 libwebp-Xcode 1.6.0 编码依赖，见 ADR-011。资金派生使用项目内精确十进制系数，允许结果超过 Int64，不持久化漂移累计余额。读取在同一 SQLite 快照中以游标累加；历史本币/原币匹配优先级与 Android 一致。

## Android 参考与保护

只读核对 AccountFunds Model、Domain Calculator/UseCase、RoomAccountFundsRepository、Domain tests、VisualModels 和 ManageVisualAssetsUseCase。未读取 CSV、数据库、凭据、配对或签名材料，未修改 Android 仓库/安装/配置；不移植个人账户初始化代码或个人 seed。

## 图片能力实验

实验测试 `ImageCodecCapabilityTests.recordSystemImageExchangeCapabilities` 运行于真实 CI 的 iOS Simulator，记录 ImageIO encoder/decoder 清单，并实际尝试 PNG/WebP 编码。只生成 2×2 合成图，不截图、录屏或读取真实图片。第一轮因测试遗漏 Foundation import 编译失败，已修复；以最终 CI 输出为能力证据，不凭文档猜测编码支持。

实际 [run 44097781406](https://github.com/loliruru/cost-ios/actions/runs/44097781406) 输出：WebP decoder 存在，encoder 不存在，实际 destination 创建返回 unavailable；PNG 编码/回读成功。用户随后明确批准最小 WebP 编码依赖，采用 exactVersion 1.6.0 的独立 libwebp C 包，无其他 package 依赖。Android 交换格式保持 WebP；完整备份仍在 Phase 8 验证。

## 验证与剩余门禁

- Windows foundation/schema/seed/层边界检查已运行通过；Windows 不提供 Swift/Xcode 编译结果。
- 已新增资金 Domain/Repository、搜索分页、媒体生命周期与 Feature ViewModel 全链路测试，等待本阶段最终 macOS CI 验证。
- 新增 CostUITests，仅使用 DEBUG 参数启动的独立内存库、隔离草稿和媒体目录；通过系统控件验证新增/编辑/删除/撤销、大字体深色下的草稿恢复与保存可达性。源码不调用截图、OCR 或录屏。
- 必须完成本阶段 Build/Test/unsigned IPA、产物复核、受管视觉和客观无障碍/交互验证。
- 用户手动安装后验收 Light/Dark、最大 Dynamic Type、中文输入/键盘/关闭恢复、VoiceOver、新增→详情→编辑→删除→撤销、基础资料与资金路径；未收到 PASS 前不标记 Phase 3 完成。

后续产物、实际测试数量和限制应写入本文件与实施计划。不得把源码存在或 Phase 2 的 green 当作本阶段验收通过。

## 真机验收步骤（待用户执行）

使用自建测试资料即可，无需提供真实账本、金额或截图：

1. 账单新增 12.34 → 详情 → 编辑 20.01 → 删除 → 撤销；搜索备注、标签并筛选日期，活动列表不包含已删除账单。
2. 分类新增父子项、改排序、父项停用、先恢复父项再恢复子项；被历史引用的分类不能永久删除。账户切换默认并停用，标签创建规范同名复用，已停用标签确认删除后宿主账单仍保留。
3. 分类/账户选择单个 emoji、图片图标和背景，切换顶部/居中/底部焦点，关闭未保存编辑器再重开；停用后历史图标仍可显示。
4. 创建两个测试账户：“验收现金”以可用金额 100 开始，“验收投资”以投入成本 0 开始。转入本金 10 后为 90/10；从投资提回本金 5、收益 1 后为现金 96、成本 5，关联损益不能在账单入口单独修改。编辑、撤销/恢复转账联动正确；不足资金失败后两侧不变化。
5. 新建草稿后关闭/重开、切换后台；中文输入不被格式化重置。Light/Dark、最大 Dynamic Type、键盘下保存/关闭可达；VoiceOver 可读币种/金额/状态并完成主流程，Reduce Motion/Transparency 下功能一致。

按路径反馈 PASS 或具体 FAIL；主观布局、材质和风格由用户判断。收到验收前 Phase 3 保持进行中，不进入 Phase 4。
