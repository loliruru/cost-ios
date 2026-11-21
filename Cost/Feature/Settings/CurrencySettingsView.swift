import Observation
import SwiftUI

@MainActor @Observable
final class CurrencySettingsModel {
    let ledger: LedgerViewModel
    private(set) var cryptoCurrencies: [Currency] = []
    private(set) var hasKey = false
    private(set) var busy = false
    var error: String?

    init(ledger: LedgerViewModel) { self.ledger = ledger }

    func load() async {
        do {
            cryptoCurrencies = try await ledger.services.currencies.currencies(includeDisabled: true).filter { $0.assetType == .crypto }
            hasKey = try await ledger.services.credentials?.apiKey() != nil
        } catch { self.error = LedgerMessage.text(error) }
    }

    func setKey(_ input: String?) async -> Bool {
        guard !busy, let credentials = ledger.services.credentials else { return false }
        busy = true
        defer { busy = false }
        do {
            try await credentials.setAPIKey(input?.trimmingCharacters(in: .whitespacesAndNewlines))
            hasKey = input != nil
            return true
        } catch { self.error = LedgerMessage.text(error); return false }
    }

    func setCrypto(_ currency: Currency, enabled: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        var changed = currency
        changed.isEnabled = enabled
        do {
            try await ledger.services.currencies.saveCurrency(changed)
            if let index = cryptoCurrencies.firstIndex(where: { $0.code == changed.code }) { cryptoCurrencies[index] = changed }
            await ledger.reload()
        } catch { self.error = LedgerMessage.text(error) }
    }

    func setBase(_ code: CurrencyCode) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await ledger.setBaseCurrency(code) }
        catch { self.error = LedgerMessage.text(error) }
    }
}

struct CurrencySettingsView: View {
    @State private var model: CurrencySettingsModel
    @State private var key = ""
    @State private var pendingBase: CurrencyCode?
    @State private var confirmBase = false
    @State private var confirmRemoval = false

    init(ledger: LedgerViewModel) { _model = State(initialValue: CurrencySettingsModel(ledger: ledger)) }

    var body: some View {
        Form {
            baseSection
            keySection
            cryptoSection
        }
        .disabled(model.busy)
        .navigationTitle("币种与报价")
        .task { await model.load() }
        .onDisappear { key = "" }
        .confirmationDialog("更改本位币会影响之后新建的账单。", isPresented: $confirmBase, titleVisibility: .visible) {
            if let pendingBase { Button("改为 \(pendingBase.rawValue)") { Task { await model.setBase(pendingBase) } } }
        }
        .ledgerError($model.error)
    }

    private var baseSelection: Binding<CurrencyCode?> {
        Binding(get: { model.ledger.baseCurrency?.code }, set: { code in
            pendingBase = code
            confirmBase = code != nil && code != model.ledger.baseCurrency?.code
        })
    }

    private var baseSection: some View {
        Section("本位币") {
            Picker("本位币", selection: baseSelection) {
                ForEach(model.ledger.currencies.filter { $0.assetType == .fiat }, id: \.code) { currency in
                    Text(currency.code.rawValue + " · " + currency.displayName).tag(Optional(currency.code))
                }
            }.accessibilityIdentifier("settings.baseCurrency")
        }
    }

    private var keySection: some View {
        Section {
            LabeledContent("API Key", value: model.hasKey ? "已配置" : "未配置")
            SecureField("输入 API Key", text: $key)
                .textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("settings.quoteKey")
            Button(model.hasKey ? "更新 API Key" : "保存 API Key") {
                Task { if await model.setKey(key) { key = "" } }
            }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if model.hasKey {
                Button("移除 API Key", role: .destructive) { confirmRemoval = true }
                    .confirmationDialog("移除 Twelve Data API Key？", isPresented: $confirmRemoval, titleVisibility: .visible) {
                        Button("移除", role: .destructive) { Task { _ = await model.setKey(nil) } }
                    }
            }
        } header: { Text("Twelve Data") } footer: { Text("密钥保存在此设备的钥匙串。汇率与市场参考价由 Twelve Data 提供。") }
    }

    private var cryptoSection: some View {
        Section {
            ForEach(model.cryptoCurrencies, id: \.code) { currency in
                Toggle(currency.code.rawValue + " · " + currency.displayName, isOn: cryptoEnabled(currency))
                    .accessibilityIdentifier("settings.crypto.\(currency.code.rawValue)")
            }
        } header: { Text("数字货币") } footer: { Text("开启后可在普通账单录入该币种的收支。") }
    }

    private func cryptoEnabled(_ currency: Currency) -> Binding<Bool> {
        Binding(get: { currency.isEnabled }, set: { enabled in
            Task { await model.setCrypto(currency, enabled: enabled) }
        })
    }
}

struct FrozenQuoteRows: View {
    let snapshot: ExchangeRateSnapshot
    var venue: String? = nil

    private var method: String {
        switch snapshot.method {
        case .identity: "同币种"
        case .actualSettlement: "实际结算金额"
        case .manualRate: venue == nil ? "手工汇率" : "实际单价"
        case .latest: "新鲜报价"
        case .historical: "历史报价"
        case .currentFallback: "当前汇率回退"
        case .cachedFallback, .cachedMarketPrice: "过期报价"
        case .marketPrice: "市场参考价"
        }
    }

    var body: some View {
        LabeledContent("每单位原币估值", value: snapshot.rate.text)
        LabeledContent("估值方式", value: method)
        LabeledContent("来源", value: snapshot.providerID)
        if let venue { LabeledContent("市场", value: venue) }
        if let instant = snapshot.dataTimestamp { LabeledContent("数据时间", value: time(instant)) }
        if let instant = snapshot.fetchedAt { LabeledContent("抓取时间", value: time(instant)) }
    }

    private func time(_ instant: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(instant) / 1000).formatted(date: .abbreviated, time: .standard)
    }
}
