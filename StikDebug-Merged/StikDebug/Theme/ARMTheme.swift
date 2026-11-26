//
//  ARMTheme.swift
//  An ARMSX2-inspired look for the whole app: near-black navy background with soft colour glows,
//  "Heny Blue" accent, translucent glass cards with 16pt corners.
//

import SwiftUI
import UIKit

enum ARMTheme {
    // Palette
    static let accent = Color(red: 0.24, green: 0.56, blue: 1.0)          // Heny Blue
    static let navyTop = Color(red: 0.063, green: 0.063, blue: 0.145)      // ~#101025, same as the ARMSX2 icon background
    static let navyBottom = Color(red: 0.020, green: 0.020, blue: 0.067)
    static let cardFill = Color.white.opacity(0.07)
    static let cardStroke = Color.white.opacity(0.14)
    static let cornerRadius: CGFloat = 16

    // Colours of the ARMSX2 cube, used for the soft background glows.
    static let glowRed = Color(red: 0.93, green: 0.20, blue: 0.27)
    static let glowOrange = Color(red: 1.00, green: 0.62, blue: 0.10)
    static let glowGreen = Color(red: 0.28, green: 0.80, blue: 0.52)
    static let glowBlue = Color(red: 0.25, green: 0.45, blue: 0.95)

    /// UIKit chrome (navigation bar, tab bar) can't be themed from SwiftUI alone.
    static func configureUIKitAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        nav.backgroundColor = UIColor(navyTop).withAlphaComponent(0.55)
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemChromeMaterialDark)
        tab.backgroundColor = UIColor(navyBottom).withAlphaComponent(0.7)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().tintColor = UIColor(accent)
    }
}

/// Dark navy gradient with four faint glows (red, orange, green, blue) like the ARMSX2 icon.
struct ARMBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [ARMTheme.navyTop, ARMTheme.navyBottom], startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                glow(ARMTheme.glowRed, x: w * 0.85, y: h * 0.05, r: w * 0.55)
                glow(ARMTheme.glowOrange, x: w * 0.05, y: h * 0.30, r: w * 0.50)
                glow(ARMTheme.glowGreen, x: w * 0.95, y: h * 0.62, r: w * 0.50)
                glow(ARMTheme.glowBlue, x: w * 0.10, y: h * 0.95, r: w * 0.60)
            }
        }
        .ignoresSafeArea()
    }

    private func glow(_ color: Color, x: CGFloat, y: CGFloat, r: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(0.16))
            .frame(width: r * 2, height: r * 2)
            .blur(radius: r * 0.45)
            .position(x: x, y: y)
    }
}

struct ARMCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: ARMTheme.cornerRadius, style: .continuous))
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

/// Status + switch for the built-in VPN. Hidden entirely in builds without the extension.
struct VPNStatusCard: View {
    @ObservedObject private var vpn = EmbeddedVPN.shared

    var body: some View {
        if vpn.state == .unavailable {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .shadow(color: color.opacity(0.5), radius: 5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(vpn.state.title).font(.subheadline.weight(.semibold))
                    Text(vpn.detail ?? "Loopback tunnel used to reach your own device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Spacer()
                Button(vpn.state == .on ? "Stop" : "Connect") {
                    vpn.state == .on ? vpn.stop() : vpn.start()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(vpn.state == .connecting)
            }
            .armCard()
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 4)
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
