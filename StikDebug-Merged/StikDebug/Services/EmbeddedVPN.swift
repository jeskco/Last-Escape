//
//  EmbeddedVPN.swift
//  Controls the built-in loopback VPN (the "VPNTunnel" app extension).
//
//  The tunnel logic is derived from LocalDevVPN by the SideStore Team
//  (StosVPN License, see THIRD_PARTY_NOTICES.md).
//

import Foundation
import NetworkExtension

/// Starts and stops the packet tunnel that is embedded in this app.
///
/// If the extension is not present (a "no VPN" build, or the signing service stripped it)
/// `isAvailable` stays false and callers fall back to the external LocalDevVPN app.
@MainActor
final class EmbeddedVPN: ObservableObject {
    static let shared = EmbeddedVPN()

    enum State: Equatable {
        case unavailable          // extension not embedded / not permitted
        case off
        case connecting
        case on
        case failed(String)

        var title: String {
            switch self {
            case .unavailable: return "Built-in VPN unavailable"
            case .off: return "VPN off"
            case .connecting: return "Connecting…"
            case .on: return "VPN connected"
            case .failed: return "VPN error"
            }
        }
    }

    @Published private(set) var state: State = .off
    @Published private(set) var detail: String?

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    /// Read from the embedded extension itself, so it stays correct even if a signing service renames bundle IDs.
    private var tunnelBundleID: String {
        if let plugins = Bundle.main.builtInPlugInsURL,
           let id = Bundle(url: plugins.appendingPathComponent("VPNTunnel.appex"))?.bundleIdentifier {
            return id
        }
        return (Bundle.main.bundleIdentifier ?? "com.stik.stikdebug") + ".VPNTunnel"
    }

    /// True when the extension is actually inside this app bundle.
    nonisolated var isEmbedded: Bool {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return false }
        let appex = plugins.appendingPathComponent("VPNTunnel.appex")
        return FileManager.default.fileExists(atPath: appex.path)
    }

    private init() {
        if !isEmbedded { state = .unavailable }
    }

    // MARK: - Public API

    func refresh() {
        guard isEmbedded else { state = .unavailable; return }
        Task { await loadManager(createIfNeeded: false) }
    }

    /// Creates the VPN configuration if needed (iOS asks the user once) and starts the tunnel.
    func start() {
        guard isEmbedded else { state = .unavailable; return }
        Task {
            state = .connecting
            guard let manager = await loadManager(createIfNeeded: true) else { return }
            do {
                let options: [String: NSObject] = [
                    TunnelKeys.iface: TunnelKeys.defaultIface as NSObject,
                    TunnelKeys.peer: TunnelKeys.defaultPeer as NSObject,
                ]
                if manager.connection.status == .connected || manager.connection.status == .connecting {
                    apply(manager.connection.status)
                    return
                }
                try manager.connection.startVPNTunnel(options: options)
            } catch {
                state = .failed(error.localizedDescription)
                detail = error.localizedDescription
            }
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    // MARK: - Internals

    @discardableResult
    private func loadManager(createIfNeeded: Bool) async -> NETunnelProviderManager? {
        do {
            let all = try await NETunnelProviderManager.loadAllFromPreferences()
            var found = all.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == tunnelBundleID
            }
            if found == nil {
                guard createIfNeeded else { state = .off; return nil }
                found = try await createManager()
            }
            guard let manager = found else { return nil }
            self.manager = manager
            observe(manager)
            apply(manager.connection.status)
            return manager
        } catch {
            // Most common cause: the signing service did not grant the Network Extension entitlement.
            state = .failed(error.localizedDescription)
            detail = "iOS refused the VPN configuration. If your signing service can't grant Network Extension, use the external LocalDevVPN app instead. (\(error.localizedDescription))"
            return nil
        }
    }

    private func createManager() async throws -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "StikDebug VPN"

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleID
        proto.serverAddress = "StikDebug Local Network Tunnel"
        proto.providerConfiguration = [
            TunnelKeys.iface: TunnelKeys.defaultIface,
            TunnelKeys.peer: TunnelKeys.defaultPeer,
        ]
        manager.protocolConfiguration = proto

        // Same on-demand behaviour as LocalDevVPN: connect when something talks to the tunnel addresses.
        let rule = NEOnDemandRuleEvaluateConnection()
        rule.interfaceTypeMatch = .any
        rule.connectionRules = [NEEvaluateConnectionRule(
            matchDomains: [TunnelKeys.defaultIface.components(separatedBy: "/")[0],
                           TunnelKeys.defaultPeer.components(separatedBy: "/")[0]],
            andAction: .connectIfNeeded
        )]
        manager.onDemandRules = [rule]
        manager.isOnDemandEnabled = true
        manager.isEnabled = true

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()   // required before the first start
        return manager
    }

    private func observe(_ manager: NETunnelProviderManager) {
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: manager.connection, queue: .main
        ) { [weak self] note in
            guard let connection = note.object as? NEVPNConnection else { return }
            Task { @MainActor in self?.apply(connection.status) }
        }
    }

    private func apply(_ status: NEVPNStatus) {
        switch status {
        case .connected:
            state = .on
            detail = nil
            // Reconnect StikDebug's device tunnel now that the loopback exists.
            TunnelManager.shared.restart()
        case .connecting, .reasserting: state = .connecting
        case .disconnecting: state = .connecting
        case .disconnected, .invalid: state = .off
        @unknown default: state = .off
        }
    }

    private enum TunnelKeys {
        static let iface = "TunnelIfaceIP"
        static let peer = "TunnelPeerIP"
        static let defaultIface = "10.7.1.1/32"
        static let defaultPeer = "10.7.0.1/32"
    }
}
