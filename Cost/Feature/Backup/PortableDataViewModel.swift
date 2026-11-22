import Foundation
import Observation

@MainActor @Observable
final class PortableDataViewModel {
    private let repository: any PortableDataRepository
    private let onImport: @MainActor (PortableDataKind, PortableDataOutcome) async -> Void
    private let onReset: @MainActor () async -> Void
    private(set) var preview: PortableDataPreview?
    private(set) var busy = false
    private(set) var status: String?
    var error: String?
    private(set) var resetting = false
    private(set) var resetPending = false
    private(set) var resetRevision = 0
    var resetError: String?

    init(repository: any PortableDataRepository,
         onImport: @escaping @MainActor (PortableDataKind, PortableDataOutcome) async -> Void,
         onReset: @escaping @MainActor () async -> Void) {
        self.repository = repository
        self.onImport = onImport
        self.onReset = onReset
    }

    func resetLocalData() async {
        guard !busy, !resetting else { return }
        resetting = true
        resetError = nil
        defer { resetting = false }
        do {
            switch try await repository.resetLocalData() {
            case .complete:
                await onReset()
                resetPending = false
                preview = nil
                status = nil
                error = nil
                resetRevision += 1
            case .cleanupPending:
                resetPending = true
            }
        } catch is CancellationError {} catch {
            resetError = resetPending ? "无法完成清理，请重试。" : "无法清空数据。账本仍保留，请重试。"
        }
    }

    func export(_ kind: PortableDataKind, password: String) async -> URL? {
        guard !busy else { return nil }
        busy = true
        status = nil
        defer { busy = false }
        do { return try await repository.export(kind, password: password) }
        catch is CancellationError { return nil }
        catch { show(error); return nil }
    }

    func finishExport(_ url: URL, saved: Bool) async {
        await repository.discardExport(url)
        if saved { status = "文件已导出。" }
    }

    func prepare(_ url: URL, kind: PortableDataKind, password: String) async -> Bool {
        guard !busy else { return false }
        busy = true
        status = nil
        defer { busy = false }
        await discard()
        do {
            preview = try await repository.prepare(url, kind: kind, password: password)
            return true
        } catch is CancellationError { return false }
        catch { show(error); return false }
    }

    func apply() async {
        guard !busy, let preview else { return }
        self.preview = nil
        busy = true
        defer { busy = false }
        do {
            let outcome = try await repository.confirm(preview.token)
            await onImport(preview.kind, outcome)
            if outcome.settingsPending {
                status = "已恢复 \(outcome.imported) 笔账单。设置尚未应用，下次启动会重试。"
            } else if preview.kind == .backup {
                status = "已恢复 \(outcome.imported) 笔账单和 \(preview.images) 张图片。"
            } else {
                status = "已导入 \(outcome.imported) 笔，跳过 \(outcome.skipped) 笔相同账单。"
            }
        } catch { show(error) }
    }

    func discard() async {
        guard let preview else { return }
        self.preview = nil
        await repository.discard(preview.token)
    }

    private func show(_ failure: Error) {
        switch failure as? PortableDataError {
        case .tooLarge: error = "文件、记录数或图片超过 Cost 数据文件限制。"
        case .invalidPassword: error = "新备份的密码须有 12 至 1024 个 UTF-16 代码单元。"
        case .passwordRequired: error = "这份备份已加密。请输入备份密码，再选择文件。"
        case .authenticationFailed: error = "密码不正确，或加密备份已损坏。"
        case .conflictingRecords: error = "文件与现有记录冲突。此次导入未写入任何记录。"
        case .expiredPreview: error = "预览已失效，请重新选择文件。"
        case .invalidImage: error = "备份中的图片或其校验信息无效。"
        case .unsupportedSchema: error = "这份备份的数据库版本或结构不受支持。"
        case .invalidFormat: error = "文件格式无效，或内容校验失败。"
        default: error = "无法完成操作。请检查文件是否可访问，以及本机储存空间。"
        }
    }
}
