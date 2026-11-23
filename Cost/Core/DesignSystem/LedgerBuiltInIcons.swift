import SwiftUI

struct LedgerBuiltInIcon: Identifiable, Sendable {
    let id: String
    let title: String
    private let systemName: String?

    private init(_ id: String, _ title: String, systemName: String? = nil) {
        self.id = id
        self.title = title
        self.systemName = systemName
    }

    @MainActor var image: Image {
        if let systemName { return Image(systemName: systemName) }
        return Image(id).renderingMode(.template)
    }

    static let expenseIcons = BuiltInCategoryCatalog.expenses.flatMap(\.items)
        .map { Self($0.iconKey, $0.iconTitle) }

    static let incomeIcons = BuiltInCategoryCatalog.incomes.flatMap(\.items)
        .map { Self($0.iconKey, $0.iconTitle) }

    static let systemIcons: [Self] = [
        ("tag", "标签"), ("cart", "购物车"), ("fork.knife", "餐具"), ("car", "汽车"),
        ("house", "房屋"), ("heart", "爱心"), ("creditcard", "银行卡"), ("banknote", "钞票"),
        ("briefcase", "公文包"), ("gift", "礼物"), ("airplane", "飞机"), ("wallet", "钱包"), ("receipt", "收据"),
    ].map { key, title in
        Self(key, title, systemName: key == "wallet" ? "wallet.bifold" : key)
    }

    private static let byID = Dictionary(uniqueKeysWithValues:
        (expenseIcons + incomeIcons + systemIcons).map { ($0.id, $0) })

    static func option(for key: String) -> Self? { byID[key] }

    @MainActor static func image(for key: String) -> Image {
        option(for: key)?.image ?? Image(systemName: "circle.grid.2x2")
    }
}

struct LedgerBuiltInIconPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            if LedgerBuiltInIcon.option(for: selection) == nil {
                Label("当前图标", systemImage: "circle.grid.2x2").tag(selection)
            }
            Section("支出图标") { options(LedgerBuiltInIcon.expenseIcons) }
            Section("收入图标") { options(LedgerBuiltInIcon.incomeIcons) }
            Section("通用图标") { options(LedgerBuiltInIcon.systemIcons) }
        }
        .pickerStyle(.navigationLink)
    }

    private func options(_ icons: [LedgerBuiltInIcon]) -> some View {
        ForEach(icons) { option in
            Label {
                Text(option.title)
            } icon: {
                option.image
            }
            .tag(option.id)
        }
    }
}
