import XCTest

final class LedgerUITests: XCTestCase {
    @MainActor
    func launch(largeText: Bool = false, recurringClock: Bool = false, anomalyFixture: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--cost-ui-testing", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"] }
        if recurringClock { app.launchArguments.append("--cost-recurring-fixed-clock") }
        if anomalyFixture { app.launchArguments.append("--cost-anomaly-fixture") }
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
        let edit = app.buttons["ledger.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.tap(); amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "20.01")
        app.buttons["entry.save"].tap()
        let updated = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledger.row.' AND label CONTAINS '20.01'")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 10))
        updated.tap()
        let delete = app.buttons["删除账单"]
        reveal(delete, in: app)
        delete.tap()
        let confirm = app.buttons.matching(identifier: "ledger.confirmDelete").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        let undo = app.buttons["撤销删除"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        XCTAssertTrue(updated.waitForNonExistence(timeout: 10))

        func toggleDeletedFilter() {
            app.navigationBars.buttons["筛选"].tap()
            let filter = app.switches["ledger.filter.deleted"]
            reveal(filter, in: app)
            let control = filter.switches.firstMatch
            (control.exists ? control : filter).tap()
            app.navigationBars["筛选"].buttons["完成"].tap()
        }

        toggleDeletedFilter()
        XCTAssertTrue(app.navigationBars["已删除账单"].waitForExistence(timeout: 10))
        XCTAssertTrue(updated.waitForExistence(timeout: 10))
        assertLabel(updated, contains: "已删除")
        undo.tap()
        XCTAssertTrue(app.staticTexts["没有已删除账单"].waitForExistence(timeout: 10))
        toggleDeletedFilter()
        XCTAssertTrue(updated.waitForExistence(timeout: 10))
    }

    @MainActor
    func testPortableDataSettingsExposeCSVAndBackupActions() {
        let app = launch()
        app.tabBars.buttons["设置"].tap()
        let link = app.buttons["settings.portable"]
        reveal(link, in: app)
        link.tap()
        XCTAssertTrue(app.buttons["portable.export.csv"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["portable.import.csv"].exists)
        let password = app.secureTextFields["portable.password"]
        reveal(password, in: app)
        XCTAssertTrue(password.exists)
        XCTAssertTrue(app.buttons["portable.export.backup"].exists)
        XCTAssertTrue(app.buttons["portable.import.backup"].exists)
    }

    @MainActor
    func testResetCancelsSafelyAndClearsLedgerAndDefaultMetadataAfterConfirmation() {
        let app = launch()
        app.buttons["ledger.add"].tap()
        let amount = app.textFields["entry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        amount.tap()
        amount.typeText("18.25")
        app.buttons["entry.save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledger.row.' AND label CONTAINS '18.25'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        app.tabBars.buttons["设置"].tap()
        let reset = app.buttons["settings.resetData"]
        reveal(reset, in: app)
        reset.tap()
        let confirmation = app.alerts["清空所有数据？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        confirmation.buttons["取消"].tap()
        app.tabBars.buttons["账单"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        app.tabBars.buttons["设置"].tap()
        reveal(reset, in: app)
        reset.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        let confirmReset = confirmation.buttons.matching(identifier: "settings.confirmReset").firstMatch
        XCTAssertTrue(confirmReset.waitForExistence(timeout: 10))
        confirmReset.tap()
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 10))

        let ledger = app.tabBars.buttons["账单"]
        XCTAssertTrue(ledger.waitForExistence(timeout: 10))
        ledger.tap()
        XCTAssertTrue(app.staticTexts["暂无账单"].waitForExistence(timeout: 10))
        XCTAssertFalse(row.exists)
        app.tabBars.buttons["设置"].tap()
        app.swipeDown()
        app.buttons["分类"].tap()
        XCTAssertTrue(app.staticTexts["暂无分类"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars.buttons["新增分类"].exists)
        app.navigationBars.buttons["设置"].tap()
        app.buttons["账户"].tap()
        XCTAssertTrue(app.staticTexts["暂无账户"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars.buttons["新增账户"].exists)
    }

    @MainActor
    func testForeignEntryWithActualSettlementAndKeySetting() {
        let app = launch()
        app.tabBars.buttons["设置"].tap()
        let settings = app.buttons["settings.quotes"]
        reveal(settings, in: app)
        settings.tap()
        XCTAssertTrue(app.secureTextFields["settings.quoteKey"].waitForExistence(timeout: 10))
        app.tabBars.buttons["账单"].tap()
        app.buttons["ledger.add"].tap()
        let picker = app.buttons["entry.currency"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()
        let usd = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "USD ·")).firstMatch
        XCTAssertTrue(usd.waitForExistence(timeout: 10))
        usd.tap()
        let amount = app.textFields["entry.amount"]
        amount.tap()
        amount.typeText("1.23")
        let actual = app.textFields["entry.actualSettlement"]
        reveal(actual, in: app)
        actual.tap()
        actual.typeText("8.76")
        app.buttons["entry.save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'ledger.row.' AND label CONTAINS 'USD'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let frozen = app.descendants(matching: .any)["ledger.frozenBase"].firstMatch
        reveal(frozen, in: app)
        XCTAssertTrue([frozen.label, frozen.value as? String ?? ""].joined().contains("8.76 CNY"), frozen.debugDescription)
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
        let baselineHint = app.descendants(matching: .any)["anomalies.insufficientBaseline"].firstMatch
        XCTAssertTrue(baselineHint.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(baselineHint.label.contains("之前最多 90 天"), baselineHint.debugDescription)
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
    func testCoverageActionsAndTodayPartialAmountStaySeparateFromFrequency() {
        let app = launch(anomalyFixture: true)
        app.tabBars.buttons["统计"].tap()
        let anomaly = app.buttons["statistics.anomalies.open"]
        XCTAssertTrue(anomaly.waitForExistence(timeout: 10))
        anomaly.tap()
        let provisional = app.descendants(matching: .any)["anomalies.provisional"].firstMatch
        for _ in 0..<4 {
            if provisional.waitForExistence(timeout: 3) { break }
            app.swipeUp()
        }
        assertLabel(provisional, contains: "今日累计")

        let open = app.buttons["coverage.open"]
        reveal(open, in: app)
        open.tap()
        let start = app.buttons["coverage.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let pause = app.buttons["coverage.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        let resume = app.buttons["coverage.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10))
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 10))

        let confirm = app.buttons["coverage.confirmDay"]
        reveal(confirm, in: app)
        confirm.tap()
        let selected = app.descendants(matching: .any)["coverage.selectedDay"].firstMatch
        assertLabel(selected, contains: "该日已确认覆盖")
        app.navigationBars["记账覆盖"].buttons.firstMatch.tap()
        let recent = app.descendants(matching: .any)["frequency.recent"].firstMatch
        reveal(recent, in: app)
        assertLabel(recent, contains: "1 个支出日 · 1 个覆盖日")
        assertLabel(recent, contains: "2026/11/16 至 2026/11/22")

        if !open.isHittable { app.swipeDown() }
        reveal(open, in: app)
        open.tap()
        let unknown = app.buttons["coverage.markUnknown"]
        reveal(unknown, in: app)
        unknown.tap()
        assertLabel(selected, contains: "该日覆盖未知")
        app.navigationBars["记账覆盖"].buttons.firstMatch.tap()
        reveal(recent, in: app)
        assertLabel(recent, contains: "0 个支出日 · 0 个覆盖日")

        let month = app.segmentedControls.buttons["近 30 天"].firstMatch
        for _ in 0..<5 where !month.isHittable { app.swipeDown() }
        XCTAssertTrue(month.isHittable, app.debugDescription)
        month.tap()
        reveal(recent, in: app)
        assertLabel(recent, contains: "2026/10/24 至 2026/11/22")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    @MainActor
    private func assertLabel(_ element: XCUIElement, contains text: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, element.debugDescription)
    }
    @MainActor
    func testNativeAppearanceKeepsNavigationAndSheetReachable() {
        let app = launch()
        let add = app.buttons["ledger.add"]
        XCTAssertTrue(add.label.contains("记一笔"))
        XCTAssertGreaterThanOrEqual(add.frame.height, 44)
        XCTAssertTrue(app.tabBars.buttons["账单"].isSelected)
        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 10))
        app.tabBars.buttons["账单"].tap()
        add.tap()
        let amount = app.textFields["entry.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10))
        XCTAssertTrue(amount.label.contains("金额"))
        XCTAssertTrue(amount.label.contains("CNY"))
        XCTAssertFalse(add.isHittable)
        let save = app.buttons["entry.save"]
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled)
        app.buttons["关闭"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        XCTAssertTrue(add.isHittable)
        XCTAssertFalse(amount.exists)
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
        XCTAssertTrue(row.label.contains("CNY"))
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
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
        let confirm = app.buttons.matching(identifier: "recurring.confirmDelete").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["暂无周期规则"].waitForExistence(timeout: 10))
        app.tabBars.buttons["账单"].tap()
        XCTAssertTrue(bills.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(bills.count, 1)
    }
}
