import SwiftUI

struct CostValueRow: View {
    let title: String
    let value: String
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(title).fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 12)
                        valueText.fixedSize(horizontal: true, vertical: false)
                    }
                    stacked
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value))
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            valueText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value).foregroundStyle(.secondary).monospacedDigit()
    }
}

struct CostAdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let content: Content

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout { content }
    }
}

private struct CostSegmentedPicker: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        if typeSize.isAccessibilitySize {
            content.pickerStyle(.menu)
        } else {
            content.pickerStyle(.segmented)
        }
    }
}

extension View {
    func costSegmentedPicker() -> some View { modifier(CostSegmentedPicker()) }
}
