//
//  TunnelProbe.swift
//  Shared by the app and the VPNTunnel extension.
//
//  A tiny TCP "can I reach this address, and how does it fail?" test. It exists to answer one question
//  before the heavy work of merging more into this app: can code running INSIDE the VPN extension reach
//  the device's own services through the loopback tunnel, the way the main app can?
//
//  outcome meanings:
//    connected    the TCP handshake completed (reached a listening service)
//    refused      something on this device answered with a reset (the route works, no service on that port)
//    timeout      no answer at all (packets went somewhere else / were dropped)
//    unreachable  the system has no route
//

import Foundation
import Darwin

struct TunnelProbeResult: Codable {
    var label: String
    var outcome: String
    var detail: String
    var ms: Int
}

enum TunnelProbe {
    static func connect(label: String, host: String, port: UInt16,
                        boundInterface: String? = nil, timeout: TimeInterval = 4) -> TunnelProbeResult {
        func fail(_ outcome: String, _ detail: String, since start: Date = Date()) -> TunnelProbeResult {
            TunnelProbeResult(label: label, outcome: outcome, detail: detail,
                              ms: Int(Date().timeIntervalSince(start) * 1000))
        }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return fail("error", "socket() failed: \(String(cString: strerror(errno)))") }
        defer { close(fd) }

        if let boundInterface {
            let index = if_nametoindex(boundInterface)
            guard index != 0 else { return fail("error", "no interface named \(boundInterface)") }
            var value = Int32(index)
            let rc = setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &value, socklen_t(MemoryLayout<Int32>.size))
            guard rc == 0 else { return fail("error", "IP_BOUND_IF failed: \(String(cString: strerror(errno)))") }
        }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return fail("error", "bad address \(host)") }

        let start = Date()
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc == 0 { return fail("connected", "", since: start) }
        let immediate = errno
        if immediate != EINPROGRESS { return classify(immediate, label: label, since: start) }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&pfd, 1, Int32(timeout * 1000))
        if ready == 0 { return fail("timeout", "no reply in \(Int(timeout))s", since: start) }
        if ready < 0 { return fail("error", "poll failed: \(String(cString: strerror(errno)))", since: start) }

        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
        if soError == 0 { return fail("connected", "", since: start) }
        return classify(soError, label: label, since: start)
    }

    private static func classify(_ code: Int32, label: String, since start: Date) -> TunnelProbeResult {
        let outcome: String
        switch code {
        case ECONNREFUSED: outcome = "refused"
        case ENETUNREACH, EHOSTUNREACH, ENETDOWN, EHOSTDOWN: outcome = "unreachable"
        case ETIMEDOUT: outcome = "timeout"
        default: outcome = "error"
        }
        return TunnelProbeResult(label: label, outcome: outcome,
                                 detail: "\(String(cString: strerror(code))) (errno \(code))",
                                 ms: Int(Date().timeIntervalSince(start) * 1000))
    }

    /// Name of the interface (e.g. "utun4") that owns the given IPv4 address.
    static func interfaceName(forAddress target: String) -> String? {
        var wanted = in_addr()
        guard inet_pton(AF_INET, target, &wanted) == 1 else { return nil }
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            if let sa = entry.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET) {
                let match = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    $0.pointee.sin_addr.s_addr == wanted.s_addr
                }
                if match { return String(cString: entry.pointee.ifa_name) }
            }
            cursor = entry.pointee.ifa_next
        }
        return nil
    }

    /// The set of checks run from inside the extension.
    static func runExtensionChecks(port: UInt16) -> [TunnelProbeResult] {
        var results: [TunnelProbeResult] = []
        results.append(connect(label: "extension → 10.7.0.1", host: "10.7.0.1", port: port))
        results.append(connect(label: "extension → 10.7.1.1 (own address)", host: "10.7.1.1", port: port))
        if let iface = interfaceName(forAddress: "10.7.1.1") {
            results.append(connect(label: "extension → 10.7.0.1 via \(iface)", host: "10.7.0.1", port: port, boundInterface: iface))
        } else {
            results.append(TunnelProbeResult(label: "tunnel interface", outcome: "error",
                                             detail: "no interface has 10.7.1.1", ms: 0))
        }
        return results
    }
}
