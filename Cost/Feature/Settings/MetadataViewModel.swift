import Foundation
import Observation

enum MetadataKind: String, CaseIterable, Identifiable {
    case category, account, tag
    var id: String { rawValue }
    var title: String { switch self { case .category: "分类"; case .account: "账户"; case .tag: "标签" } }
}
struct MetadataRoute: Identifiable { let id = UUID(); let recordID: String? }

@MainActor @Observable
final class MetadataViewModel {
    let ledger: LedgerViewModel
    let kind: MetadataKind
    let recordID: String?
    var name = ""
    var type = TransactionType.expense
    var parentID = ""
    var currency = ""
    var order = "0"
    var isDefault = false
    var archived = false
    var visual = LedgerVisual()
    var error: String?
    var isBusy = false
    init(ledger: LedgerViewModel, kind: MetadataKind, recordID: String?) {
        self.ledger = ledger; self.kind = kind; self.recordID = recordID
        switch kind {
        case .category:
            if let row = ledger.categories.first(where: { $0.id == recordID }) {
                name = row.name; type = row.type; parentID = row.parentID ?? ""; order = String(row.sortOrder); archived = row.isArchived; visual = row.visual
            }
        case .account:
            visual = LedgerVisual(iconKey: "wallet")
            if let row = ledger.accounts.first(where: { $0.id == recordID }) {
                name = row.name; currency = row.currencyCode?.rawValue ?? ""; order = String(row.sortOrder)
                isDefault = row.isDefault; archived = row.isArchived; visual = row.visual
            }
        case .tag:
            if let row = ledger.tags.first(where: { $0.id == recordID }) { name = row.name; archived = row.isArchived; visual.colorKey = row.colorKey }
        }
    }
    var parents: [Category] { ledger.categories.filter { $0.id != recordID && $0.parentID == nil && $0.type == type && (!$0.isArchived || archived) } }
    func save() async -> Bool {
        guard !isBusy else { return false }; isBusy = true; defer { isBusy = false }
        do {
            let id = recordID ?? ledger.environment.newID()
            let sort = Int64(order)
            guard let sort, name.count <= 120 else { throw LedgerError.invalidField("nameOrOrder") }
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            switch kind {
            case .category:
                let old = ledger.categories.first { $0.id == id }
                try await ledger.services.categories.saveCategory(Category(id: id, name: clean, type: type,
                    parentID: parentID.isEmpty ? nil : parentID, visual: visual, sortOrder: sort, isArchived: archived,
                    createdAt: old?.createdAt ?? ledger.environment.now(), updatedAt: ledger.environment.timestamp(after: old?.updatedAt)))
            case .account:
                let old = ledger.accounts.first { $0.id == id }
                try await ledger.services.accounts.saveAccount(Account(id: id, name: clean,
                    currencyCode: currency.isEmpty ? nil : CurrencyCode(currency), visual: visual, sortOrder: sort,
                    isDefault: isDefault && !archived, isArchived: archived,
                    createdAt: old?.createdAt ?? ledger.environment.now(), updatedAt: ledger.environment.timestamp(after: old?.updatedAt)))
            case .tag:
                let old = ledger.tags.first { $0.id == id }
                _ = try await ledger.services.tags.saveTag(Tag(id: id, name: clean, colorKey: visual.colorKey, isArchived: archived,
                    createdAt: old?.createdAt ?? ledger.environment.now(), updatedAt: ledger.environment.timestamp(after: old?.updatedAt)))
            }
            await ledger.reload()
            return true
        } catch { self.error = LedgerMessage.text(error); return false }
    }
    func delete() async -> Bool {
        guard let recordID, archived, !isBusy else { return false }; isBusy = true; defer { isBusy = false }
        do {
            if kind == .category {
                let result = try await ledger.services.categories.deleteArchivedCategory(id: recordID)
                guard result == .deleted else {
                    error = result == .hasChildren ? "请先处理全部子分类。" : "分类仍被历史账单、模板、循环、转账或反馈引用，不能永久删除。"
                    return false
                }
            } else if kind == .tag {
                guard try await ledger.services.tags.deleteArchivedTag(id: recordID) else { throw LedgerError.conflict }
            } else { return false }
            await ledger.reload(); return true
        } catch { self.error = LedgerMessage.text(error); return false }
    }
}
