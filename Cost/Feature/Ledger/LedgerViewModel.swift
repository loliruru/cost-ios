import Foundation
import Observation

struct LedgerServices: Sendable {
    let currencies: any CurrencyRepository
    let categories: any CategoryRepository
    let accounts: any AccountRepository
    let tags: any TagRepository
    let transactions: any TransactionRepository
    let funds: any AccountFundsRepository
    let drafts: any EntryDraftStore
    let visuals: any ManagedVisualRepository
    let templates: any QuickTemplateRepository
    var quotes: QuoteServices? = nil
    var credentials: (any QuoteCredentials)? = nil
    var basePreferences: (any BaseCurrencyPreferences)? = nil
}

enum LedgerMessage {
    static func text(_ error: Error) -> String {
        if let failure = error as? QuoteFailure {
            switch failure {
            case .notConfigured: return "请在设置中添加 Twelve Data API Key，或填写实际结算金额或手工汇率。"
            case .credentialsUnavailable: return "暂时无法访问钥匙串，请解锁设备后重试。"
            case .unauthorized: return "Twelve Data 拒绝访问，请核对 API Key 和币对权限。"
            case .invalidRequest: return "请检查 API Key 格式或币对是否受支持。"
            case .noData: return "此币对或日期暂无报价，可填写实际结算金额或手工汇率。"
            case .offline: return "当前离线，可填写实际结算金额或手工汇率。"
            case .timeout, .unavailable: return "报价服务暂不可用，请重试或填写手工估值。"
            case .rateLimited: return "已达 Twelve Data 请求额度，请稍后重试或填写手工估值。"
            case .malformedResponse: return "报价格式或数据时间无效，可填写手工估值。"
            case .confirmationRequired: return "请选取并确认报价，或填写实际结算金额或手工估值。"
            case .cryptoHistorical: return "过去的数字货币账单请填写当时的实际单价或结算金额。"
            case .futureDate: return "未来日期请填写手工估值。"
            }
        }
        if let error = error as? QuickTemplateError {
            switch error {
            case .unavailable: return "模板已停用或删除。"
            case .categoryUnavailable: return "模板分类不可用或收支类型不匹配，请编辑模板后重试。"
            case .accountUnavailable: return "模板账户已停用或不可用，请编辑模板后重试。"
            case .tagUnavailable: return "模板有已停用或不可用的标签，请编辑模板后重试。"
            case .currencyUnavailable: return "请选择已启用的法币。"
            case .usageOverflow: return "模板使用次数已达上限，账单未保存。"
            }
        }
        if let error = error as? VisualAssetError {
            switch error {
            case .sourceTooLarge: return "原图最多 16 MiB，处理后的图片最多 8 MiB。请选择较小的图片。"
            case .dimensionsTooLarge: return "图片单边最多 16384 像素，总像素最多 4000 万。"
            case .unsupportedImage: return "请选择受支持的静态图片；动画与无法识别的格式不支持。"
            default: return "无法导入或读取图片。已有视觉与账本会保留，请重新选择。"
            }
        }
        if error is NumericError { return "请输入大于零的有效金额，小数位不能超过币种精度。金额超出范围时请减小金额。" }
        if let error = error as? FundsError {
            switch error {
            case .insufficientFunds: return "转出账户资金不足，或操作会使投入成本为负。"
            case .currencyMismatch: return "转账币种与账户资金起点不一致。"
            case .unvaluedTransactions: return "账户存在无法按冻结金额估值的账单，请先核对。"
            case .invalidProfit: return "本金或损益不合法。损益仅适用于投入成本转入可用金额，到账金额不得为负。"
            case .categoryRequired: return "请选择已启用且收支类型匹配的损益分类。"
            case .accountUnavailable: return "请选择不同的已启用账户。"
            case .currencyUnavailable: return "请选择已启用法币。"
            default: return "金额格式或精度不正确，或超出可保存范围。"
            }
        }
        switch error as? LedgerError {
        case .conflict: return "记录已变化，请重新打开后再操作。草稿已保留。"
        case .managedTransaction: return "这笔损益由本金转账管理，请到账户资金中编辑或撤销整笔转账。"
        case .invalidHierarchy: return "分类最多两级，父子收支类型必须相同。恢复子分类前请先恢复父分类。"
        case .invalidSnapshot: return "估值与账单币种、金额或日期不符，请核对后重试。草稿已保留。"
        case .invalidCurrencyType: return "请选择已启用的币种。本位币、模板及周期仅支持法币。"
        case .invalidField("templateOrder"): return "排序请输入整数，或留空使用原有顺序。"
        case .invalidField("templateInput"): return "请填写模板名称和金额，并检查输入长度。"
        case .invalidField: return "请检查必填项、单个 emoji、停用状态及输入长度。"
        default: return "操作未完成，已有账本与草稿会保留。请重试。"
        }
    }
}

@MainActor @Observable
final class LedgerViewModel {
    let services: LedgerServices
    let environment: LedgerEnvironment
    var categories: [Category] = []
    var accounts: [Account] = []
    var tags: [Tag] = []
    var currencies: [Currency] = []
    private(set) var baseCurrency: Currency?
    var rows: [LedgerTransaction] = []
    var positions: [AccountPosition] = []
    var transfers: [AccountTransfer] = []
    var query = LedgerQuery()
    var nextCursor: LedgerCursor?
    var error: String?
    var notice: String?
    var isBusy = false
    var undoID: String?
    @ObservationIgnored private var generation = 0

    init(services: LedgerServices, environment: LedgerEnvironment = LedgerEnvironment(), baseCurrency: Currency? = nil) {
        self.services = services; self.environment = environment
        self.baseCurrency = baseCurrency
    }
    func reload() async {
        generation += 1
        let token = generation
        var filter = query; filter.cursor = nil
        do {
            async let categoryRows = services.categories.categories(includeArchived: true)
            async let accountRows = services.accounts.accounts(includeArchived: true)
            async let tagRows = services.tags.tags(includeArchived: true)
            async let currencyRows = services.currencies.currencies(includeDisabled: false)
            async let base = preferredBaseCurrency(services.basePreferences, in: services.currencies)
            async let page = services.transactions.searchTransactions(filter)
            async let positionRows = services.funds.positions()
            async let transferRows = services.funds.transfers(limit: 200)
            let result = try await (categoryRows, accountRows, tagRows, currencyRows, page, positionRows, transferRows, base)
            guard token == generation, !Task.isCancelled else { return }
            categories = result.0; accounts = result.1; tags = result.2; currencies = result.3
            rows = result.4.rows; nextCursor = result.4.next; positions = result.5; transfers = result.6
            baseCurrency = result.7
        } catch is CancellationError {} catch { if token == generation { self.error = LedgerMessage.text(error) } }
    }
    func refreshAfterRestore() async {
        undoID = nil
        notice = nil
        query = LedgerQuery()
        await reload()
    }
    func loadMore() async {
        guard let nextCursor, !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        let token = generation
        var filter = query; filter.cursor = nextCursor
        do {
            let page = try await services.transactions.searchTransactions(filter)
            guard token == generation else { return }
            let ids = Set(rows.map(\.id)); rows += page.rows.filter { !ids.contains($0.id) }
            self.nextCursor = page.next
        } catch { self.error = LedgerMessage.text(error) }
    }
    func perform(_ work: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        do { try await work(); await reload() }
        catch { self.error = LedgerMessage.text(error) }
    }
    func delete(_ row: LedgerTransaction) async {
        await perform {
            guard try await services.transactions.softDeleteTransaction(id: row.id, at: environment.timestamp(after: row.updatedAt)) else { throw LedgerError.conflict }
            undoID = row.id; notice = "账单已删除，可撤销；也可在已删除账单中恢复。"
        }
    }
    func restore(id: String) async {
        await perform {
            guard let row = try await services.transactions.transaction(id: id),
                  try await services.transactions.restoreTransaction(id: id, at: environment.timestamp(after: row.updatedAt)) else { throw LedgerError.conflict }
            undoID = nil; notice = "账单已恢复"
        }
    }
    func categoryName(_ id: String) -> String { categories.first { $0.id == id }?.name ?? "分类不可用" }
    func setBaseCurrency(_ code: CurrencyCode) async throws {
        guard let preferences = services.basePreferences, let currency = try await services.currencies.currency(code: code),
              currency.isEnabled, currency.assetType == .fiat else { throw LedgerError.invalidCurrencyType }
        await preferences.setBaseCurrencyCode(code.rawValue)
        generation += 1
        baseCurrency = currency
        await reload()
    }
    func accountName(_ id: String) -> String { accounts.first { $0.id == id }?.name ?? "账户不可用" }
    func managed(id: String) async -> Bool? {
        do { return try await services.transactions.isManagedTransaction(id: id) }
        catch { self.error = LedgerMessage.text(error); return nil }
    }
}
