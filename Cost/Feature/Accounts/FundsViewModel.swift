import Foundation
import Observation

@MainActor @Observable
final class FundsViewModel {
    let ledger: LedgerViewModel
    let account: Account?
    let existing: AccountTransfer?
    let id: String
    let requestKey: String
    var enabled = false
    var kind = AccountAmountKind.available
    var code = "CNY"
    var amount = ""
    var from = ""
    var to = ""
    var principal = ""
    var profit = "0"
    var categoryID = ""
    var date = Date()
    var zoneID: String
    var note = ""
    var isBusy = false
    var error: String?
    init(ledger: LedgerViewModel, account: Account? = nil, existing: AccountTransfer? = nil) {
        self.ledger = ledger; self.account = account; self.existing = existing
        id = existing?.id ?? ledger.environment.newID(); requestKey = existing?.requestKey ?? ledger.environment.newID()
        zoneID = existing?.occurredAt.zoneID ?? ledger.environment.zoneID()
        if let account, let position = ledger.positions.first(where: { $0.accountID == account.id }), let opening = position.opening {
            enabled = opening.enabled; kind = opening.kind; code = opening.currencyCode.rawValue
            // A new current value must be entered on every calibration/re-enable.
        }
        if let existing {
            from = existing.fromAccountID; to = existing.toAccountID; code = existing.currencyCode.rawValue
            principal = FundAmount(units: existing.principalMinor, scale: existing.scale).text
            profit = FundAmount(units: existing.profitMinor, scale: existing.scale).text
            categoryID = existing.profitCategoryID ?? ""; note = existing.note ?? ""
            date = Date(timeIntervalSince1970: TimeInterval(existing.occurredAt.epochMillis) / 1000)
        }
    }
    func save() async -> Bool {
        guard !isBusy else { return false }; isBusy = true; defer { isBusy = false }
        let useCase = ManageFundsUseCase(repository: ledger.services.funds, currencies: ledger.services.currencies, environment: ledger.environment)
        do {
            if let account {
                try await useCase.setOpening(accountID: account.id, kind: kind, enabled: enabled, code: code, amount: amount)
            } else {
                _ = try await useCase.saveTransfer(id: id, requestKey: requestKey, from: from, to: to, code: code,
                    principal: principal, profit: profit, categoryID: categoryID.isEmpty ? nil : categoryID,
                    occurredAt: OccurredAt(epochMillis: Int64(date.timeIntervalSince1970 * 1000), zoneID: zoneID), note: note, existing: existing)
            }
            await ledger.reload(); return true
        } catch { self.error = LedgerMessage.text(error); return false }
    }
    func setDeleted(_ deleted: Bool) async -> Bool {
        guard let existing, !isBusy else { return false }; isBusy = true; defer { isBusy = false }
        do {
            try await ledger.services.funds.setTransferDeleted(id: existing.id, deleted: deleted, at: ledger.environment.now())
            await ledger.reload(); return true
        } catch { self.error = LedgerMessage.text(error); return false }
    }
}
