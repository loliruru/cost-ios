enum AnomalySensitivity: String, CaseIterable, Identifiable, Sendable {
    case low = "LOW", normal = "NORMAL", high = "HIGH"
    var id: Self { self }

    var spreadFactor: DecimalInteger {
        switch self {
        case .low: DecimalInteger("6")
        case .normal: DecimalInteger("4")
        case .high: DecimalInteger("3")
        }
    }

    var doubleRatio: DecimalInteger {
        switch self {
        case .low: DecimalInteger("6")
        case .normal: DecimalInteger("5")
        case .high: DecimalInteger("4")
        }
    }
}

struct AnomalyPreferences: Equatable, Sendable {
    var enabled = true
    var sensitivity = AnomalySensitivity.normal
}

protocol AnomalyPreferencesRepository: Sendable {
    func load() async -> AnomalyPreferences
    func save(_ preferences: AnomalyPreferences) async
}

enum AnomalyWindow: Int64, CaseIterable, Identifiable, Sendable {
    case week = 7, month = 30
    var id: Self { self }
}

enum AnomalyKind: String, Hashable, Sendable {
    case transaction = "TRANSACTION", day = "DAY", category = "CATEGORY"
}

enum AnomalyFeedbackType: String, Sendable {
    case ignoredOnce = "IGNORED_ONCE", markedNormal = "MARKED_NORMAL"
}

struct AnomalyRequest: Equatable, Sendable {
    let today: Int64
    let window: AnomalyWindow
    let currency: CurrencyCode
    let sensitivity: AnomalySensitivity
    var start: Int64 { today - window.rawValue + 1 }
    var sampleRange: Range<Int64> { (start - 90)..<(today + 1) }
}

struct AnomalyTransaction: Sendable {
    let id: String
    let day: Int64
    let categoryID: String
    let categoryName: String
    let amount: FrozenAmount
}

struct AnomalyDay: Sendable {
    let day: Int64
    let categoryID: String
    let amount: FrozenAmount
}

struct AnomalyFeedback: Sendable {
    static let featureVersion = 1
    let id: String
    let type: AnomalyFeedbackType
    let kind: AnomalyKind
    let categoryID: String?
    let currency: CurrencyCode
    let amount: FrozenAmount
    let version: Int
    let createdAt: Int64
}

struct AnomalyInput: Sendable {
    let transactions: [AnomalyTransaction]
    let daily: [AnomalyDay]
    let feedback: [AnomalyFeedback]
}

protocol AnomalyRepository: Sendable {
    func observeAnomalyInput(_ request: AnomalyRequest) -> AsyncThrowingStream<AnomalyInput, Error>
    func saveAnomalyFeedback(_ feedback: AnomalyFeedback) async throws
    func clearAnomalyFeedback() async throws
}

struct AnomalyFinding: Identifiable, Sendable {
    let id: String
    let day: Int64
    let kind: AnomalyKind
    let categoryID: String?
    let categoryName: String?
    let transactionID: String?
    let currency: CurrencyCode
    let amount: FrozenAmount
    let threshold: FrozenAmount
    let baselineDays: Int64
    let activeSamples: Int

    func feedback(_ type: AnomalyFeedbackType, at timestamp: Int64) -> AnomalyFeedback {
        AnomalyFeedback(id: id, type: type, kind: kind, categoryID: categoryID, currency: currency,
            amount: amount, version: AnomalyFeedback.featureVersion, createdAt: timestamp)
    }
}

struct AnomalyResult: Sendable {
    enum Status: Equatable, Sendable { case ready, insufficientData, sampleLimit }
    let status: Status
    var findings: [AnomalyFinding] = []
    var totalFindings = 0
    var insufficientGroups = 0
}

enum DetectSpendingAnomalies {
    static let sampleLimit = 2_000
    private static let displayLimit = 30
    private static let workingScale = 20

    private struct Sample {
        let day: Int64
        let units: DecimalInteger
        var transactionID: String? = nil
    }

    private struct Group: Hashable {
        let kind: AnomalyKind
        let categoryID: String?
    }

    static func detect(_ request: AnomalyRequest, input: AnomalyInput) -> AnomalyResult {
        guard input.transactions.count <= sampleLimit, input.daily.count <= sampleLimit else {
            return AnomalyResult(status: .sampleLimit)
        }
        var findings: [AnomalyFinding] = []
        var assessed = 0
        var insufficient = 0
        var names: [String: String] = [:]
        let feedback = input.feedback.filter { $0.currency == request.currency }
        let ignored = Set(feedback.lazy.filter { $0.type == .ignoredOnce }.map(\.id))
        let marked = Dictionary(grouping: feedback.filter {
            $0.type == .markedNormal && $0.version == AnomalyFeedback.featureVersion
        }, by: { Group(kind: $0.kind, categoryID: $0.categoryID) }).mapValues { rows in
            rows.map { $0.amount.atScale(workingScale) }.sorted()
        }

        func assess(_ group: Group, samples: [Sample]) {
            let candidates = samples.filter { $0.day >= request.start }
            let history = samples.filter { $0.day < request.start }
            let recent = history.filter { $0.day >= request.start - 30 }
            let days: Int64 = recent.count >= 5 ? 30 : 90
            let baseline = days == 30 ? recent : history
            guard baseline.count >= 5 else {
                if !candidates.isEmpty { insufficient += 1 }
                return
            }
            assessed += 1
            var values = baseline.map(\.units)
            if group.kind != .transaction {
                values.append(contentsOf: repeatElement(.zero, count: Int(days) - baseline.count))
            }
            let threshold = threshold(for: values, sensitivity: request.sensitivity)
            let normal = marked[group] ?? []
            for sample in candidates where sample.units > threshold {
                let suffix = sample.transactionID.map(part) ?? String(sample.day)
                let key = "\(group.kind.rawValue):\(request.currency.rawValue):\(part(group.categoryID)):\(suffix)"
                guard !ignored.contains(key), !isSimilar(sample.units, to: normal) else { continue }
                findings.append(AnomalyFinding(id: key, day: sample.day, kind: group.kind, categoryID: group.categoryID,
                    categoryName: group.categoryID.flatMap { names[$0] }, transactionID: sample.transactionID,
                    currency: request.currency, amount: FrozenAmount(units: sample.units.divided(by: DecimalInteger("100")).quotient, scale: 18),
                    threshold: FrozenAmount(units: threshold, scale: workingScale), baselineDays: days, activeSamples: baseline.count))
            }
        }

        let transactions = Dictionary(grouping: input.transactions.filter { request.sampleRange.contains($0.day) }, by: \.categoryID)
        for (id, rows) in transactions {
            names[id] = rows.first?.categoryName
            assess(Group(kind: .transaction, categoryID: id), samples: rows.map {
                Sample(day: $0.day, units: $0.amount.atScale(workingScale), transactionID: $0.id)
            })
        }
        var categoryDays: [String: [Int64: DecimalInteger]] = [:]
        var days: [Int64: DecimalInteger] = [:]
        for row in input.daily where request.sampleRange.contains(row.day) {
            let amount = row.amount.atScale(workingScale)
            let categoryAmount = categoryDays[row.categoryID]?[row.day] ?? .zero
            categoryDays[row.categoryID, default: [:]][row.day] = categoryAmount.adding(amount)
            days[row.day] = (days[row.day] ?? .zero).adding(amount)
        }
        assess(Group(kind: .day, categoryID: nil), samples: days.map { Sample(day: $0.key, units: $0.value) })
        for (id, totals) in categoryDays {
            assess(Group(kind: .category, categoryID: id), samples: totals.map { Sample(day: $0.key, units: $0.value) })
        }
        findings.sort { $0.day == $1.day ? $0.id < $1.id : $0.day > $1.day }
        return AnomalyResult(status: assessed == 0 ? .insufficientData : .ready,
            findings: Array(findings.prefix(displayLimit)), totalFindings: findings.count, insufficientGroups: insufficient)
    }

    private static func part(_ value: String?) -> String {
        let value = value ?? ""
        return "\(value.utf16.count):\(value)"
    }

    // Values are in 10^-20 major units. Medians and MAD are exact at this precision for inputs
    // with scale <= 18. Flooring each rational threshold preserves strict comparison with an integer.
    private static func threshold(for values: [DecimalInteger], sensitivity: AnomalySensitivity) -> DecimalInteger {
        let sorted = values.sorted()
        let center = median(sorted)
        let active = median(sorted.filter { !$0.isZero })
        let mad = median(sorted.map { $0 < center ? center.subtracting($0) : $0.subtracting(center) }.sorted())
        let iqr = sorted[sorted.count * 3 / 4].subtracting(sorted[sorted.count / 4])
        let factor = sensitivity.spreadFactor
        let ratio = sensitivity.doubleRatio
        let madSpread = mad.multiplied(by: factor).multiplied(by: DecimalInteger("14826"))
            .divided(by: DecimalInteger("10000")).quotient
        let iqrSpread = iqr.multiplied(by: factor).multiplied(by: DecimalInteger("1000"))
            .divided(by: DecimalInteger("1349")).quotient
        let activeFloor = active.multiplied(by: ratio).divided(by: DecimalInteger("2")).quotient
        let meanFloor = sorted.reduce(.zero) { $0.adding($1) }.multiplied(by: ratio)
            .divided(by: DecimalInteger(String(2 * sorted.count))).quotient
        return max(center.adding(max(madSpread, iqrSpread)), max(activeFloor, meanFloor))
    }

    private static func median(_ sorted: [DecimalInteger]) -> DecimalInteger {
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[middle] }
        return sorted[middle - 1].adding(sorted[middle]).divided(by: DecimalInteger("2")).quotient
    }

    private static func isSimilar(_ amount: DecimalInteger, to marked: [DecimalInteger]) -> Bool {
        guard !marked.isEmpty else { return false }
        let scaled = amount.timesPowerOfTen(1)
        var low = 0
        var high = marked.count
        while low < high {
            let middle = low + (high - low) / 2
            if marked[middle].multiplied(by: DecimalInteger("12")) < scaled { low = middle + 1 }
            else { high = middle }
        }
        return low < marked.count && marked[low].multiplied(by: DecimalInteger("8")) <= scaled
    }
}
