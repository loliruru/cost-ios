import XCTest

final class LedgerUITests: XCTestCase {
    @MainActor
    func launch(largeText: Bool = false, recurringClock: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--cost-ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"] }
        if recurringClock { app.launchArguments.append("--cost-recurring-fixed-clock") }
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
    func testStatisticsUsesFrozenExpenseAndExposesAnomalyControl() {
        let app = launch()
        app.buttons["ledger.add"].tap()
        let amount = app.textFields["entry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.tap()
        amount.typeText("12.34")
        app.buttons["entry.save"].tap()
        let recorded = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledger.row.' AND label CONTAINS '12.34'")).firstMatch
        XCTAssertTrue(recorded.waitForExistence(timeout: 10))
        app.tabBars.buttons["统计"].tap()
        let expense = app.descendants(matching: .any)["statistics.total.expense"].firstMatch
        XCTAssertTrue(expense.waitForExistence(timeout: 10), app.debugDescription)
        let showsExpense = NSPredicate(format: "value == %@", "12.34 CNY")
        let expectation = XCTNSPredicateExpectation(predicate: showsExpense, object: expense)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, expense.debugDescription)
        app.buttons["statistics.anomalies.open"].tap()
        let enabled = app.switches["anomalies.enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 10))
        let control = enabled.switches.firstMatch
        if control.exists {
            control.tap()
        } else {
            enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let disabled = app.descendants(matching: .any)["anomalies.disabled"].firstMatch
        XCTAssertTrue(disabled.waitForExistence(timeout: 10), app.debugDescription)
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

    @MainActor
    func testCategorySortLabelStaysVisibleWithPrefilledValue() {
        let app = launch()
        app.tabBars.buttons["设置"].tap()
        app.buttons["分类"].tap()
        let addCategory = app.buttons["新增分类"]
        XCTAssertTrue(addCategory.waitForExistence(timeout: 10))
        addCategory.tap()

        let order = app.textFields["metadata.sortOrder"]
        let label = app.staticTexts["排序（小的在前）"]
        XCTAssertTrue(order.waitForExistence(timeout: 10))
        XCTAssertEqual(order.value as? String, "0")
        XCTAssertTrue(label.isHittable)

        order.tap()
        order.typeText(XCUIKeyboardKey.delete.rawValue + "10")
        XCTAssertEqual(order.value as? String, "10")
        XCTAssertTrue(label.isHittable)
    }

    @MainActor
    func testTemplateQuickRecordAndUndoFromTemplatesTab() {
        let app = launch()
        app.tabBars.buttons["模板"].tap()
        let addTemplate = app.buttons["template.add"]
        XCTAssertTrue(addTemplate.waitForExistence(timeout: 10))
        addTemplate.tap()

        let name = app.textFields["template.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Lunch template")
        let amount = app.textFields["template.amount"]
        if !amount.isHittable { app.swipeUp() }
        XCTAssertTrue(amount.isHittable)
        amount.tap()
        amount.typeText("12.34")
        app.buttons["template.save"].tap()

        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'template.record.'")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        record.doubleTap()
        let undo = app.buttons["template.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10))

        app.tabBars.buttons["账单"].tap()
        let bills = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledger.row.'"))
        XCTAssertTrue(bills.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(bills.count, 1)
        XCTAssertTrue(bills.firstMatch.label.contains("12.34"))

        app.tabBars.buttons["模板"].tap()
        undo.tap()
        XCTAssertTrue(app.staticTexts["已撤销记账"].waitForExistence(timeout: 10))
        app.tabBars.buttons["账单"].tap()
        XCTAssertTrue(app.staticTexts["暂无账单"].waitForExistence(timeout: 10))
        XCTAssertEqual(bills.count, 0)
    }

    @MainActor
    func testRecurringRuleCreatesBillAndDeletionPreservesIt() {
        let app = launch(recurringClock: true)
        app.tabBars.buttons["设置"].tap()
        app.buttons["recurring.open"].tap()
        let add = app.buttons["recurring.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let name = app.textFields["recurring.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText("Recurring lunch")
        let amount = app.textFields["recurring.amount"]
        if !amount.isHittable { app.swipeUp() }
        XCTAssertTrue(amount.isHittable)
        amount.tap(); amount.typeText("12.34")
        app.buttons["recurring.save"].tap()

        let rule = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'recurring.rule.'")).firstMatch
        XCTAssertTrue(rule.waitForExistence(timeout: 10))
        app.tabBars.buttons["账单"].tap()
        let bills = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledger.row.'"))
        XCTAssertTrue(bills.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(bills.count, 1)
        XCTAssertTrue(bills.firstMatch.label.contains("12.34"))

        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(rule.waitForExistence(timeout: 10))
        rule.tap()
        let delete = app.buttons["删除规则"]
        for _ in 0..<5 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        let confirm = app.buttons["确认删除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["暂无周期规则"].waitForExistence(timeout: 10))
        app.tabBars.buttons["账单"].tap()
        XCTAssertTrue(bills.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(bills.count, 1)
    }
}
