import Testing
import UIKit
@testable import Cost

struct LedgerBuiltInIconTests {
    @Test @MainActor
    func categoryIconsResolveToBundledTemplateImages() {
        let icons = LedgerBuiltInIcon.expenseIcons + LedgerBuiltInIcon.incomeIcons
        #expect(icons.count == 35)
        #expect(Set(icons.map(\.id)).count == icons.count)
        #expect(LedgerBuiltInIcon.option(for: "category-chips")?.title == "薯片")

        for icon in icons {
            let image = UIImage(named: icon.id, in: .main, compatibleWith: nil)
            #expect(image?.renderingMode == .alwaysTemplate, "Missing template image for \(icon.id)")
        }
    }
}
