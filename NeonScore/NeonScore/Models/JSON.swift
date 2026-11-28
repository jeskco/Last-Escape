import Foundation

/// Forgiving accessor for ESPN's loosely typed JSON. Missing keys never crash; they just return empty values.
struct JSON {
    let value: Any?
    init(_ value: Any?) { self.value = value }

    subscript(_ key: String) -> JSON { JSON((value as? [String: Any])?[key]) }
    subscript(_ index: Int) -> JSON {
        if let a = value as? [Any], a.indices.contains(index) { return JSON(a[index]) }
        return JSON(nil)
    }

    var array: [JSON] { (value as? [Any])?.map { JSON($0) } ?? [] }
    var exists: Bool { value != nil && !(value is NSNull) }
    var string: String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }
    var int: Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }
    var double: Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
    var bool: Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }
    var url: URL? { string.flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) } }
}
