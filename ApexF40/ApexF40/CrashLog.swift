import Foundation
import UIKit

/// Writes a report when the app dies (Swift traps, signals, exceptions) and keeps a trail of the last
/// startup steps, so the next launch can show what happened.
enum CrashLog {
    static let reportURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("last_crash.txt")
    static var wroteException = false
    private static var trail: [String] = []
    private static let lock = NSLock()
    private static var trailText = "" // pre-rendered so the signal handler doesn't allocate much

    static func step(_ s: String) {
        lock.lock()
        trail.append("\(String(format: "%.2f", CACurrentMediaTime())) \(s)")
        if trail.count > 40 { trail.removeFirst(trail.count - 40) }
        trailText = trail.joined(separator: "\n")
        let t = trailText
        lock.unlock()
        if trail.count < 30 { try? t.write(to: trailURL, atomically: true, encoding: .utf8) }
    }

    static let trailURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("last_launch.txt")
    /// The previous launch's trail if it never reached a steady frame (killed without a signal, e.g. out of memory).
    static let previousStall: String? = {
        guard let t = try? String(contentsOf: trailURL, encoding: .utf8) else { return nil }
        return t.contains("frame 600") ? nil : t
    }()

    static func install() {
        _ = previousStall
        NSSetUncaughtExceptionHandler { e in
            CrashLog.wroteException = true
            CrashLog.write("Exception \(e.name.rawValue): \(e.reason ?? "")", stack: e.callStackSymbols)
        }
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            signal(sig) { s in
                if !CrashLog.wroteException { CrashLog.write("Signal \(s)", stack: Thread.callStackSymbols) }
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }

    static func write(_ title: String, stack: [String]) {
        let info = Bundle.main.infoDictionary
        let v = "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        let text = "Apex F40 \(v) · iOS \(UIDevice.current.systemVersion) · \(deviceModel())\n\(title)\nThread: \(Thread.isMainThread ? "main" : (Thread.current.name ?? "background"))\n\n--- Last steps ---\n\(trailText)\n\n--- Stack ---\n\(stack.prefix(40).joined(separator: "\n"))\n"
        try? text.write(to: reportURL, atomically: false, encoding: .utf8)
    }

    static func pending() -> String? {
        if let r = try? String(contentsOf: reportURL, encoding: .utf8) { return r }
        if let t = previousStall { return "Apex F40 · iOS \(UIDevice.current.systemVersion) · \(deviceModel())\nThe app stopped without an error (possibly out of memory).\n\n--- Last steps ---\n\(t)" }
        return nil
    }
    static func clear() { try? FileManager.default.removeItem(at: reportURL) }

    static func deviceModel() -> String {
        var s = utsname(); uname(&s)
        return withUnsafeBytes(of: &s.machine) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
