import Foundation
import CoreFoundation
import NookPluginSDK

/// JSONSerialization alone accepts duplicate object keys. Reject them before
/// decoding model arguments or provider metadata, including escaped spellings.
enum FlowCatalogJSON {
    static func integer(_ object: [String: Any], _ key: String) -> Int? {
        guard let n = object[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue >= 0, n.doubleValue <= 262144,
              n.doubleValue.rounded(.towardZero) == n.doubleValue else { return nil }
        return n.intValue
    }
    static func boolean(_ object: [String: Any], _ key: String) -> Bool? {
        guard let n = object[key] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }; return n.boolValue
    }
    static func object(_ text: String, limit: Int) throws -> [String: Any] {
        guard text.utf8.count <= limit else { throw AgentError.message("Flow JSON exceeds its byte limit.") }
        var scanner = Scanner(bytes: Array(text.utf8))
        try scanner.value(depth: 0); scanner.whitespace()
        guard scanner.index == scanner.bytes.count,
              let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw AgentError.message("Flow JSON must be one complete object.") }
        return object
    }
    static func scalars(_ text: String) throws -> [String: PluginValue] {
        _ = try object(text, limit: 8192)
        return try JSONDecoder().decode([String: PluginValue].self, from: Data(text.utf8))
    }
    private struct Scanner {
        let bytes: [UInt8]
        var index = 0
        mutating func whitespace() { while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
        mutating func take(_ token: UInt8) -> Bool {
            whitespace(); guard index < bytes.count, bytes[index] == token else { return false }; index += 1; return true
        }
        mutating func string() throws -> String {
            whitespace(); let start = index
            guard index < bytes.count, bytes[index] == 34 else { throw bad() }; index += 1
            var escaped = false
            while index < bytes.count {
                let byte = bytes[index]; index += 1
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 {
                    return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index]))
                }
            }
            throw bad()
        }
        mutating func value(depth: Int) throws {
            whitespace(); guard depth <= 64, index < bytes.count else { throw bad() }
            if bytes[index] == 123 {
                index += 1; var names = Set<Data>()
                if take(125) { return }
                repeat {
                    let key = try string()
                    guard names.insert(Data(key.utf8)).inserted, take(58) else { throw bad() }
                    try value(depth: depth + 1)
                    if take(125) { return }
                    guard take(44) else { throw bad() }
                } while true
            } else if bytes[index] == 91 {
                index += 1; if take(93) { return }
                repeat {
                    try value(depth: depth + 1)
                    if take(93) { return }
                    guard take(44) else { throw bad() }
                } while true
            } else if bytes[index] == 34 { _ = try string() }
            else {
                let start = index
                while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                guard index > start else { throw bad() }
                // The full Foundation parse validates number/literal syntax.
            }
        }
        func bad() -> AgentError { .message("Malformed, duplicate-key or over-deep flow JSON.") }
    }
}
