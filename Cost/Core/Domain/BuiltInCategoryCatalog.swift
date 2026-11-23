import Foundation

enum BuiltInCategoryCatalog {
    struct Item: Sendable {
        let id: String
        let name: String
        let iconKey: String
        let iconTitle: String

        init(_ key: String, _ name: String, iconTitle: String? = nil) {
            id = "seed-category-\(key)"
            self.name = name
            iconKey = "category-\(key)"
            self.iconTitle = iconTitle ?? name
        }
    }

    struct Group: Sendable {
        let root: Item
        let children: [Item]
        var items: [Item] { [root] + children }

        init(_ root: Item, _ children: [Item] = []) {
            self.root = root
            self.children = children
        }
    }

    static let expenses: [Group] = [
        Group(Item("dining", "餐饮"), [
            Item("meals", "三餐"),
            Item("chips", "零食饮品", iconTitle: "薯片"),
        ]),
        Group(Item("traffic", "交通"), [
            Item("metro", "地铁公交"),
            Item("taxi", "打车"),
            Item("rail", "城际交通"),
        ]),
        Group(Item("home", "住房"), [
            Item("rent", "房租"),
            Item("utilities", "水电燃气"),
        ]),
        Group(Item("hardware", "数码硬件"), [
            Item("equipment", "设备与核心部件"),
            Item("accessories", "配件与维修"),
            Item("electronics", "电子制作"),
        ]),
        Group(Item("digital", "数字服务"), [
            Item("software-ai", "软件与 AI"),
            Item("cloud", "云与网络"),
            Item("telecom", "通讯"),
        ]),
        Group(Item("entertainment", "娱乐"), [
            Item("games", "游戏"),
            Item("shows", "影音演出"),
            Item("collectibles", "收藏周边"),
        ]),
        Group(Item("daily", "日常生活"), [
            Item("household", "日用百货"),
            Item("health", "医疗健康"),
            Item("clothes", "服饰"),
        ]),
        Group(Item("finance", "金融费用"), [
            Item("fees", "手续费"),
            Item("investment-loss", "已实现投资损失"),
        ]),
    ]

    static let incomes: [Group] = [
        Group(Item("other-income", "其他收入")),
        Group(Item("returns", "回款"), [
            Item("refund", "退款"),
            Item("reimbursements", "分摊与报销"),
        ]),
        Group(Item("salary", "工资奖金")),
        Group(Item("investment-gain", "投资收益")),
    ]

    static func additions(to existing: [Category]) -> [Category] {
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var additions: [Category] = []

        func resolve(_ item: Item, id: String, type: TransactionType, parentID: String?, order: Int64) -> Category? {
            if let stored = byID[id] {
                return stored.type == type && stored.parentID == parentID ? stored : nil
            }
            let name = Tag.normalize(item.name)
            let matches = existing.filter {
                $0.type == type && $0.parentID == parentID && Tag.normalize($0.name) == name
            }
            if !matches.isEmpty { return matches.count == 1 ? matches.first : nil }
            let category = Category(id: id, name: item.name, type: type, parentID: parentID,
                visual: LedgerVisual(iconKey: item.iconKey), sortOrder: order,
                createdAt: 0, updatedAt: 0)
            additions.append(category)
            return category
        }

        let groups: [(TransactionType, [Group])] = [(.expense, expenses), (.income, incomes)]
        var nextOrder: Int64 = 10
        for (type, catalog) in groups {
            for group in catalog {
                let order = nextOrder
                nextOrder += 10
                guard let root = resolve(group.root, id: group.root.id, type: type, parentID: nil, order: order),
                      !root.isArchived else { continue }
                for (offset, item) in group.children.enumerated() {
                    // A reused custom parent gives its children a separate identity in CSV exchanges.
                    let id = root.id == group.root.id ? item.id : "\(item.id):\(root.id)"
                    _ = resolve(item, id: id, type: type, parentID: root.id, order: order + Int64(offset + 1))
                }
            }
        }
        return additions
    }
}
