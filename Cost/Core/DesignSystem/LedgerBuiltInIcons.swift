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

    static let expenseIcons: [Self] = [
        Self("category-dining", "餐饮"),
        Self("category-meals", "三餐"),
        Self("category-chips", "薯片"),
        Self("category-traffic", "交通"),
        Self("category-metro", "地铁公交"),
        Self("category-taxi", "打车"),
        Self("category-rail", "城际交通"),
        Self("category-home", "住房"),
        Self("category-rent", "房租"),
        Self("category-utilities", "水电燃气"),
        Self("category-hardware", "数码硬件"),
        Self("category-equipment", "设备与核心部件"),
        Self("category-accessories", "配件与维修"),
        Self("category-electronics", "电子制作"),
        Self("category-digital", "数字服务"),
        Self("category-software-ai", "软件与 AI"),
        Self("category-cloud", "云与网络"),
        Self("category-telecom", "通讯"),
        Self("category-entertainment", "娱乐"),
        Self("category-games", "游戏"),
        Self("category-shows", "影音演出"),
        Self("category-collectibles", "收藏周边"),
        Self("category-daily", "日常生活"),
        Self("category-household", "日用百货"),
        Self("category-health", "医疗健康"),
        Self("category-clothes", "服饰"),
        Self("category-finance", "金融费用"),
        Self("category-fees", "手续费"),
        Self("category-investment-loss", "已实现投资损失"),
    ]

    static let incomeIcons: [Self] = [
        Self("category-other-income", "其他收入"),
        Self("category-returns", "回款"),
        Self("category-refund", "退款"),
        Self("category-reimbursements", "分摊与报销"),
        Self("category-salary", "工资奖金"),
        Self("category-investment-gain", "投资收益"),
    ]

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
