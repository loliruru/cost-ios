import SwiftUI

enum LedgerStyle {
    private static let builtInIcons = [
        ("tag", "标签"), ("cart", "购物车"), ("fork.knife", "餐具"), ("car", "汽车"),
        ("house", "房屋"), ("heart", "爱心"), ("creditcard", "银行卡"), ("banknote", "钞票"),
        ("briefcase", "公文包"), ("gift", "礼物"), ("airplane", "飞机"), ("wallet", "钱包"), ("receipt", "收据"),
    ]
    static var iconKeys: [String] { builtInIcons.map { $0.0 } }
    static func iconTitle(_ key: String) -> String {
        builtInIcons.first { $0.0 == key }?.1 ?? "默认图标"
    }
    static func symbol(_ key: String) -> String {
        if key == "wallet" { return "wallet.bifold" }
        return builtInIcons.contains { $0.0 == key } ? key : "circle.grid.2x2"
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
    static func occurred(_ instant: OccurredAt) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: instant.zoneID)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(instant.epochMillis) / 1000))
    }
}

struct LedgerIcon: View {
    let visual: LedgerVisual
    var repository: (any ManagedVisualRepository)? = nil
    var body: some View {
        Group {
            if visual.source == .image, let repository { ManagedPicture(id: visual.iconAssetID, repository: repository, icon: true).frame(width: 36, height: 36).clipShape(.rect(cornerRadius: 8)) }
            else if visual.source == .emoji, let emoji = visual.emoji { Text(emoji) }
            else { Image(systemName: LedgerStyle.symbol(visual.iconKey)).foregroundStyle(Color.accentColor) }
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
