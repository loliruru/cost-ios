import Testing
@testable import Cost

struct SnapshotTests {
    @Test
    func incompleteOrInconsistentSnapshotsAreRejected() throws {
        #expect(throws: LedgerError.invalidSnapshot) { try TestLedger.transaction(baseUnits: 1235) }
        #expect(throws: LedgerError.invalidSnapshot) {
            try TestLedger.transaction(code: "USD", rate: "7.25", baseUnits: 1, method: .manualRate)
        }
        let actual = try TestLedger.transaction(code: "USD", rate: "7.25", baseUnits: 7001, method: .actualSettlement)
        #expect(actual.convertedBase.minorUnits == 7001)
        let snapshot = ExchangeRateSnapshot(rate: try DecimalRate("7.25"), providerID: "FIXTURE", dataTimestamp: nil, fetchedAt: nil, method: .latest)
        #expect(throws: LedgerError.invalidSnapshot) { try snapshot.validate() }
    }

    @Test
    func sourceDatesAndDeletionAreValidated() throws {
        #expect(throws: LedgerError.invalidField("sourceID")) { try TestLedger.transaction(source: .template) }
        #expect(throws: LedgerError.invalidField("sourceID")) { try TestLedger.transaction(sourceID: "unexpected") }
        #expect(throws: LedgerError.invalidField("timestamps")) { try TestLedger.transaction(created: 20, updated: 10) }
        #expect(throws: LedgerError.invalidField("timestamps")) { try TestLedger.transaction(deleted: 9) }
        #expect(try OccurredAt(epochMillis: -1, zoneID: "UTC").localEpochDay == -1)
        #expect(try OccurredAt(epochMillis: -1, zoneID: "Asia/Singapore").localEpochDay == 0)
        #expect(throws: LedgerError.invalidField("localEpochDay")) { try OccurredAt(epochMillis: 0, zoneID: "UTC", localEpochDay: 1) }
        #expect(throws: LedgerError.invalidTimeZone) { try OccurredAt(epochMillis: 0, zoneID: "Invalid/Zone") }
    }

    @Test
    func unicodeTagIdentityIsStable() {
        #expect(Tag.normalize("  ＦＯＯ\u{00A0}\u{2003}Bar \n") == "foo bar")
        #expect(Tag.normalize("CAFÉ") == Tag.normalize("Cafe\u{0301}"))
        #expect(Tag.normalize("I") == "i")
    }
}
