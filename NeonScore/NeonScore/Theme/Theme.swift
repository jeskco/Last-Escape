import SwiftUI

enum Neon {
    static let cyan = Color(red: 0.0, green: 0.90, blue: 1.0)
    static let magenta = Color(red: 1.0, green: 0.17, blue: 0.84)
    static let black = Color(red: 0.02, green: 0.02, blue: 0.04)
    static let surface = Color(red: 0.07, green: 0.07, blue: 0.11)
    static let surfaceHigh = Color(red: 0.11, green: 0.11, blue: 0.17)
    static let textDim = Color.white.opacity(0.62)
    static let gradient = LinearGradient(colors: [cyan, magenta], startPoint: .leading, endPoint: .trailing)
}

extension Color {
    init?(hex: String?) {
        guard var h = hex?.trimmingCharacters(in: .whitespaces), !h.isEmpty else { return nil }
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

struct NeonBackground: View {
    var body: some View {
        ZStack {
            Neon.black
            RadialGradient(colors: [Neon.magenta.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 360)
            RadialGradient(colors: [Neon.cyan.opacity(0.14), .clear], center: .bottomLeading, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

struct NeonCard: ViewModifier {
    var highlight = false
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Neon.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(highlight ? AnyShapeStyle(Neon.gradient) : AnyShapeStyle(Color.white.opacity(0.08)), lineWidth: highlight ? 1.4 : 1)
            )
            .shadow(color: highlight ? Neon.magenta.opacity(0.25) : .clear, radius: 10)
    }
}

extension View {
    func neonCard(highlight: Bool = false) -> some View { modifier(NeonCard(highlight: highlight)) }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(Neon.gradient).frame(width: 4, height: 16)
            Text(text.uppercased()).font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(Neon.textDim)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

struct LivePill: View {
    @State private var on = false
    var text = "LIVE"
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Neon.magenta).frame(width: 7, height: 7).opacity(on ? 1 : 0.3)
            Text(text).font(.caption2.weight(.heavy)).foregroundStyle(Neon.magenta)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Neon.magenta.opacity(0.14), in: Capsule())
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { on = true } }
    }
}

struct LogoView: View {
    let url: URL?
    let fallback: String
    var size: CGFloat = 34
    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    default: placeholder
                    }
                }
            } else { placeholder }
        }
        .frame(width: size, height: size)
    }
    private var placeholder: some View {
        Circle().fill(Neon.surfaceHigh)
            .overlay(Text(String(fallback.prefix(3))).font(.system(size: size * 0.3, weight: .bold)).foregroundStyle(Neon.cyan))
    }
}
