import SwiftUI
import UIKit

enum CostControlSurface: Equatable {
    case nativeGlass
    case material
    case opaque

    init(supportsGlass: Bool, reduceTransparency: Bool, increaseContrast: Bool) {
        if reduceTransparency || increaseContrast {
            self = .opaque
        } else {
            self = supportsGlass ? .nativeGlass : .material
        }
    }
}

private struct CostChrome: ViewModifier {
    enum Placement {
        case navigationBar
        case tabBar
        case entrySheet
        case entryButton
    }

    let placement: Placement
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.costLowPower) private var lowPower

    private var surface: CostControlSurface {
        let supportsGlass: Bool
        if #available(iOS 26.0, *) {
            supportsGlass = placement != .entryButton || !lowPower
        } else {
            supportsGlass = false
        }
        return CostControlSurface(supportsGlass: supportsGlass,
            reduceTransparency: reduceTransparency, increaseContrast: contrast == .increased)
    }

    func body(content: Content) -> some View {
        switch placement {
        case .navigationBar: bar(content, at: .navigationBar)
        case .tabBar: bar(content, at: .tabBar)
        case .entrySheet: sheet(content)
        case .entryButton: button(content)
        }
    }

    @ViewBuilder
    private func bar(_ content: Content, at placement: ToolbarPlacement) -> some View {
        switch surface {
        case .nativeGlass: content
        case .material: content.toolbarBackground(.ultraThinMaterial, for: placement)
        case .opaque:
            content
                .toolbarBackground(Color(uiColor: .systemBackground), for: placement)
                .toolbarBackground(.visible, for: placement)
        }
    }

    @ViewBuilder
    private func sheet(_ content: Content) -> some View {
        switch surface {
        case .nativeGlass: content
        case .material: content.presentationBackground(.ultraThinMaterial)
        case .opaque: content.presentationBackground(Color(uiColor: .systemGroupedBackground))
        }
    }

    @ViewBuilder
    private func button(_ content: Content) -> some View {
        if #available(iOS 26.0, *), surface == .nativeGlass {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background {
                if surface == .opaque {
                    Capsule().fill(Color(uiColor: .secondarySystemGroupedBackground))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule().strokeBorder(.primary.opacity(surface == .opaque ? 0.30 : 0.15), lineWidth: 1)
            }
        }
    }
}

extension EnvironmentValues {
    @Entry var costLowPower = false
}

extension View {
    func costNavigationChrome() -> some View { modifier(CostChrome(placement: .navigationBar)) }
    func costTabChrome() -> some View { modifier(CostChrome(placement: .tabBar)) }
    func costEntrySheet() -> some View {
        modifier(CostChrome(placement: .entrySheet))
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
    }
}

struct CostEntryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("记一笔", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minHeight: 48)
                .contentShape(Capsule())
                .modifier(CostChrome(placement: .entryButton))
        }
        .buttonStyle(.plain)
    }
}

enum CostMotion {
    static func ledgerChange(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }
}

@MainActor
enum CostHaptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

#Preview("记账操作") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("交通").font(.headline)
            Text("−12.34 CNY").monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
    .safeAreaInset(edge: .bottom, alignment: .trailing) {
        CostEntryButton {}.padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
