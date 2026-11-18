# Phase 3 核心账单与基础资料

开始日期：2026-11-17（Asia/Singapore），验证持续至 2026-11-18。用户已批准 Phase 3；本阶段进行中，未获真机视觉验收，未开始 Phase 4。

## 范围与进度

已实现并通过本阶段 macOS Build/Test：

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

- Windows foundation/schema/seed/层边界检查、6 项 IPA 校验器测试、35 项忽略探针，以及 Android 53 文件 hash/HEAD/tracked diff 只读复核通过；Windows 不提供 Swift/Xcode 编译结果。
- 资金 Domain/Repository、搜索分页、媒体生命周期、草稿持久化、日期展示与 Feature ViewModel 全链路测试已通过本阶段最终 macOS CI。
- 新增 CostUITests，仅使用 DEBUG 参数启动的独立内存库、隔离草稿和媒体目录；通过系统控件验证新增/编辑/删除/撤销、大字体深色下的草稿恢复与保存可达性。源码不调用截图、OCR 或录屏。
- 本阶段 Build/Test/unsigned IPA、产物复核、受管视觉与客观 UI 语义/状态验证已完成；真实 VoiceOver 操作、中文 IME 手感和主观布局/风格仍需用户真机确认。
- 用户手动安装后验收 Light/Dark、最大 Dynamic Type、中文输入/键盘/关闭恢复、VoiceOver、新增→详情→编辑→删除→撤销、基础资料与资金路径；未收到 PASS 前不标记 Phase 3 完成。

以下只记录实际运行结果，不把源码存在或 Phase 2 的 green 当作本阶段验收通过。

已验证中间实现 [run 44120173209](https://github.com/loliruru/cost-ios/actions/runs/44120173209)，源码 `0191c71ee831909ee2693209fbe2b89aa6158a4b`：64 项 hosted Swift tests（含 264 组精度向量）、2 条原生 UI 测试（54 秒）、Simulator Build、unsigned device Archive、IPA 校验/上传全部通过。其后补齐媒体 clock/ID 可注入性及固定断言，最终源码与产物以随后的验证结果为准。

编译期间已按真实日志修正 SwiftUI Section 的 header/footer 重载、catch 变量遮蔽，以及主导航表达式类型推断超时（拆分设置页、显式 Label）。没有删除测试、降低 Swift 6/并发模式或跳过构建门禁。Xcode 的 AppIntents metadata processor 会对未链接 AppIntents 的 targets 输出跳过提示；未引入本阶段不需要的 AppIntents 依赖来消除提示。

## 最终自动验证与交付

[run 44124799270](https://github.com/loliruru/cost-ios/actions/runs/44124799270) 全部 green，最终应用源码 `6f542851f76531bd6c872a0a66d154a01b06b632`：

- 66 项 hosted Swift tests 全通过，实际执行 4.814 秒；包含 Phase 2 的 264 组独立精度向量、资金原子性/守恒/旧账截止/幂等/并发、受管损益保护、媒体去重/lease/清理/修复/元数据与 WebP 真实解码、草稿重开、固定时区和闰日筛选。
- 2 项原生 UI tests 全通过，69.936 秒：新增→编辑→删除→撤销；深色/最大 Dynamic Type 下草稿恢复、可访问金额名称与保存可达性。测试只使用独立内存库、隔离草稿/媒体目录，不读取真实账本，不调用截图/OCR/录屏。
- Simulator Build、unsigned device Archive、IPA 打包/检查/上传通过。实际 Xcode 16.4（16F6）、Swift 6.1.2（Swift 6 language mode）、XcodeGen 2.46.0、SDK/runtime 18.5、iPhone 16；最低部署 iOS 18。
- Windows 下载后重新运行 IPA 校验，CI/本地 JSON 完全一致；SHA-256 与校验文件一致；随包 libwebp 许可证与源码字节一致，无账本/CSV/签名材料。

[下载 IPA artifact](https://github.com/loliruru/cost-ios/actions/runs/44124799270/artifacts/14349181988)；[构建/测试证据](https://github.com/loliruru/cost-ios/actions/runs/44124799270/artifacts/14349306852)。artifact 保留 30 天，需登录 GitHub。

| 项目 | 实际值 |
|---|---|
| 版本 | 0.3.0 / build 3 |
| IPA 大小 | 1,837,193 bytes |
| Payload | Payload/Cost.app/ |
| 平台与签名 | arm64 / iOS device / unsigned |
| SHA-256 | `913439cc98de3d9410c7bc2e8a3f332c78bc6f6f003f609846cf1d2cfbc183e9` |

本地下载位于忽略的 `build/downloads/44124799270/ipa/Cost-unsigned.ipa`；日志与 xcresult 位于对应 evidence 目录。最后补齐媒体 clock/ID 注入，并修复详情使用设备时区、非公历日期筛选可能偏移的问题；最终产物已包含这些修正。

核心实现入口：[Domain UseCase](../Cost/Core/Domain/LedgerUseCases.swift)、[资金事务](../Cost/Core/Data/GRDBAccountFundsRepository.swift)、[受管媒体](../Cost/Core/Data/ManagedVisualStore.swift)、[主导航与账单](../Cost/Feature/Ledger/LedgerRootView.swift)、[快速录入](../Cost/Feature/Entry/EntryViewModel.swift)。

限制：当前快速录入只保存本币完整 identity 快照；Fiat FX/Crypto、模板、循环、统计和完整备份仍按后续阶段实现。Glass 精修属于 Phase 9。用户手动签名安装后，按下列清单验收；未收到 PASS 前 Phase 3 不标记全部完成。

## 排序可见性修复（build 4）

真机反馈指出分类表单找不到排序项。build 3 将说明作为输入框占位文字，预填的 `0` 隐藏了说明。提交 `0d03d6c` 在分类和账户表单将「排序（小的在前）」显示为常驻标签，位置在「名称」下方。新增 UI 测试确认输入框分别为 `0` 和 `10` 时，标签均可见。

ARM Runner 两次没有取得执行机器，本次使用独立 Intel 验证分支。提交 `875467a` 相对主分支修复提交只调整 Runner 标签与对应的静态检查。Xcode 16.4 和 iOS 18.5 模拟器通过 66 项 Swift tests、3 项 UI tests，设备 Archive 和 IPA 检查也通过。下载后复核为 `0.3.0 / build 4`、arm64 iOS device、未签名，SHA-256 与 CI 一致（`0e77bb88dbdcca8567ed3ee42b33059f0fe192b2f868f2dca68238a310d711ae`）。[CI 运行](https://github.com/loliruru/cost-ios/actions/runs/44328711441) · [build 4 IPA](https://github.com/loliruru/cost-ios/actions/runs/44328711441/artifacts/14442235308)

## 真机验收步骤（待用户执行）

使用自建测试资料即可，无需提供真实账本、金额或截图：

1. 账单新增 12.34 → 详情 → 编辑 20.01 → 删除 → 撤销；搜索备注、标签并筛选日期，活动列表不包含已删除账单。
2. 在「设置 → 分类」新增父子项。打开「新增分类」或「编辑分类」，名称下方、收支上方是排序数字（初始为 `0`）。build 3 有值时只显示数字，build 4 增加常驻标签「排序（小的在前）」。把两个测试分类分别设为 `10` 和 `20`，保存后检查列表中 `10` 排在 `20` 前。停用父项后先恢复父项再恢复子项。被历史引用的分类不能永久删除。账户切换默认并停用，标签创建规范同名复用，已停用标签确认删除后宿主账单仍保留。
3. 分类/账户选择单个 emoji、图片图标和背景，切换顶部/居中/底部焦点，关闭未保存编辑器再重开；停用后历史图标仍可显示。
4. 创建两个测试账户：“验收现金”以可用金额 100 开始，“验收投资”以投入成本 0 开始。转入本金 10 后为 90/10；从投资提回本金 5、收益 1 后为现金 96、成本 5，关联损益不能在账单入口单独修改。编辑、撤销/恢复转账联动正确；不足资金失败后两侧不变化。
5. 新建草稿后关闭/重开、切换后台；中文输入不被格式化重置。Light/Dark、最大 Dynamic Type、键盘下保存/关闭可达；VoiceOver 可读币种/金额/状态并完成主流程，Reduce Motion/Transparency 下功能一致。

按路径反馈 PASS 或具体 FAIL；主观布局、材质和风格由用户判断。收到验收前 Phase 3 保持进行中，不进入 Phase 4。
