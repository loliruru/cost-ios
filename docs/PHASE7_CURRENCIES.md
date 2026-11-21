# Phase 7 · 多币种记账

2026-11-21 用户确认 Phase 6 通过并批准 Phase 7。版本为 0.7.0 / build 10。

- 币种和小数位由现有 GRDB 币种表读取。设置支持确认更改启用的法币本位币、手动启用数字货币，以及保存和移除 Twelve Data API Key。Keychain 条目仅限本设备，首次解锁后可供周期任务访问。
- Fiat 优先按实际结算额或手工率，随后按账单业务日使用当天或历史报价。历史响应须匹配请求的 UTC 日期。当前回退和过期报价均需确认。Crypto 优先使用实际结算额或实际单价，当天可主动选取独立市场报价，过去账单用当时的结算额或单价。
- 冻结快照保存精确原币和本位币金额、估值方式、来源、数据时间与抓取时间，Crypto 同时保存币对和市场。只修改类别、备注或标签时沿用原快照。缓存和本位币设置更新只影响后续估值。
- 模板一键记账使用符合时效的法币报价；需要估值确认或服务不可用时打开可编辑草稿。周期规则只自动接受符合日期或时效的法币报价，其他结果保留待重试或跳过。
- 复用已有 `fx_quotes`、`crypto_price_quotes` 和交易快照字段，schema 仍为 v1。HTTPS 传输使用 Authorization 请求头、有界响应和重试。Swift 测试使用固定响应，不要求真实凭据。 [Twelve Data Exchange Rate](https://twelvedata.com/docs/currencies#exchange-rate) · [Crypto endpoints](https://twelvedata.com/exchanges/digital_currency)

## 验证结果

- 2026-11-21，源码 `6076078f0d31894d3af0aa2e5974e2c97f6d9de1` 在 Xcode 16.4、Swift 6.1.2 下通过模拟器构建、113 项 Swift 测试、8 项原生 UI 测试、未签名设备 Archive 和 IPA 打包。Phase 7 用例验证原始十进制、有限重试、缓存与时效、请求取消、历史不可变、Crypto 和一键模板事务。原生 UI 用例验证密钥设置入口与外币实际结算后的冻结金额。 [CI](https://github.com/loliruru/cost-ios/actions/runs/44917768260) · [构建与测试证据](https://github.com/loliruru/cost-ios/actions/runs/44917768260/artifacts/14712943225)
- Windows 静态检查、Android 53 文件只读基线和 6 项 IPA 校验器测试通过。下载的未签名 IPA 为 2,395,805 bytes，arm64 iOS，最低 iOS 18.0。SHA-256 为 `a21a520a9c3f9ebaaaf00603a5b4bb2aa8f67cc090e5340090a32385f1b73944`，与 CI 一致。 [未签名 IPA](https://github.com/loliruru/cost-ios/actions/runs/44917768260/artifacts/14712499492)
- 真实 Twelve Data 契约与设备 Keychain 操作待真机验证。CI 使用注入的测试凭据和固定响应。

## 真机验收

1. 不配置 API Key，录入一笔 USD 账单，分别试手工汇率和实际结算额。看详情中的原币、本位币和来源，再只修改备注并核对快照。
2. 在设置中选择另一种启用的法币并确认。新建账单默认使用这个币种，之前账单保留冻结的本位币。
3. 在设置中启用 BTC，填写实际单价或结算金额记账，核对 8 位原币精度、币对和冻结结果。停用后仍可查看旧账。
4. 如有自己的 API Key，在设置中配置后查询当天及过去的 Fiat 汇率。检查数据时间、抓取时间和回退确认；Crypto 市场参考价在当天主动查询。可同时检查表单在深色模式、大字体和 VoiceOver 下的表现。
