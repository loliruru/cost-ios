import SwiftUI

enum LedgerStyle {
    static let iconKeys = ["tag", "cart", "fork.knife", "car", "house", "heart", "creditcard", "banknote", "briefcase", "gift", "airplane", "wallet"]
    static func symbol(_ key: String) -> String {
        if key == "wallet" { return "wallet.bifold" }
        return iconKeys.contains(key) ? key : "circle.grid.2x2"
    }
    static func amount(_ row: LedgerTransaction) -> String {
        (row.type == .expense ? "−" : "+") + row.original.plainText + " " + row.original.currencyCode.rawValue
    }
    static func day(_ epochDay: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochDay) * 86400))
    }
}

struct LedgerIcon: View {
    let visual: LedgerVisual
    var repository: (any ManagedVisualRepository)? = nil
    var body: some View {
        Group {
            if visual.source == .image, let repository { ManagedPicture(id: visual.iconAssetID, repository: repository, icon: true).frame(width: 36, height: 36).clipShape(.rect(cornerRadius: 8)) }
            else if visual.source == .emoji, let emoji = visual.emoji { Text(emoji) }
            else { Image(systemName: LedgerStyle.symbol(visual.iconKey)) }
        }
        .font(.title3).frame(minWidth: 36, minHeight: 44).accessibilityHidden(true)
    }
}

struct LedgerErrorAlert: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert("未能完成", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
    }
}
extension View {
    func ledgerError(_ message: Binding<String?>) -> some View { modifier(LedgerErrorAlert(message: message)) }
}
