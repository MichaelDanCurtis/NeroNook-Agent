import Foundation
import NookPluginSDK

public struct AgentAnswer: Codable, Equatable {
    public var reply: String
    public var action: String?
    public var decision: Bool?
    public var delivery: String?
    /// JSON scalar argument map, validated against the currently permitted catalog.
    public var arguments: String
    public init(reply: String, action: String? = nil, arguments: String = "{}", decision: Bool? = nil, delivery: String? = nil) { self.reply = reply; self.action = action; self.arguments = arguments; self.decision = decision; self.delivery = delivery }
    public func proposal(catalog: [PluginCatalogEntry]) throws -> (PluginCatalogEntry, [String: PluginValue])? {
        guard reply.count <= 16000, arguments.utf8.count <= 8192 else { throw AgentError.message("The proposed response is too large.") }
        guard let action else { return nil }
        guard let entry = catalog.first(where: { $0.address.key == action && $0.action != nil }), let definition = entry.action else { throw AgentError.message("The proposed action is unavailable or not permitted.") }
        let values = try JSONDecoder().decode([String: PluginValue].self, from: Data(arguments.utf8))
        try definition.input.validate(values)
        return (entry, values)
    }
    public static var schema: [String: Any] { [
        "type": "object", "additionalProperties": false, "required": ["delivery", "reply", "action", "arguments", "decision"],
        "properties": ["delivery": ["type": ["string", "null"], "enum": ["natural", "gentle", "bright", "reflective", "playful", NSNull()]], "reply": ["type": "string"], "action": ["type": ["string", "null"]], "arguments": ["type": "string"], "decision": ["type": ["boolean", "null"]]]
    ] }
    public static let deliveryInstructions = "For delivery, choose natural, gentle, bright, reflective or playful to describe your own spoken delivery, or null. Emit delivery before reply when possible. A missing or late cue keeps current speech; never delay words for a cue. Respond to the user's stated context without asserting feelings they have not expressed. No flirtation or laughter markup."
    /// A tiny prefix parser, not extraction from arbitrary nested model JSON.
    /// Cue metadata arriving after reply never rewrites an admitted segment.
    public static func streamingDelivery(_ raw: String) -> PluginExpressionCue? {
        guard raw.utf8.count <= 65536 else { return nil }
        var rest = raw[...]
        func trim() { rest = rest.drop(while: { $0.isWhitespace }) }
        trim(); guard rest.first == "{" else { return nil }; rest = rest.dropFirst(); trim()
        guard rest.hasPrefix("\"delivery\"") else { return nil }; rest = rest.dropFirst(10); trim()
        guard rest.first == ":" else { return nil }; rest = rest.dropFirst(); trim()
        guard rest.first == "\"" else { return nil }; rest = rest.dropFirst()
        guard let end = rest.firstIndex(of: "\""), rest[..<end].utf8.count <= 16 else { return nil }
        return PluginExpressionCue.named(String(rest[..<end]))
    }
    public static func partialReply(_ raw: String) -> String {
        streamingReply(raw).text
    }
    public static func streamingReply(_ raw: String) -> (text: String, sealed: Bool) {
        guard raw.utf8.count <= 65536, let range = raw.range(of: #""reply"\s*:\s*""#, options: .regularExpression) else { return ("",false) }
        var encoded = "", escaped = false, sealed = false
        for char in raw[range.upperBound...] {
            if char == "\"", !escaped { sealed = true; break }
            encoded.append(char)
            if escaped { escaped = false } else if char == "\\" { escaped = true }
        }
        // A delta can end in the middle of an escape or a surrogate pair.
        for _ in 0...12 {
            if let decoded = try? JSONDecoder().decode(String.self, from: Data(("\"" + encoded + "\"").utf8)) { return (decoded,sealed) }
            if encoded.isEmpty { return ("",false) }; encoded.removeLast();sealed=false
        }
        return ("",false)
    }
}
