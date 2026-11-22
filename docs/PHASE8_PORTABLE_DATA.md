# Phase 8 — CSV、完整备份与跨平台恢复

用户于 2026-11-22 确认 Phase 7 通过并批准开始。实现版本为 0.8.0 / build 11。

## 文件交换

- iOS 的「设置 → 导入与备份」提供 Cost CSV 和完整备份的系统 Files 导入与导出。预检给出账单和图片数，完整备份恢复须确认替换。输出先在 App 私有目录完成，再交给系统文件选择器。
- CSV 使用 Android Room 的交易列顺序、UTF-8、RFC 4180、单引号前缀/null 和 JSON 引用资料。账单及标签内容相同才跳过。ID、请求键或元数据冲突使整次合并回滚。账户的空币种保持为空。CSV 保留 emoji，图片用内置图标回退。账户资金、媒体字节、模板及规则经完整备份携带。
- 完整备份输出 Room v10 交换库，按冻结的 Room schema 和 identity 生成 SQLite 元数据。导入支持 v1–v10，按相应 schema 的列重放到受信任的 iOS 私有 staging。旧版缺失列取已审计的默认值。读取外来库时禁用 trusted schema 并拒绝虚拟表和 SQLite 内部影子表。重放只复制账本行。
- ZIP 输出采用 stored，并支持读取 Android Java 的 raw DEFLATE 和 data descriptor。条目名、局部/中央目录、大小、CRC 和 manifest SHA-256 均检查。PBKDF2 由 CommonCrypto 实现，AES-GCM 由 CryptoKit 实现。Unicode 密码按 Android 的 UTF-16 长度限制及原始 UTF-8 序列派生。使用既有 WebP 格式和编解码方案。 [Apple Compression](https://developer.apple.com/documentation/compression/compression_zlib) [Apple CryptoKit](https://developer.apple.com/documentation/cryptokit/aes/gcm) [ZIP 格式规范](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)
- 全量恢复使用新媒体文件名，仅在一个 GRDB 事务内替换账本并写入设置 outbox。提交前失败保留原账本和原媒体。提交后设置失败由下次启动或周期任务重试。周期运行和恢复共享维护互斥，媒体生命周期沿用独立互斥。iOS 应用本位币、主题和异常设置，其他白名单设置可随完整备份往返。

## 验证

- Windows 通过 Foundation、数据层和 6 项 IPA 校验器检查。Android 53 份审计文件摘要、HEAD 和 tracked diff 一致。独立 Python 检查验证 Room v10 identity、v1–v10 的列与默认值映射，并复算 Java 的 UTF-8 Unicode 密码向量。
- 2026-11-22，源码 `54aee65461ff3f7e03f5a6ba5ce8392a9a5629bb` 通过模拟器 Build、117 项 Swift 测试、9 项原生 UI 测试和未签名设备 Archive。测试覆盖 Java 加密备份导入、旧版迁移、损坏密文、ZIP 路径和大小、CSV 原子合并、1,202 笔账单、WebP、关联损益、周期防重和设置 outbox。入口 UI 测试验证了 CSV 和完整备份操作与密码控件。 [CI](https://github.com/loliruru/cost-ios/actions/runs/44981029939) [证据](https://github.com/loliruru/cost-ios/actions/runs/44981029939/artifacts/14739130251)
- 在 Windows 下载复核了 0.8.0 / build 11 的未签名 IPA，适用于 arm64 设备，最低 iOS 18.0，共 2,537,207 字节。SHA-256 为 `ecdff639c6af14a64d7f49f8586f739c4273032bd6f6c234cfbc72c8bf4f2183`，与 CI 一致。 [未签名 IPA](https://github.com/loliruru/cost-ios/actions/runs/44981029939/artifacts/14738218848)
- 补充 Swift 测试通过 iOS 加密导出后恢复、每次导出的 salt/nonce 差异，以及注入 SQLite 写入失败后的账本和图片回滚。 [补充 CI](https://github.com/loliruru/cost-ios/actions/runs/44982181912)

## 真机与 Android 验收

2026-11-22 用户确认本阶段通过。以下真机 Files 操作与 Android 应用双向互导未测试。

1. 使用合成账本生成 CSV 和完整备份，通过「设置 → 导入与备份」保存到「我的 iPhone」或 iCloud Drive。
2. 分别导入 CSV 和加密备份，核对预览计数、取消行为、确认替换和密码错误提示。
3. 在独立 Android 测试账本恢复 iOS 导出的文件，核对冻结原币、本位币、业务日期、标签、图片、资金关系和周期执行记录。
