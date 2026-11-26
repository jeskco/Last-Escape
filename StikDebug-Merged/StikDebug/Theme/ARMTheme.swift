//
//  ARMTheme.swift
//  An ARMSX2-inspired look for the whole app: near-black navy background with soft colour glows,
//  "Heny Blue" accent, translucent glass cards with 16pt corners.
//

import SwiftUI
import UIKit

enum ARMTheme {
    // ARMSX2's PS2-menu look: deep royal blue, translucent glass, "Heny Blue" accent.
    static let accent = Color(red: 0.36, green: 0.62, blue: 1.0)
    static let skyTop = Color(red: 0.10, green: 0.20, blue: 0.62)
    static let skyMid = Color(red: 0.07, green: 0.12, blue: 0.45)
    static let skyBottom = Color(red: 0.02, green: 0.04, blue: 0.22)
    static let cardFill = Color(red: 0.25, green: 0.42, blue: 0.95).opacity(0.28)
    static let cardStroke = Color.white.opacity(0.22)
    static let cornerRadius: CGFloat = 22

    /// Translucent blue glass used behind list rows.
    static var rowBackground: some View {
        RoundedRectangle(cornerRadius: 0)
            .fill(cardFill)
    }

    static func configureUIKitAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        // Floating glass tab bar like ARMSX2's.
        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        tab.backgroundColor = UIColor(skyBottom).withAlphaComponent(0.35)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = UIColor(accent)
    }
}

/// Blue gradient with slowly drifting translucent shapes, in the spirit of ARMSX2's PlayStation 2 menu wallpaper.
struct ARMBackground: View {
    private struct Shape { let x, y, size, speed, phase: Double; let square: Bool }
    private let shapes: [Shape] = (0..<18).map { i in
        let f = Double(i)
        return Shape(x: (f * 0.37).truncatingRemainder(dividingBy: 1),
                     y: (f * 0.61).truncatingRemainder(dividingBy: 1),
                     size: 14 + (f * 7).truncatingRemainder(dividingBy: 40),
                     speed: 0.012 + (f * 0.003).truncatingRemainder(dividingBy: 0.02),
                     phase: f * 1.7, square: i % 3 == 0)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [ARMTheme.skyTop, ARMTheme.skyMid, ARMTheme.skyBottom],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.14), .clear],
                           center: UnitPoint(x: 0.5, y: 0.55), startRadius: 10, endRadius: 420)
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    // soft ribbons
                    for k in 0..<3 {
                        var path = Path()
                        let base = size.height * (0.30 + 0.22 * Double(k))
                        path.move(to: CGPoint(x: 0, y: base))
                        for step in stride(from: 0.0, through: Double(size.width), by: 12) {
                            let y = base + sin(step / 90 + t * 0.25 + Double(k)) * 34
                            path.addLine(to: CGPoint(x: step, y: y))
                        }
                        context.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 26)
                    }
                    for s in shapes {
                        let px = (s.x + sin(t * s.speed * 3 + s.phase) * 0.04) * size.width
                        let py = ((s.y + t * s.speed).truncatingRemainder(dividingBy: 1)) * size.height
                        let rect = CGRect(x: px, y: py, width: s.size, height: s.size)
                        let path = s.square
                            ? Path(roundedRect: rect, cornerRadius: 3)
                            : Path(ellipseIn: rect)
                        context.stroke(path, with: .color(.white.opacity(0.28)), lineWidth: 1.5)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct ARMCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: ARMTheme.cornerRadius, style: .continuous))
            .background(ARMTheme.cardFill, in: RoundedRectangle(cornerRadius: ARMTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ARMTheme.cornerRadius, style: .continuous)
                    .strokeBorder(ARMTheme.cardStroke, lineWidth: 1)
            )
    }
}

extension View {
    /// Applies the ARMSX2-style look app-wide. Call once on the root view.
    func armTheme() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(ARMTheme.accent)
            .scrollContentBackground(.hidden)
            .background(ARMBackground())
    }

    func armCard() -> some View { modifier(ARMCard()) }
}

/// Status + switch for the built-in VPN, shown as the first list section. Hidden in builds without the extension.
struct VPNStatusSection: View {
    @ObservedObject private var vpn = EmbeddedVPN.shared

    var body: some View {
        if vpn.state != .unavailable {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        Circle()
                            .fill(color)
                            .frame(width: 10, height: 10)
                            .shadow(color: color.opacity(0.6), radius: 4)
                        Text(vpn.state.title)
                            .font(.headline)
                        Spacer(minLength: 8)
                        Button(vpn.state == .on ? "Stop" : "Connect") {
                            vpn.state == .on ? vpn.stop() : vpn.start()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(vpn.state == .connecting)
                    }

                    Text(vpn.detail ?? "Loopback tunnel used to reach your own device")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if vpn.state == .on {
                        Button("Test tunnel") { vpn.runProbe() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        if let report = vpn.probeReport {
                            Text(report)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var color: Color {
        switch vpn.state {
        case .on: return .green
        case .connecting: return .orange
        case .failed: return .red
        default: return .gray
        }
    }
}
