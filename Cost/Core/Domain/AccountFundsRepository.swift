import Foundation

protocol AccountFundsRepository: Sendable {
    func latestOpening(accountID: String) async throws -> AccountFundOpening?
    func saveOpening(_ opening: AccountFundOpening) async throws -> AccountFundOpening
    func positions() async throws -> [AccountPosition]
    func transfers(limit: Int) async throws -> [AccountTransfer]
    func transfer(id: String) async throws -> AccountTransfer?
    func saveTransfer(_ transfer: AccountTransfer, expectedUpdatedAt: Int64?) async throws -> AccountTransfer
    func setTransferDeleted(id: String, deleted: Bool, at timestamp: Int64) async throws
}
