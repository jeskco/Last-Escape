import Foundation
import Compression

/// Minimal .zip extractor (stored + deflate entries) so archives from Sketchfab, CGTrader, Mixamo etc.
/// can be opened directly. Uses Apple's Compression framework (COMPRESSION_ZLIB is raw DEFLATE).
enum ZipReader {
    enum ZipError: LocalizedError {
        case notZip, unsupported(String), corrupt
        var errorDescription: String? {
            switch self {
            case .notZip: return "This isn’t a valid ZIP archive."
            case .unsupported(let s): return "This ZIP uses a feature Rig Viewer can’t read (\(s)). Unzip it in Files and open the model inside."
            case .corrupt: return "This ZIP archive is damaged or incomplete."
            }
        }
    }

    /// Extracts `zip` into `dest`, returning the extracted file URLs.
    static func extract(_ zip: URL, to dest: URL) throws -> [URL] {
        let data = try Data(contentsOf: zip, options: .mappedIfSafe)
        guard data.count >= 22 else { throw ZipError.notZip }
        func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { Int(data[o]) | Int(data[o + 1]) << 8 | Int(data[o + 2]) << 16 | Int(data[o + 3]) << 24 }

        var eocd = -1
        var i = data.count - 22
        let stop = max(0, data.count - 22 - 65_535)
        while i >= stop { if u32(i) == 0x06054b50 { eocd = i; break }; i -= 1 }
        guard eocd >= 0 else { throw ZipError.notZip }
        let entries = u16(eocd + 10)
        var p = u32(eocd + 16)
        if p == 0xFFFF_FFFF || entries == 0xFFFF { throw ZipError.unsupported("ZIP64") }

        let fm = FileManager.default
        let root = dest.standardizedFileURL.path
        var out: [URL] = []
        var total = 0
        for _ in 0..<entries {
            guard p + 46 <= data.count, u32(p) == 0x02014b50 else { throw ZipError.corrupt }
            let flags = u16(p + 8), method = u16(p + 10)
            let compSize = u32(p + 20), size = u32(p + 24)
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
            let local = u32(p + 42)
            guard p + 46 + nameLen <= data.count else { throw ZipError.corrupt }
            let name = String(decoding: data[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self).replacingOccurrences(of: "\\", with: "/")
            p += 46 + nameLen + extraLen + commentLen

            if name.hasSuffix("/") || name.contains("__MACOSX") || name.split(separator: "/").contains(where: { $0 == ".." || $0.hasPrefix("._") }) { continue }
            if flags & 1 != 0 { throw ZipError.unsupported("password protection") }
            guard local + 30 <= data.count, u32(local) == 0x04034b50 else { throw ZipError.corrupt }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + compSize <= data.count else { throw ZipError.corrupt }
            total += size
            if total > 2_000_000_000 { throw ZipError.unsupported("over 2 GB uncompressed") }

            let target = dest.appendingPathComponent(name).standardizedFileURL
            guard target.path.hasPrefix(root) else { continue }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload = data[start..<(start + compSize)]
            switch method {
            case 0:
                try Data(payload).write(to: target)
            case 8:
                var buffer = Data(count: max(size, 1))
                let written = buffer.withUnsafeMutableBytes { dst in
                    payload.withUnsafeBytes { src in
                        compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size,
                                                  src.bindMemory(to: UInt8.self).baseAddress!, compSize, nil, COMPRESSION_ZLIB)
                    }
                }
                guard written == size else { throw ZipError.corrupt }
                try buffer.prefix(size).write(to: target)
            default:
                throw ZipError.unsupported("compression method \(method)")
            }
            out.append(target)
        }
        return out
    }
}
