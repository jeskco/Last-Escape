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

/// ARMSX2's own PlayStation 2 menu wallpaper (towers, crystals, orbs and fog), animated behind the whole app.
struct ARMBackground: View {
    var body: some View {
        PlayStation2MenuBackground(theme: .blue)
            .ignoresSafeArea()
            .allowsHitTesting(false)
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
