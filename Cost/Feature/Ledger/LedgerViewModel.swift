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
}

enum LedgerMessage {
    static func text(_ error: Error) -> String {
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
        case .invalidSnapshot: return "当前阶段仅支持本币记账，外币估值将在多币种阶段提供。草稿已保留。"
        case .invalidCurrencyType: return "请选择已启用法币。"
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

    init(services: LedgerServices, environment: LedgerEnvironment = LedgerEnvironment()) {
        self.services = services; self.environment = environment
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
            async let page = services.transactions.searchTransactions(filter)
            async let positionRows = services.funds.positions()
            async let transferRows = services.funds.transfers(limit: 200)
            let result = try await (categoryRows, accountRows, tagRows, currencyRows, page, positionRows, transferRows)
            guard token == generation, !Task.isCancelled else { return }
            categories = result.0; accounts = result.1; tags = result.2; currencies = result.3
            rows = result.4.rows; nextCursor = result.4.next; positions = result.5; transfers = result.6
        } catch is CancellationError {} catch { if token == generation { self.error = LedgerMessage.text(error) } }
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
    func accountName(_ id: String) -> String { accounts.first { $0.id == id }?.name ?? "账户不可用" }
    func managed(id: String) async -> Bool? {
        do { return try await services.transactions.isManagedTransaction(id: id) }
        catch { self.error = LedgerMessage.text(error); return nil }
    }
}
