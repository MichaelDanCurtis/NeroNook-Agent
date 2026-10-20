import Foundation

/// Presentation data has its own byte budget. It never changes saved chat or the
/// exact operation held by a pending review.
public enum AgentPresentation {
    public static func prefix(_ text: String, bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        var count = 0, result = ""
        for character in text {
            let next = String(character), size = next.utf8.count
            guard count + size <= bytes else { break }
            result += next; count += size
        }
        return result
    }
    public struct Message: Codable, Equatable {
        public var id: UUID
        public var role: String
        public var text: String
        public var phase: String
        public var context: Bool
        public var activities: [ChatActivity]
        public var excerpt: Bool
        init(_ message: ChatMessage) {
            id = message.id; role = message.role; text = message.text; phase = message.phase
            context = message.context; activities = message.activities; excerpt = false
        }
    }
    public struct Messages {
        public let json: String
        public let omitted: Bool
        public let count: Int
    }
    private static func encoded<T: Encodable>(_ value: T) -> Data { (try? JSONEncoder().encode(value)) ?? Data() }
    public static func messages(_ source: [ChatMessage], budget: Int = 18000) -> Messages {
        let limit = max(512, budget)
        var result: [Message] = [], omitted = false
        for original in source.reversed() {
            var message = Message(original)
            let bounded = prefix(message.text, bytes: 16000)
            message.excerpt = bounded != message.text; message.text = bounded
            if encoded([message] + result).count > limit {
                guard result.isEmpty else { omitted = true; break }
                // The newest answer must remain readable, including Unicode and
                // long spoken replies. Playback bookkeeping is not a UI payload.
                while !message.activities.isEmpty {
                    var metadata = message; metadata.text = ""
                    if encoded([metadata]).count < limit / 2 { break }
                    message.activities.removeFirst(); message.excerpt = true
                }
                let characters = Array(message.text)
                var low = 0, high = characters.count
                message.excerpt = true
                while low < high {
                    let middle = (low + high + 1) / 2
                    message.text = String(characters.prefix(middle))
                    if encoded([message]).count <= limit { low = middle } else { high = middle - 1 }
                }
                message.text = String(characters.prefix(low)); omitted = true
            }
            if message.text.isEmpty, !original.text.isEmpty {
                message.text = "[This message is too large to preview. Copy the full text.]"
                message.excerpt = true
            }
            omitted = omitted || message.excerpt
            result.insert(message, at: 0)
        }
        return Messages(json: String(decoding: encoded(result), as: UTF8.self), omitted: omitted || result.count < source.count, count: result.count)
    }
    public struct Review: Codable, Equatable {
        public let id: UUID
        public let title: String
        public let detail: String
        public let consequence: String
        public let requiresFullReview: Bool
        public let waiting: Int
    }
    public static func reviews(_ pending: [AgentToolReview]) -> [Review] {
        guard let first = pending.first else { return [] }
        let complete = Review(id: first.id, title: first.title, detail: first.detail, consequence: first.consequence, requiresFullReview: false, waiting: pending.count)
        if encoded([complete]).count <= 4000 { return [complete] }
        var detailBudget = 800
        while true {
            let preview = Review(id: first.id, title: prefix(first.title, bytes: 180), detail: prefix(first.detail, bytes: detailBudget), consequence: prefix(first.consequence, bytes: 400), requiresFullReview: true, waiting: pending.count)
            if encoded([preview]).count <= 4000 || detailBudget == 0 { return [preview] }
            detailBudget /= 2
        }
    }
    public static func canApprove(_ id: UUID, pending: [AgentToolReview]) -> Bool {
        reviews(pending).contains { $0.id == id && !$0.requiresFullReview }
    }
}
