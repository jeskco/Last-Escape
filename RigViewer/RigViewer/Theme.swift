import SwiftUI

/// Rig Viewer's visual language: deep "ink" canvas, aurora light, bold rounded type, soft cards and springy controls.
enum Theme {
    static let corner: CGFloat = 22
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.78)

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.035, green: 0.04, blue: 0.065) : Color(red: 0.95, green: 0.955, blue: 0.975)
    }
    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.065) : Color.white.opacity(0.82)
    }
    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }
    /// A two-colour gradient built from the accent.
    static func accentGradient(_ a: Color) -> LinearGradient {
        LinearGradient(colors: [a, a.blend(.purple, 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    /// Blend toward another colour (works on iOS 17).
    func blend(_ other: Color, _ t: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1); b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = CGFloat(t)
        return Color(red: Double(r1 + (r2 - r1) * k), green: Double(g1 + (g2 - g1) * k), blue: Double(b1 + (b2 - b1) * k), opacity: Double(a1 + (a2 - a1) * k))
    }
}

// MARK: - Buttons

/// Every tappable thing squishes a little and springs back.
struct Pressable: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == Pressable {
    static var pressable: Pressable { Pressable() }
    static func pressable(_ s: CGFloat) -> Pressable { Pressable(scale: s) }
}

// MARK: - Cards

struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.corner
    var highlighted = false
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(highlighted ? AnyShapeStyle(Color.accentColor.opacity(0.7)) : AnyShapeStyle(Theme.stroke(scheme)), lineWidth: highlighted ? 1.5 : 1)
            )
    }
}

extension View {
    func card(_ radius: CGFloat = Theme.corner, highlighted: Bool = false) -> some View { modifier(CardBackground(radius: radius, highlighted: highlighted)) }

    /// Fades and lifts content in, staggered by `index`.
    func entrance(_ index: Int, shown: Bool) -> some View {
        self.opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .animation(.spring(response: 0.55, dampingFraction: 0.85).delay(Double(index) * 0.05), value: shown)
    }
}

// MARK: - Aurora background

/// Slowly drifting coloured light behind everything. Cheap: radial gradients in a Canvas, ~30 fps.
struct Aurora: View {
    var accent: Color
    var intensity: Double = 1
    var animated = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.ink(scheme)))
                let blobs: [(Color, Double, Double, Double, Double)] = [
                    (accent, 0.18, 0.12, 0.55, 0.0),
                    (accent.blend(.purple, 0.6), 0.88, 0.22, 0.5, 1.7),
                    (Color.teal, 0.72, 0.92, 0.6, 3.1),
                    (accent.blend(.pink, 0.5), 0.12, 0.85, 0.45, 4.4),
                ]
                let dark = scheme == .dark
                for (c, x, y, r, ph) in blobs {
                    let cx = (x + 0.06 * sin(t * 0.11 + ph)) * size.width
                    let cy = (y + 0.05 * cos(t * 0.09 + ph * 1.3)) * size.height
                    let rad = r * max(size.width, size.height) * (1 + 0.06 * sin(t * 0.07 + ph))
                    let alpha = (dark ? 0.34 : 0.22) * intensity
                    let g = Gradient(colors: [c.opacity(alpha), c.opacity(alpha * 0.35), .clear])
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - rad, y: cy - rad, width: rad * 2, height: rad * 2)),
                             with: .radialGradient(g, center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: rad))
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Small components

/// A gradient-filled rounded square holding an SF Symbol (app-icon style).
struct GlyphBadge: View {
    let symbol: String
    var colors: [Color]
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 1))
            .shadow(color: (colors.first ?? .clear).opacity(0.35), radius: size * 0.2, y: size * 0.08)
    }
}

/// Section title in the new style: small caps label + optional trailing action.
struct SectionTitle: View {
    let title: String
    var action: (String, () -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).font(.caption.weight(.heavy)).tracking(1.4).foregroundStyle(.secondary)
            Spacer()
            if let action {
                Button(action.0, action: action.1).font(.caption.weight(.semibold)).buttonStyle(.pressable)
            }
        }
    }
}

/// A scrollable row of icon + label tabs with a sliding highlight.
struct PillTabs<T: Hashable>: View {
    let items: [(T, String, String)]       // value, icon, title
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        let on = item.0 == selection
                        Button {
                            withAnimation(Theme.snappy) { selection = item.0 }
                            Haptics.select()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: item.1).font(.system(size: 13, weight: .semibold))
                                Text(item.2).font(.footnote.weight(.semibold)).fixedSize()
                            }
                            .padding(.horizontal, 13).frame(height: 34)
                            .foregroundStyle(on ? Color.white : Color.primary.opacity(0.75))
                            .background {
                                if on { Capsule().fill(Color.accentColor.gradient).matchedGeometryEffect(id: "pill", in: ns) }
                            }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable(0.93))
                        .id(item.0)
                    }
                }
                .padding(3)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, v in withAnimation(Theme.spring) { proxy.scrollTo(v, anchor: .center) } }
        }
    }
}
