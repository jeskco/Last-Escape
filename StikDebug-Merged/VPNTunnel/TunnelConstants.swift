// Tunnel address constants, same values as LocalDevVPN (SideStore Team, StosVPN License).
import Foundation

struct TunnelConstants {
    static let ifaceIPConfigurationKey = "TunnelIfaceIP"
    static let peerIPConfigurationKey = "TunnelPeerIP"

    static let defaultIfaceIP = "10.7.1.1/32"
    static let defaultPeerIP = "10.7.0.1/32"
    static let defaultAllowIntermediateAddresses = true
}
