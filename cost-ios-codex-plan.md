# Cost iOS — Codex 可执行开发方案

> [!IMPORTANT]
> 本文档是给 Codex 的完整执行指令。Codex 必须严格按照本文档的阶段顺序、验收标准和技术约束执行，不得跳过阶段、擅自更改架构或一次性生成整个 App。

---

## 一、项目概述

**项目名称**：Cost iOS

**目标**：将已有的 Android 原生记账 App「Cost」移植为独立的 iOS 原生版本。保留 Android 版核心业务逻辑，使用 Apple 设计规范重新设计 UI。

**核心约束**：

| 项目 | 要求 |
|---|---|
| 语言 | Swift 6 |
| UI 框架 | SwiftUI |
| 开发环境 | Windows 11 + Codex（无 Mac、无 Xcode） |
| 构建环境 | GitHub Actions macOS Runner（公开仓库免费） |
| 签名方式 | 免费 Apple ID + SideStore（不购买 Apple Developer Program） |
| 工程管理 | XcodeGen（project.yml 是唯一配置来源） |
| 安装方式 | SideStore 侧载到 iPhone |
| App Store | 不上架 |
| 第三方依赖 | 尽可能为零 |

---

## 二、Android 参考项目

**路径**：`C:\Dev\Codex\Android\Cost`

### 必须阅读的文档（按优先级）

1. `AGENTS.md` — 协作规则
2. `docs/PRODUCT_SPEC.md` — 产品规格 V3（V1 范围、账单、分类、模板、周期、统计、多币种）
3. `docs/DATA_MODEL.md` — 数据模型（Room schema v10、Money、Decimal rate、核心实体定义）
4. `docs/ARCHITECTURE.md` — 架构（模块边界、UDF、依赖方向）
5. `docs/FX_PROVIDER.md` — 汇率 Provider（Twelve Data Forex v2、freshness、缓存、密钥）
6. `docs/BACKUP_FORMAT.md` — 备份格式（CSV、ZIP envelope、原子恢复）
7. `docs/DESIGN_SYSTEM.md` — 设计系统（Liquid Glass、信息层、材质分工）
8. `docs/IMPLEMENTATION_PLAN.md` — 实施计划（20 个 Phase 全部完成）

### Android 保护规则

- **绝对不允许**修改 Android 项目的任何代码、数据库、架构或文档。
- iOS 必须建立独立目录 `C:\Dev\Codex\iPhone\cost`、独立 Git 仓库。
- 业务规则必须与 Android 保持一致，从 Android 文档和源码提取，不得重新猜测。

---

## 三、iOS 技术架构

### 3.1 技术栈

| 领域 | 技术 | 说明 |
|---|---|---|
| 语言 | Swift 6 | Strict Concurrency |
| UI | SwiftUI | iOS 18+ |
| 状态管理 | `@Observable` (Observation) | 不使用 ObservableObject/Combine |
| 架构 | MVVM + Domain/UseCase | 与 Android 对齐 |
| 数据库 | **GRDB.swift**（SQLite） | 见下方说明 |
| 网络 | URLSession + async/await | 无第三方 HTTP 库 |
| 图表 | Swift Charts | 系统框架 |
| 异步 | Swift Concurrency (async/await, TaskGroup) | 无 Combine |
| 本地通知 | UserNotifications | 周期记账提醒 |
| 密钥 | Keychain Services | API Key 存储 |
| 测试 | Swift Testing + XCTest | 优先 Swift Testing |
| 工程管理 | XcodeGen | project.yml → .xcodeproj |
| 最低部署 | iOS 18.0 | 支持 @Observable, Swift Charts, SwiftData |

> [!NOTE]
> **为什么选 GRDB 而不是 SwiftData**：
> - Cost 的数据模型复杂（17+ 实体、多对多关系、跨表事务、精确 Decimal 存储、复杂 SQL 聚合统计）
> - SwiftData 不支持自定义 SQL 聚合查询、不支持显式事务控制、Migration 能力弱
> - GRDB 是纯 Swift 的 SQLite 封装，支持 Migration、事务、自定义 SQL、Decimal 精度、WAL、编译时 SQL 检查
> - 与 Android Room（也是 SQLite 封装）对称，数据兼容性更好
> - GRDB 是唯一允许的第三方依赖，通过 Swift Package Manager 引入

### 3.2 项目目录结构

```text
Cost/
├── project.yml                    # XcodeGen 配置（唯一工程来源）
├── Package.swift                  # SPM 依赖声明（GRDB）
├── .gitignore
├── .github/
│   └── workflows/
│       └── build.yml              # GitHub Actions CI
├── AGENTS.md                      # Codex 协作规则
├── docs/
│   ├── PRODUCT_SPEC.md
│   ├── ARCHITECTURE.md
│   ├── DATA_MODEL.md
│   ├── DESIGN_SYSTEM.md
│   ├── IMPLEMENTATION_PLAN.md
│   └── DECISIONS.md
├── Cost/                          # 主 App Target
│   ├── App/
│   │   ├── CostApp.swift
│   │   └── AppContainer.swift     # 依赖组装
│   ├── Core/
│   │   ├── Model/                 # Money, Decimal, 值对象, 业务枚举
│   │   ├── Domain/                # Repository 协议, UseCase, 统计规则
│   │   ├── Data/                  # GRDB, Provider, Repository 实现, Mapper
│   │   └── DesignSystem/          # Theme, Tokens, 基础组件, Glass
│   ├── Feature/
│   │   ├── Ledger/                # 账单列表、CRUD
│   │   ├── Entry/                 # 快速记账
│   │   ├── Templates/             # 快捷模板
│   │   ├── Recurring/             # 周期记账
│   │   ├── Statistics/            # 统计图表
│   │   ├── Categories/            # 分类管理
│   │   ├── Accounts/              # 账户管理
│   │   ├── Settings/              # 设置
│   │   └── Backup/                # 备份恢复
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   └── Localizable.xcstrings
│   └── Info.plist
└── CostTests/                     # 测试 Target
    ├── Core/
    │   ├── ModelTests/
    │   ├── DomainTests/
    │   └── DataTests/
    └── Feature/
```

### 3.3 架构依赖方向

```text
Feature ────→ Core/Domain ────→ Core/Model
   │                ▲
   └──→ Core/DesignSystem  │
                    │ implements
               Core/Data ────→ Core/Model
                    ▲
                    │ assembled by
                  App/
```

- `Core/Domain` 不依赖 UIKit、SwiftUI、GRDB 或 URLSession
- Feature 的 ViewModel 调用 UseCase/Repository 协议，不直接操作数据库
- GRDB Entity 与网络 DTO 不穿透到 View 层

---

## 四、核心业务规则（从 Android 移植）

以下规则必须与 Android 完全一致，不得修改：

### 4.1 金额精度

```swift
struct Money {
    let minorUnits: Int64       // unscaledValue, e.g. CNY 12.34 → 1234
    let currencyCode: String    // ISO 4217
    let scale: Int              // CNY=2, JPY=0, BTC=8
}
```

- scale 范围 `0...18`，Long 溢出必须失败
- 金额必须 > 0，方向由 TransactionType (.income/.expense) 表达
- 输入先解析为 `Decimal`（Swift Foundation），再转为 `Int64`，不经过 `Double`
- 不同 scale 相加前必须 rescale

### 4.2 汇率精度

- 汇率使用规范化十进制字符串持久化（如 `"0.047315"`）
- Domain 层解析为 `Decimal`
- 最大 precision 38、最大 scale 18
- 网络 JSON 必须从原始字符串解析，禁止先读成 `Double`
- 汇率方向：`rateBasePerOriginal = 1 original → N base`
- 换算：`convertedBaseMajor = originalMajor × rateBasePerOriginal`
- 舍入：`Decimal.RoundingMode.bankers`（即 HALF_EVEN）

### 4.3 历史汇率不可变

- 每笔交易冻结保存：原金额、原币种、本位币、汇率字符串、换算金额、汇率来源、Provider 时间戳、本机抓取时间
- 汇率缓存刷新/淘汰不得改写历史账单
- 只有用户显式编辑才能改变历史快照

### 4.4 Currency 数据驱动

- Currency 不是 Swift enum，是数据库 seed data
- 初始启用：CNY, USD, JPY, EUR, GBP, HKD, KRW, SGD, AUD, CAD, CHF
- 初始停用：USDT, USDC, BTC, ETH
- Fiat FX 与 Crypto Market Price 独立接口和数据路径

### 4.5 时间与时区

- `createdAt`/`updatedAt`/provider timestamp 使用 UTC epoch milliseconds (Int64)
- 账单发生时间保存 `occurredAtEpochMillis`、`occurredZoneId`、`occurredLocalEpochDay`
- 报表区间使用 `[startEpochDay, endEpochDayExclusive)` 半开区间
- 周期规则保存 IANA ZoneId，DST gap 推进到下一有效时刻，overlap 选较早 offset

### 4.6 软删除

- 普通删除采用可恢复软删除
- 已删除账单不参与列表、统计和余额
- 可由撤销/恢复重新启用

---

## 五、iOS UI 设计要求

- 原生 SwiftUI，**不复制 Android Material 设计**
- iOS 原生导航（NavigationStack）
- 原生 TabView
- SF Symbols 图标
- Liquid Glass 效果（使用 iOS 26 原生 `.glassEffect` API，若 target < iOS 26 则降级为 `.ultraThinMaterial`）
- 浅色 + 深色模式
- Dynamic Type 动态字体
- 合理动画（matchedGeometryEffect, withAnimation）
- 触觉反馈（UIImpactFeedbackGenerator）
- 无障碍支持（VoiceOver labels, accessibility traits）
- 适配 iPhone 全尺寸

> [!WARNING]
> Liquid Glass 不是"所有页面都做成玻璃"。账单内容必须优先保证清晰可读。Glass 只用于导航栏、TabBar、FAB、Bottom Sheet 等控件层。

---

## 六、构建与部署链路

```
Windows 11 + Codex (编写代码)
    → git push → GitHub Public Repository
    → GitHub Actions (macos-15 Runner)
    → brew install xcodegen
    → xcodegen generate
    → xcodebuild build (iphonesimulator + iphoneos)
    → xcodebuild test (iphonesimulator)
    → 打包 unsigned IPA
    → 上传 GitHub Actions Artifact
    → 用户下载 IPA
    → SideStore / Sideloadly 安装到 iPhone
```

### 6.1 GitHub Actions Workflow

```yaml
# .github/workflows/build.yml
name: Build Cost iOS

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-15
    timeout-minutes: 30

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode Project
        run: xcodegen generate

      - name: Show Xcode Version
        run: xcodebuild -version

      - name: Resolve SPM Dependencies
        run: xcodebuild -resolvePackageDependencies -project Cost.xcodeproj -scheme Cost

      - name: Build for Simulator
        run: |
          xcodebuild build \
            -project Cost.xcodeproj \
            -scheme Cost \
            -destination 'generic/platform=iOS Simulator' \
            -configuration Debug \
            CODE_SIGNING_ALLOWED=NO

      - name: Run Tests
        run: |
          xcodebuild test \
            -project Cost.xcodeproj \
            -scheme CostTests \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            -configuration Debug \
            CODE_SIGNING_ALLOWED=NO

      - name: Build for Device (Unsigned)
        run: |
          xcodebuild archive \
            -project Cost.xcodeproj \
            -scheme Cost \
            -destination 'generic/platform=iOS' \
            -configuration Release \
            -archivePath build/Cost.xcarchive \
            CODE_SIGNING_ALLOWED=NO \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO

      - name: Create Unsigned IPA
        run: |
          mkdir -p build/Payload
          cp -r build/Cost.xcarchive/Products/Applications/Cost.app build/Payload/
          cd build
          zip -r Cost-unsigned.ipa Payload
          rm -rf Payload

      - name: Upload IPA Artifact
        uses: actions/upload-artifact@v4
        with:
          name: Cost-unsigned-ipa
          path: build/Cost-unsigned.ipa
          retention-days: 30

      - name: Upload Build Logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: build-logs
          path: |
            build/**/*.log
            ~/Library/Logs/DiagnosticReports/
```

### 6.2 XcodeGen project.yml 基础模板

```yaml
name: Cost
options:
  bundleIdPrefix: com.personal
  deploymentTarget:
    iOS: "18.0"
  xcodeVersion: "16.0"
  generateEmptyDirectories: true

packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift
    from: "7.0.0"

settings:
  base:
    SWIFT_VERSION: "6.0"
    CODE_SIGNING_ALLOWED: "NO"
    CODE_SIGN_IDENTITY: ""
    PRODUCT_BUNDLE_IDENTIFIER: com.personal.cost

targets:
  Cost:
    type: application
    platform: iOS
    sources:
      - Cost
    dependencies:
      - package: GRDB
    settings:
      base:
        INFOPLIST_FILE: Cost/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.personal.cost

  CostTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - CostTests
    dependencies:
      - target: Cost
    settings:
      base:
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Cost.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Cost"
        BUNDLE_LOADER: "$(TEST_HOST)"
```

### 6.3 SideStore 安装流程（用户手动，Codex 不执行）

1. iPhone 安装 SideStore（通过 iLoader 或 Sideloadly 首次安装）
2. Windows USB 连接 iPhone，完成配对获取 pairing file
3. SideStore 配置 LocalDevVPN
4. 从 GitHub Actions Artifact 下载 `Cost-unsigned.ipa`
5. SideStore 导入 IPA 并签名安装
6. 每 7 天前在 SideStore 中刷新签名（SideStore 支持后台自动刷新，但不保证 100% 可靠）

> [!CAUTION]
> - 免费 Apple ID 签名有效期 7 天，需定期刷新
> - 同时最多安装 3 个侧载 App（含 SideStore 本身）
> - 配对文件失效需重新 USB 配对
> - iOS 大版本更新可能暂时导致 SideStore 不兼容
> - 保留 Sideloadly 作为备用 USB 安装工具

---

## 七、安全与隐私

### 7.1 .gitignore 必须包含

```gitignore
# Xcode
*.xcodeproj/
*.xcworkspace/
xcuserdata/
DerivedData/
build/

# Secrets
*.p12
*.mobileprovision
*.cer
local.properties
Secrets.swift

# Personal data
*.sqlite
*.sqlite-wal
*.sqlite-shm
*.csv
*.json.backup
backup/

# SideStore
*.plist.pairing
anisette/

# System
.DS_Store
*.swp
```

### 7.2 API Key 管理

- Twelve Data API Key 存储在 iOS Keychain，**不硬编码**
- 用户首次启动时在 Settings 页面手动输入
- 不存入数据库、备份、导出或日志
- 没有 Key 时 Provider 返回 `.notConfigured`，仅提供手工汇率

### 7.3 公开仓库安全规则

- 不提交任何个人数据、密钥、证书、配对文件
- 构建日志中不包含敏感信息
- 不将 Apple 账户信息存入 GitHub Secrets
- 发现泄漏立即报告并停止

---

## 八、开发阶段计划

> [!IMPORTANT]
> **Phase 0 和 Phase 1 必须优先完成。** 在完整构建链路验证通过之前，不投入业务功能开发。每个 Phase 完成后必须停止，等待用户确认后才能进入下一阶段。

### Phase 0：项目初始化与 Android 审计

**目标**：审计 Android 项目、建立 iOS 项目骨架和文档体系

**任务清单**：

1. 阅读 Android `C:\Dev\Codex\Android\Cost` 的全部文档和关键源码
2. 确认 Android 当前实际实现状态（Phase 20 已完成，schema v10）
3. 在 `C:\Dev\Codex\iPhone\cost` 创建 iOS 项目目录
4. 初始化 Git 仓库 `git init`
5. 创建 `.gitignore`
6. 创建以下文档（内容从 Android 文档提取并适配 iOS）：
   - `AGENTS.md`
   - `docs/PRODUCT_SPEC.md`
   - `docs/ARCHITECTURE.md`
   - `docs/DATA_MODEL.md`
   - `docs/DESIGN_SYSTEM.md`
   - `docs/IMPLEMENTATION_PLAN.md`
   - `docs/DECISIONS.md`（记录 SwiftData → GRDB 等技术决策及理由）
7. 创建 `project.yml`（XcodeGen 配置）
8. 创建最小 Swift 文件使项目结构完整：
   - `Cost/App/CostApp.swift`（空 App 入口）
   - `Cost/App/AppContainer.swift`
   - `Cost/Info.plist`
   - `Cost/Resources/Assets.xcassets`
9. 创建 `CostTests/` 基础测试文件
10. 提交：`docs(phase-0): iOS project foundation and Android audit`

**验收标准**：

- [ ] 6 份文档齐全、与 Android 业务规则一致
- [ ] 项目目录结构完整
- [ ] `.gitignore` 覆盖所有敏感文件
- [ ] `project.yml` 语法正确
- [ ] Git 仓库初始化并完成首次提交

---

### Phase 1：端到端构建链路验证

**目标**：验证 Windows → GitHub → macOS Runner → XcodeGen → Build → IPA 完整链路

**任务清单**：

1. 创建 `.github/workflows/build.yml`
2. `CostApp.swift` 实现最小可运行 App（一个 Text("Cost") 页面）
3. 确保 `project.yml` 包含 GRDB 依赖声明
4. 本地验证 `project.yml` YAML 语法正确
5. 提交并推送到 GitHub 公开仓库
6. 确认 GitHub Actions 成功执行：
   - XcodeGen 生成 .xcodeproj
   - SPM 解析 GRDB 依赖
   - iphonesimulator Build 通过
   - iphoneos Archive 通过
   - IPA 文件生成并上传为 Artifact
7. 如果构建失败，根据日志修复并重新推送
8. 提交：`ci(phase-1): end-to-end build pipeline verified`

**验收标准**：

- [ ] GitHub Actions 全部 green
- [ ] Artifact 中包含有效的 `Cost-unsigned.ipa`
- [ ] IPA 内部结构正确（`Payload/Cost.app/`）
- [ ] 构建日志中无敏感信息

> [!TIP]
> Phase 1 完成后，用户将尝试用 SideStore/Sideloadly 安装 IPA 到真机，验证完整链路的最后一环。此步骤由用户手动完成。

---

### Phase 2：数据层基础

**目标**：实现 GRDB 数据库、核心数据模型、Money 精确数值、Migration 框架

**任务清单**：

1. 实现 `Money` 值对象（minorUnits: Int64, currencyCode: String, scale: Int）
2. 实现 `DecimalRate` 值对象（规范化十进制字符串）
3. 实现 GRDB 数据库初始化与 Migration 框架
4. 创建核心数据库表（对标 Android schema v10）：
   - `currencies`
   - `categories`（含父子关系）
   - `accounts`
   - `tags`
   - `transactions`
   - `transaction_tags`
   - `fiat_fx_cache`
   - `market_price_cache`
   - `quick_templates`
   - `quick_template_tags`
   - `recurring_rules`
   - `recurring_executions`
   - `anomaly_feedback`
   - `account_opening_revisions`
   - `internal_transfers`
5. 实现 seed data（初始 Currency、默认分类、默认账户）
6. 实现 Repository 协议（Core/Domain 层）
7. 实现 GRDB Repository 实现（Core/Data 层）
8. 编写 Money 精度测试（加减乘除、溢出、rescale）
9. 编写 Migration 测试
10. 编写 Repository CRUD 测试

**验收标准**：

- [ ] Money 计算精度测试全部通过
- [ ] DecimalRate 解析不经过 Double
- [ ] Migration 测试通过
- [ ] 基础 CRUD 测试通过
- [ ] GitHub Actions Build + Test 通过

---

### Phase 3：账单、账户、分类、标签管理

**目标**：实现核心记账功能的完整 CRUD

**任务清单**：

1. 实现分类管理 UI（一级/二级、emoji 图标、停用/启用）
2. 实现账户管理 UI（名称、默认账户、停用/启用）
3. 实现标签管理 UI（创建、复用、多对多关联）
4. 实现账单列表页（按日分组、搜索筛选）
5. 实现快速记账页（Bottom Sheet 风格）
   - 金额输入（精确 Decimal）
   - 分类选择
   - 账户选择
   - 日期时间选择
   - 备注和标签
   - 币种选择（默认 CNY）
6. 实现账单编辑和删除（软删除 + 撤销）
7. 主 TabView 导航结构

**验收标准**：

- [ ] 分类/账户/标签 CRUD 功能完整
- [ ] 账单新增 → 列表显示 → 编辑 → 删除 → 撤销 全链路通过
- [ ] 金额精度正确（无 Double 计算）
- [ ] 软删除语义与 Android 一致
- [ ] 用户真机视觉验收

---

### Phase 4：快捷模板

**目标**：实现一键记账和编辑后保存

**任务清单**：

1. 实现模板 CRUD（名称、金额、分类、账户、备注、标签）
2. 一键记账：当前时间 + 模板字段 → 直接创建账单（防重复点击）
3. 编辑后保存：模板预填 → 用户修改 → 创建账单（不回写模板）
4. 模板排序（用户排序优先，结合使用次数和最近使用时间）
5. 模板停用/恢复/删除（删除只移除模板，保留已生成账单）

**验收标准**：

- [ ] 一键记账幂等（快速双击不产生重复）
- [ ] 模板与账单关系正确
- [ ] 排序稳定可测试

---

### Phase 5：周期记账

**目标**：实现周期性交易规则和自动生成

**任务清单**：

1. 实现周期规则 CRUD（频率、起止日期、时区）
2. 实现 occurrence 生成器（唯一 occurrence key 防重复）
3. 使用 `BGAppRefreshTask` 在后台检查并生成到期账单
4. 实现本地通知提醒
5. DST 边界处理（gap → 推进到下一有效时刻，overlap → 选较早 offset）
6. 规则暂停/恢复/删除

> [!WARNING]
> iOS 后台任务不保证准时执行。App 每次前台启动时必须补执行所有漏掉的周期账单。本地通知作为用户提醒，不依赖后台任务一定执行。

**验收标准**：

- [ ] Occurrence key 幂等
- [ ] 时区边界测试通过
- [ ] 前台启动补执行逻辑正确

---

### Phase 6：统计分析

**目标**：实现统计图表和异常开支识别

**任务清单**：

1. SQL 聚合查询（日/月/季/年统计，使用冻结的 convertedBaseMinor）
2. 分类构成饼图（Swift Charts）
3. 趋势折线图
4. 平均日/月/季/年支出
5. 收入与支出对比
6. 环比/同比
7. 异常开支识别（本地稳健统计，周期降权）
8. 异常反馈（用户标记"正常"后不再提醒）

**验收标准**：

- [ ] 统计口径与 Android 完全一致（只聚合冻结金额）
- [ ] 图表数据正确
- [ ] 异常识别可测试

---

### Phase 7：多币种与汇率系统

**目标**：实现完整的多币种记账和 Twelve Data FX Provider

**任务清单**：

1. Twelve Data Forex v2 Provider 实现
   - `/exchange_rate` Latest + Historical
   - `dp=11`, `timezone=UTC`
   - 原始字符串解析为 Decimal，禁止 Double
2. Freshness 策略（provider timestamp + 5 分钟）
3. 缓存（Room/GRDB 本地缓存，keyed mutex 并发去重）
4. 失败处理（429/5xx 指数退避，offline 降级，typed failure）
5. 优先级：实际扣款金额 > 用户手工汇率 > 当天 latest > historical > cached fallback
6. 交易汇率快照冻结（rate 字符串 + 换算金额 + 来源 + 时间戳）
7. 汇率 UI（来源、数据时间、新鲜/过期状态）
8. Keychain 存储 API Key，首次在 Settings 页手动输入
9. 无 Key 时返回 `.notConfigured`，仅手工汇率可用

**验收标准**：

- [ ] Decimal 精度全链路测试通过
- [ ] Freshness 策略正确
- [ ] 离线降级正确
- [ ] 历史账单不随汇率更新变化

---

### Phase 8：数据备份与跨平台兼容

**目标**：实现 JSON/CSV 导入导出，与 Android 备份格式兼容

**任务清单**：

1. 研究 Android `docs/BACKUP_FORMAT.md` 的具体格式
2. 实现 CSV 导出（UTF-8 RFC 4180，与 Android 格式一致）
3. 实现 CSV 导入（Android 导出 → iOS 导入）
4. 实现完整备份导出（ZIP envelope：database.sqlite + settings.json + manifest.json）
5. 实现完整备份导入（staging → 校验 → 原子恢复）
6. 可选密码加密（PBKDF2-HMAC-SHA256 + AES-GCM）
7. 导入导出通过 iOS Files app（UIDocumentPickerViewController）

**验收标准**：

- [ ] Android 备份 → iOS 恢复 数据完整
- [ ] iOS 备份 → Android 恢复 数据完整（需 Android 端配合验证）
- [ ] 加密/解密测试通过
- [ ] 大数据量备份不超时

---

### Phase 9：Liquid Glass 与 UI 精修

**目标**：实现精致的 iOS 原生视觉效果

**任务清单**：

1. Liquid Glass 导航栏和 TabBar（iOS 26 `.glassEffect` 或降级 `.ultraThinMaterial`）
2. 快速记账 Bottom Sheet Glass 效果
3. 浅色/深色主题适配
4. Dynamic Type 全页面适配
5. 触觉反馈（关键操作添加 Haptic）
6. 动画精修（页面转场、Sheet 展开收起、列表操作）
7. SF Symbols 统一替换所有图标
8. App 图标设计（简洁风格）
9. VoiceOver 无障碍标签补全

**验收标准**：

- [ ] 用户真机视觉验收 PASS
- [ ] 深色模式完整
- [ ] Dynamic Type 不破坏布局
- [ ] VoiceOver 可完成核心操作

---

### Phase 10：完整测试与稳定性

**目标**：全量测试、数据恢复测试、长期稳定性

**任务清单**：

1. 补全单元测试覆盖率（Money、Domain、Repository）
2. UI 测试关键路径
3. 数据库 Migration 测试（从 v1 到当前）
4. 备份恢复测试（导出 → 删除 → 恢复 → 验证数据完整）
5. 大数据量性能测试（1000+ 账单）
6. 清理所有编译警告和 lint 问题

**验收标准**：

- [ ] 所有测试通过
- [ ] GitHub Actions 全绿
- [ ] 真机运行 24 小时无崩溃
- [ ] 备份恢复数据 100% 一致

---

## 九、Codex 协作规则

### 9.1 开始任何工作前

1. 阅读本文件和 `docs/` 下相关文档
2. 检查 `git status`、`git diff` 和最近提交
3. 阅读 `docs/IMPLEMENTATION_PLAN.md`，只执行用户指定的一个 Phase
4. 若聊天记录与仓库冲突，以仓库当前代码为准

### 9.2 硬规则

- 金额、汇率、统计计算禁止使用 `Float` / `Double`
- 所有外币交易必须冻结完整汇率快照
- Currency 数据驱动，不在业务代码中写死币种列表
- 默认 offline-first、无广告、无强制注册
- 任何密钥不得提交到仓库
- 复杂业务规则不得写在 SwiftUI View 中
- 每个 Phase 完成后立即停止，不自动进入下一 Phase
- 不允许一次性生成整个 App
- 不允许把未实现的功能描述为已完成

### 9.3 提交规范

格式：`type(scope): summary`

类型：`feat`, `fix`, `docs`, `ci`, `test`, `refactor`, `style`

### 9.4 每 Phase 交付流程

1. 完成实现
2. 运行本 Phase 定义的测试
3. 检查 `git diff` 和修改文件列表
4. 更新 `docs/IMPLEMENTATION_PLAN.md` 状态
5. 创建清晰的 commit
6. 简短汇报：完成内容、核心文件、测试结果、是否需要视觉验收、下一步
7. **停止，等待用户确认**

---

## 十、风险与缓解

| 风险 | 严重程度 | 缓解措施 |
|---|---|---|
| SideStore 7 天签名过期 | 中 | 启用 SideStore 后台刷新；保留 Sideloadly 备用；设日历提醒 |
| iOS 大版本更新导致 SideStore 不兼容 | 高 | 不在第一时间更新 iOS；等待 SideStore 社区适配 |
| GitHub Actions macOS Runner 配置变更 | 低 | 锁定 `macos-15`；监控 GitHub 公告 |
| GRDB 重大 API 变更 | 低 | 锁定版本 `from: "7.0.0"`；有 migration path |
| 无 Xcode Preview 导致 UI 开发效率低 | 中 | 多写 UI 测试；每次 push 后从 CI 截图验证；用户真机验收 |
| 配对文件失效 | 低 | 保留 USB 线和 Sideloadly 备用 |
| Twelve Data API 免费额度耗尽 | 低 | 本地缓存 + 5 分钟 freshness 大幅减少请求 |

---

## 十一、本文档使用方式

1. 将本文档作为 Codex 的主要输入
2. 同时让 Codex 阅读 Android 项目的 `docs/` 文档
3. 告诉 Codex：**"请从 Phase 0 开始执行"**
4. 每个 Phase 完成后，用户验收并确认后再告诉 Codex 进入下一 Phase
5. 如果构建失败，将 GitHub Actions 日志提供给 Codex 修复
