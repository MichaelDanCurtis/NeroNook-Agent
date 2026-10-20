import Foundation

public struct ChatActivity: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var phase: String
    public init(id: String = UUID().uuidString, title: String, phase: String = "running") { self.id = id; self.title = title; self.phase = phase }
}
public struct ChatMessage: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var role: String
    public var text: String
    public var phase: String
    public var voiceHeard: String?
    public var voiceInterrupted: Bool?
    public var context: Bool
    public var activities: [ChatActivity] = []
    public init(role: String, text: String, phase: String = "complete", context: Bool = false) { self.role = role; self.text = text; self.phase = phase; self.context = context }
}
public struct Conversation: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var title = "New conversation"
    public var updated = Date()
    public var messages: [ChatMessage] = []
    public init() {}
    public mutating func begin(_ text: String, context: Bool) -> UUID {
        if messages.isEmpty { title = String(text.prefix(48)) }
        messages.append(.init(role: "user", text: text, context: context))
        let reply = ChatMessage(role: "assistant", text: "", phase: "working", context: context)
        messages.append(reply); messages = Array(messages.suffix(40)); updated = Date()
        return reply.id
    }
    public mutating func update(_ id: UUID, text: String? = nil, phase: String? = nil, activity: ChatActivity? = nil) {
        guard let i = messages.firstIndex(where: { $0.id == id && $0.role == "assistant" }) else { return }
        if let text { messages[i].text = String(text.prefix(16000)) }
        if let phase { messages[i].phase = phase }
        if let activity {
            messages[i].activities.removeAll { $0.id == activity.id }; messages[i].activities.append(activity)
            messages[i].activities = Array(messages[i].activities.suffix(16))
        }
        updated = Date()
    }
    /// Only completed conversational text is carried forward, never raw tool results.
    public func context(before id: UUID? = nil) -> String {
        var lines: [String] = []; var bytes = 0
        let eligible = id.flatMap { target in messages.firstIndex(where: { $0.id == target }) }.map { Array(messages.prefix($0)) } ?? messages
        for m in eligible.reversed() where !m.text.isEmpty && (m.phase == "complete" || (m.phase == "stopped" && m.voiceHeard?.isEmpty == false)) {
            let text = m.role == "assistant" ? (m.voiceHeard ?? m.text) : m.text
            guard !text.isEmpty else { continue }
            let delivery = m.voiceInterrupted == true ? " (voice interrupted; only completed spoken sentences follow)" : ""
            let line = "\(m.role)\(delivery): \(text)"
            guard bytes + line.utf8.count < 24000 else { break }
            lines.append(line); bytes += line.utf8.count
        }
        return lines.reversed().joined(separator: "\n\n")
    }
    public mutating func recoverInterrupted() {
        for i in messages.indices {
            if messages[i].phase == "working" { messages[i].phase = "interrupted" }
            for j in messages[i].activities.indices where messages[i].activities[j].phase == "running" { messages[i].activities[j].phase = "interrupted" }
        }
    }
}
public struct ConversationArchive: Codable {
    public var version = 1
    public var selected: UUID?
    public var conversations: [Conversation]
    public init(selected: UUID?, conversations: [Conversation]) { self.selected = selected; self.conversations = conversations }
    public func validate() throws {
        guard version == 1, conversations.count <= 20, Set(conversations.map(\.id)).count == conversations.count else { throw AgentError.message("Conversation history needs recovery. The original file was kept.") }
        for c in conversations {
            guard c.title.count <= 48, c.messages.count <= 40, Set(c.messages.map(\.id)).count == c.messages.count,
                  c.messages.allSatisfy({ ["user", "assistant"].contains($0.role) && $0.text.count <= 16000 && ($0.voiceHeard?.count ?? 0) <= 16000 && ["complete", "working", "stopped", "failed", "interrupted"].contains($0.phase) && $0.activities.count <= 16 && $0.activities.allSatisfy({ $0.title.count <= 300 && $0.id.count <= 100 && $0.phase.count <= 40 }) }) else { throw AgentError.message("Conversation history needs recovery. The original file was kept.") }
        }
    }
}
public final class ConversationFiles {
    public let file: URL
    public init(file: URL) { self.file = file }
    public func load() throws -> ConversationArchive? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let data = try handle.read(upToCount: 4_194_305) ?? Data()
        guard data.count <= 4_194_304 else { throw AgentError.message("Conversation history exceeds its limit. The original file was kept.") }
        let archive = try JSONDecoder().decode(ConversationArchive.self, from: data); try archive.validate(); return archive
    }
    public func save(_ archive: ConversationArchive) throws {
        try archive.validate(); let data = try JSONEncoder().encode(archive)
        guard data.count <= 4_194_304 else { throw AgentError.message("Conversation history is full.") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: file, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
