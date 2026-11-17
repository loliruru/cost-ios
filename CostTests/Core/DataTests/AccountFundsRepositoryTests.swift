import GRDB
import Testing
@testable import Cost

struct AccountFundsRepositoryTests {
    func fixture() async throws -> GRDBLedgerRepository {
        let repository = GRDBLedgerRepository(database: try AppDatabase.inMemory())
        try await repository.saveAccount(Account(id: "invest", name: "投资测试账户", createdAt: 10, updatedAt: 10))
        for (id, kind, amount) in [("seed-default-account", AccountAmountKind.available, Int64(500_000)), ("invest", .investmentCost, Int64(200_000))] {
            _ = try await repository.saveOpening(AccountFundOpening(id: "opening-\(id)", accountID: id, kind: kind, enabled: true,
                currencyCode: CurrencyCode("CNY"), scale: 2, amountMinor: amount, startedAt: 1000, createdAt: 1000))
        }
        return repository
    }
    func transfer(id: String = "transfer", principal: Int64 = 100_000, profit: Int64 = 0, withdrawal: Bool = false, updated: Int64 = 2000, requestKey: String? = nil) throws -> AccountTransfer {
        try AccountTransfer(id: id, requestKey: requestKey ?? "request-\(id)", fromAccountID: withdrawal ? "invest" : "seed-default-account",
            toAccountID: withdrawal ? "seed-default-account" : "invest", fromKind: withdrawal ? .investmentCost : .available,
            toKind: withdrawal ? .available : .investmentCost, currencyCode: CurrencyCode("CNY"), scale: 2,
            principalMinor: principal, profitMinor: profit,
            profitCategoryID: profit == 0 ? nil : (profit > 0 ? "seed-income-other" : "seed-expense-other"), profitTransactionID: nil,
            occurredAt: OccurredAt(epochMillis: 2000, zoneID: "UTC"), note: nil, createdAt: 2000, updatedAt: updated)
    }
    @Test func principalConservationIdempotencyAndPayloadConflict() async throws {
        let repository = try await fixture()
        let row = try transfer()
        _ = try await repository.saveTransfer(row, expectedUpdatedAt: nil)
        let duplicate = try transfer(id: "other")
        let retry = AccountTransfer(id: duplicate.id, requestKey: row.requestKey, fromAccountID: row.fromAccountID, toAccountID: row.toAccountID,
            fromKind: row.fromKind, toKind: row.toKind, currencyCode: row.currencyCode, scale: row.scale,
            principalMinor: row.principalMinor, profitMinor: 0, profitCategoryID: nil, profitTransactionID: nil,
            occurredAt: row.occurredAt, note: nil, createdAt: row.createdAt, updatedAt: row.updatedAt)
        #expect(try await repository.saveTransfer(retry, expectedUpdatedAt: nil).id == row.id)
        let positions = try await repository.positions()
        #expect(positions.first { $0.accountID == "seed-default-account" }?.amount?.text == "4000.00")
        #expect(positions.first { $0.accountID == "invest" }?.amount?.text == "3000.00")
        #expect(try await repository.recentTransactions().isEmpty)
        await #expect(throws: LedgerError.conflict) { _ = try await repository.saveTransfer(row, expectedUpdatedAt: nil) }
    }
    @Test func profitEditZeroDeleteRestoreAndManagedProtection() async throws {
        let repository = try await fixture()
        let first = try await repository.saveTransfer(transfer(profit: 10_000, withdrawal: true), expectedUpdatedAt: nil)
        let profitID = try #require(first.profitTransactionID)
        #expect(try await repository.transaction(id: profitID)?.original.minorUnits == 10_000)
        await #expect(throws: LedgerError.managedTransaction) { _ = try await repository.softDeleteTransaction(id: profitID, at: 3000) }
        try await repository.setTransferDeleted(id: first.id, deleted: true, at: 3000)
        #expect(try await repository.transaction(id: profitID)?.deletedAt == 3000)
        try await repository.setTransferDeleted(id: first.id, deleted: false, at: 4000)
        #expect(try await repository.transaction(id: profitID)?.deletedAt == nil)
        let zero = try transfer(profit: 0, withdrawal: true, updated: 5000)
        let saved = try await repository.saveTransfer(zero, expectedUpdatedAt: 4000)
        #expect(saved.profitTransactionID == profitID)
        #expect(try await repository.transaction(id: profitID)?.deletedAt == 5000)
        let loss = try transfer(profit: -20_000, withdrawal: true, updated: 6000)
        _ = try await repository.saveTransfer(loss, expectedUpdatedAt: 5000)
        let row = try #require(try await repository.transaction(id: profitID))
        #expect(row.type == .expense && row.original.minorUnits == 20_000 && row.deletedAt == nil)
        #expect(try await repository.positions().first { $0.accountID == "seed-default-account" }?.amount?.text == "5800.00")
    }
    @Test func insufficientFundsRollsBackPrincipalAndProfit() async throws {
        let repository = try await fixture()
        await #expect(throws: FundsError.insufficientFunds) {
            _ = try await repository.saveTransfer(transfer(principal: 300_000, profit: 1, withdrawal: true), expectedUpdatedAt: nil)
        }
        #expect(try await repository.transfers().isEmpty)
        #expect(try await repository.recentTransactions().isEmpty)
        #expect(try await repository.positions().first { $0.accountID == "invest" }?.amount?.text == "2000.00")
    }
    @Test func deletingDepositCannotMakeInvestmentCostNegative() async throws {
        let repository = try await fixture()
        let deposit = try await repository.saveTransfer(transfer(), expectedUpdatedAt: nil)
        _ = try await repository.saveTransfer(transfer(id: "withdraw", principal: 250_000, withdrawal: true), expectedUpdatedAt: nil)
        await #expect(throws: FundsError.insufficientFunds) { try await repository.setTransferDeleted(id: deposit.id, deleted: true, at: 3000) }
        #expect(try await repository.transfer(id: deposit.id)?.deletedAt == nil)
    }
    @Test func revisionsResetCutoffWithoutReplayingOldBills() async throws {
        let repository = try await fixture()
        _ = try await repository.createTransaction(TestLedger.transaction(units: 100, occurred: 900))
        #expect(try await repository.positions().first { $0.accountID == "seed-default-account" }?.amount?.text == "5000.00")
        let off = try AccountFundOpening(id: "off", accountID: "seed-default-account", kind: .available, enabled: false,
            currencyCode: CurrencyCode("CNY"), scale: 2, amountMinor: nil, startedAt: 3000, createdAt: 3000)
        #expect(try await repository.saveOpening(off).revision == 2)
        #expect(try await repository.positions().first { $0.accountID == "seed-default-account" }?.amount == nil)
        let zero = try AccountFundOpening(id: "zero", accountID: "seed-default-account", kind: .available, enabled: true,
            currencyCode: CurrencyCode("CNY"), scale: 2, amountMinor: 0, startedAt: 4000, createdAt: 4000)
        #expect(try await repository.saveOpening(zero).revision == 3)
        #expect(try await repository.positions().first { $0.accountID == "seed-default-account" }?.amount?.text == "0.00")
    }
    @Test func failedTransferStorageRollsBackGeneratedProfit() async throws {
        let repository = try await fixture()
        try await repository.database.writer.write { db in try db.execute(sql: "CREATE TRIGGER fail_transfer BEFORE INSERT ON account_transfers BEGIN SELECT RAISE(ABORT,'fixture'); END") }
        await #expect(throws: LedgerError.storageConstraint) { _ = try await repository.saveTransfer(transfer(profit: 100, withdrawal: true), expectedUpdatedAt: nil) }
        #expect(try await repository.recentTransactions().isEmpty)
        #expect(try await repository.transfers().isEmpty)
    }
    @Test func concurrentRetriesCommitOneTransferAndOneProfit() async throws {
        let repository = try await fixture()
        let requests = try (0..<20).map { try transfer(id: "concurrent-\($0)", principal: 100, profit: 10, withdrawal: true, requestKey: "one-transfer") }
        let ids = try await withThrowingTaskGroup(of: String.self) { group in
            for row in requests { group.addTask { try await repository.saveTransfer(row, expectedUpdatedAt: nil).id } }
            var ids = Set<String>()
            for try await id in group { ids.insert(id) }
            return ids
        }
        #expect(ids.count == 1)
        #expect(try await repository.transfers().count == 1)
        #expect(try await repository.recentTransactions().count == 1)
        await #expect(throws: LedgerError.conflict) {
            _ = try await repository.saveTransfer(transfer(id: "conflict", principal: 101, profit: 10, withdrawal: true, requestKey: "one-transfer"), expectedUpdatedAt: nil)
        }
    }
    @Test func currencyMismatchIsAtomicAndUnvaluedEffectsAreReported() async throws {
        let repository = try await fixture()
        let usd = try AccountFundOpening(id: "usd", accountID: "seed-default-account", kind: .available, enabled: true,
            currencyCode: CurrencyCode("USD"), scale: 2, amountMinor: 1000, startedAt: 1000, createdAt: 1000)
        _ = try await repository.saveOpening(usd)
        _ = try await repository.createTransaction(TestLedger.transaction(units: 1, occurred: 2000))
        #expect(try await repository.positions().first { $0.accountID == "seed-default-account" }?.unvaluedCount == 1)
        await #expect(throws: FundsError.currencyMismatch) { _ = try await repository.saveTransfer(transfer(profit: 10, withdrawal: true), expectedUpdatedAt: nil) }
        #expect(try await repository.transfers().isEmpty)
        #expect(try await repository.recentTransactions().count == 1)
    }
}
