import XCTest

final class LedgerUITests: XCTestCase {
    @MainActor
    func launch(largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--cost-ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"] }
        app.launch()
        XCTAssertTrue(app.buttons["ledger.add"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor
    func testCreateEditDeleteUndoThroughNativeControls() throws {
        let app = launch()
        app.buttons["ledger.add"].tap()
        let amount = app.textFields["entry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.tap(); amount.typeText("12.34")
        XCTAssertTrue(app.buttons["entry.save"].isHittable)
        app.buttons["entry.save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledger.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); XCTAssertTrue(row.label.contains("12.34"))
        row.tap()
        app.buttons["ledger.edit"].tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.tap(); amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "20.01")
        app.buttons["entry.save"].tap()
        let updated = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledger.row.' AND label CONTAINS '20.01'")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 10))
        updated.tap(); app.buttons["删除账单"].tap(); app.buttons["删除"].tap()
        XCTAssertTrue(app.buttons["撤销删除"].waitForExistence(timeout: 10))
        app.buttons["撤销删除"].tap()
        XCTAssertTrue(updated.waitForExistence(timeout: 10))
    }
    @MainActor
    func testLargeTextDarkModeDraftRecoveryAndAccessibleSave() throws {
        let app = launch(largeText: true)
        app.buttons["ledger.add"].tap()
        let amount = app.textFields["entry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10)); XCTAssertFalse(amount.label.isEmpty)
        amount.tap(); amount.typeText("123.45")
        XCTAssertTrue(app.buttons["entry.save"].isHittable)
        app.buttons["关闭"].tap()
        app.buttons["ledger.add"].tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        XCTAssertEqual(amount.value as? String, "123.45")
        XCTAssertTrue(app.buttons["entry.save"].isHittable)
        app.buttons["entry.save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledger.row.' AND label CONTAINS '123.45'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.isHittable)
    }
}
