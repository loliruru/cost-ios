# Phase 8 — CSV、完整备份与跨平台恢复

用户于 2026-11-22 确认 Phase 7 通过并批准开始。实现版本为 0.8.0 / build 11。

## 文件交换

- iOS 的「设置 → 导入与备份」提供 Cost CSV 和完整备份的系统 Files 导入与导出。预检给出账单和图片数，完整备份恢复须确认替换。输出先在 App 私有目录完成，再交给系统文件选择器。
- CSV 使用 Android Room 的交易列顺序、UTF-8、RFC 4180、单引号前缀/null 和 JSON 引用资料。账单及标签内容相同才跳过；ID、请求键或元数据冲突使整次合并回滚。账户的空币种保持为空。CSV 保留 emoji，图片用内置图标回退。账户资金、媒体字节、模板及规则经完整备份携带。
- 完整备份输出 Room v10 交换库，按冻结的 Room schema 和 identity 生成 SQLite 元数据。导入支持 v1–v10，按相应 schema 的列重放到受信任的 iOS 私有 staging；旧版缺失列取已审计的默认值。读取外来库时禁用 trusted schema 并拒绝虚拟表；导入源库的视图、触发器和 ORM 元数据不会复制。
- ZIP 输出采用 stored，并支持读取 Android Java 的 raw DEFLATE 和 data descriptor。条目名、局部/中央目录、大小、CRC 和 manifest SHA-256 均检查。PBKDF2 由 CommonCrypto 实现，AES-GCM 由 CryptoKit 实现；Unicode 密码按 Android 的 UTF-16 长度限制及原始 UTF-8 序列派生。使用既有 WebP 格式和编解码方案。 [Apple Compression](https://developer.apple.com/documentation/compression/compression_zlib) [Apple CryptoKit](https://developer.apple.com/documentation/cryptokit/aes/gcm) [ZIP 格式规范](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)
- 全量恢复使用新媒体文件名，仅在一个 GRDB 事务内替换账本并写入设置 outbox。提交前失败保留原账本和原媒体；提交后设置失败由下次启动或周期任务重试。周期运行和恢复共享维护互斥，媒体生命周期沿用独立互斥。iOS 应用本位币、主题和异常设置，其他白名单设置可随完整备份往返。

## 验证

Windows 使用本机 Java 的 JCA 和 ZipOutputStream 配合 Android v1 schema，生成纯合成的 Unicode 密码测试文件。iOS 用例覆盖密钥向量、旧版恢复、CSV 重复与冲突回滚、1,200 笔账单和 WebP、设置重放，以及原生设置入口。当前记录的完成状态以实际 CI 结果为准。

建议使用合成数据在真机试用 Files 的 iCloud 或本机文件夹，核对明文和加密文件、取消和确认流程。Android 应用实际接收 iOS 文件的验证需要独立 Android 测试环境。
