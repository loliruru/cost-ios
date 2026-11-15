# Cost iOS 协作规则

## 开始工作

1. 读取本文件、[实施计划](docs/IMPLEMENTATION_PLAN.md)和当前 Phase 相关文档。
2. 检查 `git status`、`git diff`、最近提交；以当前仓库代码、测试、文档为事实来源。
3. 一次只执行用户批准的一个 Phase；完成、验证、更新状态、独立提交后停止，等待用户明确批准下一阶段。
4. 原始需求见 [cost-ios-codex-plan.md](cost-ios-codex-plan.md)；审计差异见 [Android 审计](docs/ANDROID_AUDIT.md)。不得把计划当作已实现功能。

## 长期硬规则

- iOS 工作仅在本独立仓库进行。`C:\Dev\Codex\Android\Cost` 是只读参考；绝不修改其代码、数据库、文档、Git 状态、设备安装或配置，不读取个人 CSV、数据库、密钥、配对或签名材料。
- Swift 6、Strict Concurrency、iOS 18+、SwiftUI、Observation `@Observable`、MVVM + Domain/UseCase、GRDB。不得引入 Combine/ObservableObject、SwiftData 或额外第三方应用依赖。
- `project.yml` 是唯一工程与应用依赖配置来源；XcodeGen 生成的 `.xcodeproj` 不入库。无 Mac/Xcode 时只报告实际完成的静态验证，不能声称 Build/Test/IPA 通过。
- **Phase 0 和 Phase 1 优先完成**；端到端构建链路未验证前，不开发业务功能。
- 金额、汇率、市场价格、统计禁止使用 `Float` / `Double`。金额用正数 `Int64` minor units 和 `0...18` scale，精确解析、受控 rescale、溢出报错；换算使用 HALF_EVEN。Foundation Decimal 的中间结果精度必须单独验证。
- 外币交易冻结原币金额/scale、本位币/scale、精确 rate、换算金额、估值方式、来源、Provider 数据时间和抓取时间。缓存、偏好或行情更新不得改写历史。
- Currency 数据驱动；Fiat FX 与 Crypto Market Price 的类型、接口和缓存分离；不假定稳定币等于法币。
- 业务日期冻结 IANA 时区和 local epoch day；区间使用半开边界；周期执行用唯一 occurrence key。DST 以 Android 源码及测试为准。
- 普通账单软删除，活动列表/统计/余额排除已删除记录；分类、标签、模板、循环的删除各自遵循产品文档中的引用保护。
- SwiftUI View 只展示与发送事件；ViewModel 经 UseCase/Repository 协议工作，不接触 GRDB Entity、SQL 或网络 DTO。复杂规则进入 Domain。
- 默认 offline-first、无广告、无强制注册、无无关分析或权限。API Key 只存 Keychain，不硬编码，不进入数据库、偏好、导出、备份、日志或公开产物。
- 用户图片通过系统选择器导入私有受管副本；稳定引用、尺寸/类型限制、去元数据、故障回退和引用感知清理。不能复制 Android 个人账本作为 iOS seed。
- Glass 只用于导航、操作和临时控制层，集中封装；内容层优先清晰。iOS 26 API 必须有可用性保护和 iOS 18 材质回退。支持 Light/Dark、Dynamic Type、VoiceOver、Reduce Motion/Transparency。
- 自动化验证功能、精度、原子性、迁移和客观无障碍；主观材质/美感由用户真机验收。未获明确要求不主动截图、OCR、录屏或读取真实账本。
- SideStore 安装、Apple ID 登录与签名刷新由用户手动完成。不得擅自发布、上传个人材料或进入下一 Phase。

## 事实来源

- [产品](docs/PRODUCT_SPEC.md)、[架构](docs/ARCHITECTURE.md)、[数据](docs/DATA_MODEL.md)、[设计](docs/DESIGN_SYSTEM.md)
- [阶段与验收](docs/IMPLEMENTATION_PLAN.md)、[决策](docs/DECISIONS.md)、[Android 审计](docs/ANDROID_AUDIT.md)

## 验证与交付

- 优先运行当前阶段的最小相关检查；本地 `python scripts/verify_foundation.py`，开发依赖安装见 [README](README.md)。构建命令见实施计划。
- schema 改动需显式 Migration、冻结快照与回滚测试；数值用 Android 边界向量对照；测试时间、时区、ID、Provider 均可注入，不依赖真实网络。
- 检查差异、敏感文件忽略规则和文件清单，仅暂存本阶段内容。提交格式 `type(scope): summary`。
- 简短汇报实现、验证及限制、是否需主观视觉验收，随后停止。后续 Phase 必须等待用户明确确认。
