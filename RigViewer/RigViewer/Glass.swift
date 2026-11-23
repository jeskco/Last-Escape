import SwiftUI

/// Liquid Glass when built with the iOS 26 SDK and running on iOS 26; a material fallback otherwise.
extension View {
    @ViewBuilder
    func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.28), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.28), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        #endif
    }

    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule) } else { self.buttonStyle(.bordered).buttonBorderShape(.capsule) }
        }
        #else
        if prominent { self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule) } else { self.buttonStyle(.bordered).buttonBorderShape(.capsule) }
        #endif
    }
}

/// Groups glass shapes so they blend and morph into each other (iOS 26).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content
    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

/// An inset grouped section in the style of Settings, drawn inside a glass panel.
struct Section2<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.headline).padding(.horizontal, 6) }
            VStack(spacing: 0) { content() }
                .background(Color(uiColor: .secondarySystemBackground).opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            if let footer { Text(footer).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 6) }
        }
    }
}

struct Row<Trailing: View>: View {
    let label: String
    var showDivider = true
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(label).lineLimit(1)
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 16).frame(minHeight: 48)
            if showDivider { Divider().padding(.leading, 16) }
        }
    }
}

extension Row where Trailing == Text {
    init(_ label: String, value: String, showDivider: Bool = true) {
        self.label = label; self.showDivider = showDivider
        self.trailing = { Text(value).foregroundStyle(.secondary).monospacedDigit() }
    }
}
