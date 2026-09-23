import Foundation
import NookPluginSDK

public struct AgentAnswer: Codable, Equatable {
    public var reply: String
    public var action: String?
    public var decision: Bool?
    /// JSON scalar argument map, validated against the currently permitted catalog.
    public var arguments: String
    public init(reply: String, action: String? = nil, arguments: String = "{}", decision: Bool? = nil) { self.reply = reply; self.action = action; self.arguments = arguments; self.decision = decision }
    public func proposal(catalog: [PluginCatalogEntry]) throws -> (PluginCatalogEntry, [String: PluginValue])? {
        guard reply.count <= 16000, arguments.utf8.count <= 8192 else { throw AgentError.message("The proposed response is too large.") }
        guard let action else { return nil }
        guard let entry = catalog.first(where: { $0.address.key == action && $0.action != nil }), let definition = entry.action else { throw AgentError.message("The proposed action is unavailable or not permitted.") }
        let values = try JSONDecoder().decode([String: PluginValue].self, from: Data(arguments.utf8))
        try definition.input.validate(values)
        return (entry, values)
    }
    public static var schema: [String: Any] { [
        "type": "object", "additionalProperties": false, "required": ["reply", "action", "arguments", "decision"],
        "properties": ["reply": ["type": "string"], "action": ["type": ["string", "null"]], "arguments": ["type": "string"], "decision": ["type": ["boolean", "null"]]]
    ] }
    public static func partialReply(_ raw: String) -> String {
        guard raw.utf8.count <= 65536, let range = raw.range(of: #""reply"\s*:\s*""#, options: .regularExpression) else { return "" }
        var encoded = "", escaped = false
        for char in raw[range.upperBound...] {
            if char == "\"", !escaped { break }
            encoded.append(char)
            if escaped { escaped = false } else if char == "\\" { escaped = true }
        }
        // A delta can end in the middle of an escape or a surrogate pair.
        for _ in 0...12 {
            if let decoded = try? JSONDecoder().decode(String.self, from: Data(("\"" + encoded + "\"").utf8)) { return decoded }
            if encoded.isEmpty { return "" }; encoded.removeLast()
        }
        return ""
    }
}
