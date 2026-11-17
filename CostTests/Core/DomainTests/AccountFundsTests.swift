import Testing
@testable import Cost

struct AccountFundsTests {
    func opening(kind: AccountAmountKind = .available, enabled: Bool = true, amount: Int64 = 5_000_000) throws -> AccountFundOpening {
        try AccountFundOpening(id: "opening", accountID: "seed-default-account", revision: 1, kind: kind, enabled: enabled,
            currencyCode: CurrencyCode("CNY"), scale: 2, amountMinor: enabled ? amount : nil, startedAt: 1000, createdAt: 1000)
    }
    @Test func cutoffUsesOccurrenceAndCreationAtSameMillisecond() throws {
        let rows = try [TestLedger.transaction(id: "old", units: 123, occurred: 900),
            TestLedger.transaction(id: "same", units: 400, occurred: 1000, created: 1000, updated: 1000),
            TestLedger.transaction(id: "new-same", units: 1, occurred: 1000, created: 1001, updated: 1001),
            TestLedger.transaction(id: "new", units: 2, occurred: 1001)]
        let position = try AccountFundsCalculator.position(accountID: "seed-default-account", opening: opening(), transactions: rows, transfers: [])
        #expect(position.amount?.text == "49999.97")
    }
    @Test func unknownDiffersFromRealZeroAndInvestmentIgnoresBills() throws {
        let row = try TestLedger.transaction()
        #expect(try AccountFundsCalculator.position(accountID: row.accountID, opening: opening(enabled: false), transactions: [row], transfers: []).amount == nil)
        #expect(try AccountFundsCalculator.position(accountID: row.accountID, opening: opening(amount: 0), transactions: [], transfers: []).amount?.text == "0.00")
        #expect(try AccountFundsCalculator.position(accountID: row.accountID, opening: opening(kind: .investmentCost), transactions: [row], transfers: []).amount?.text == "50000.00")
    }
    @Test func frozenOriginalWinsAndDerivedTotalExceedsInt64Exactly() throws {
        let row = try TestLedger.transaction(units: 1, category: "seed-income-other", type: .income)
        let position = try AccountFundsCalculator.position(accountID: row.accountID, opening: opening(amount: .max), transactions: [row], transfers: [])
        #expect(position.amount?.text == "92233720368547758.08")
        let foreign = try TestLedger.transaction(units: 100, code: "USD", rate: "7", baseUnits: 700, method: .manualRate)
        #expect(try AccountFundsCalculator.position(accountID: row.accountID, opening: opening(), transactions: [foreign], transfers: []).amount?.text == "49993.00")
    }
    @Test func signedParsingAndMixedScaleAreExact() throws {
        #expect(try FundAmount.parseMinor("0", scale: 2) == 0)
        #expect(try FundAmount.parseMinor("-1.23", scale: 2, signed: true) == -123)
        for input in ["1.000", "1e2", "NaN", "-1", "92233720368547758.08", String(repeating: "9", count: 200)] {
            #expect(throws: (any Error).self) { try FundAmount.parseMinor(input, scale: 2) }
        }
        var value = FundAmount(units: -1, scale: 0)
        value.add(units: 125, scale: 2)
        #expect(value.text == "0.25")
        value.add(units: 5, scale: 1, subtract: true)
        #expect(value.text == "-0.25")
    }
    @Test func emojiIsOneSequenceAndTagUnicodeNormalizationIsStable() throws {
        for emoji in ["🍜", "👨‍👩‍👧‍👦", "🇸🇬", "1️⃣", "❤️"] { try LedgerVisual(source: .emoji, emoji: emoji).validate() }
        for emoji in ["", "hello", "🍜🍜", "1", "🏽"] { #expect(throws: (any Error).self) { try LedgerVisual(source: .emoji, emoji: emoji).validate() } }
        #expect(Tag.normalize("  ＦＯＯ\u{00A0} BAR\n") == "foo bar")
    }
}
