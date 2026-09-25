import Foundation

public enum ContextKind: String, Codable, Sendable { case workspace, window, nook }

public struct ContextSource: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: ContextKind
    public var name: String
    public var enabled = true
    public var allowCloud = false
    public var bookmark: Data?
    public init(kind: ContextKind, name: String, bookmark: Data? = nil) {
        id = UUID(); self.kind = kind; self.name = String(name.prefix(120)); self.bookmark = bookmark
    }
}

public struct ContextFact: Equatable, Sendable {
    public var source: UUID
    public var generation: UUID
    public var text: String
    public var observed: Date
    public var expires: Date
    public init(source: UUID, generation: UUID, text: String, observed: Date, expires: Date) {
        self.source = source; self.generation = generation; self.text = text; self.observed = observed; self.expires = expires
    }
}

/// Session-bound and transient. Raw observations never enter the durable archive.
public struct ContextBuffer: Sendable {
    public private(set) var generation = UUID()
    public private(set) var paused = false
    public private(set) var facts: [UUID: ContextFact] = [:]
    public init() {}
    public mutating func invalidate(paused: Bool? = nil) {
        if let paused { self.paused = paused }
        generation = UUID(); facts.removeAll()
    }
    public mutating func remove(_ source: UUID) { facts[source] = nil }
    @discardableResult public mutating func ingest(_ fact: ContextFact, sources: [ContextSource], now: Date) -> Bool {
        guard !paused, fact.generation == generation, let source = sources.first(where: { $0.id == fact.source }), source.enabled,
              fact.observed.timeIntervalSince1970.isFinite, fact.expires.timeIntervalSince1970.isFinite,
              fact.observed <= now, now < fact.expires, fact.expires.timeIntervalSince(fact.observed) <= 60,
              !fact.text.isEmpty, fact.text.utf8.count <= 8192, facts.count < 24 || facts[fact.source] != nil else { return false }
        if let old = facts[fact.source], old.observed > fact.observed { return false }
        facts[fact.source] = fact; return true
    }
    public func snapshot(sources: [ContextSource], cloud: Bool, now: Date) -> [ContextFact] {
        guard !paused else { return [] }
        return sources.filter { $0.enabled && (!cloud || $0.allowCloud) }.compactMap { source in
            guard let fact = facts[source.id], fact.generation == generation, fact.observed <= now, now < fact.expires else { return nil }
            return fact
        }
    }
}

public struct ObservedRun: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var phase: String
    public var detail: String
    public var observed: Date
    public var terminal: Bool { ["succeeded", "completed", "simulated", "failed", "cancelled", "interrupted"].contains(phase) }
    public init(id: String, title: String, phase: String, detail: String = "", observed: Date) {
        self.id = id; self.title = String(title.prefix(120)); self.phase = String(phase.prefix(40)); self.detail = String(detail.prefix(200)); self.observed = observed
    }
}

public struct AgentWatch: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var runID: String
    public var title: String
    public var paused = false
    public var dismissed = false
    public var lastPhase: String?
    public var lastDetail = ""
    public var lastObserved: Date?
    public var terminalSeen = false
    public var created = Date()
    public init(run: ObservedRun) { runID = run.id; title = run.title }
}

public struct AgentActivity: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var watchID: UUID?
    public var title: String
    public var detail: String
    public var date = Date()
    public var attention = false
    public var read = false
    public init(watchID: UUID? = nil, title: String, detail: String, attention: Bool = false) {
        self.watchID = watchID; self.title = String(title.prefix(160)); self.detail = String(detail.prefix(400)); self.attention = attention
    }
}

public struct ContinualArchive: Codable, Sendable {
    public var version = 1
    public var paused = false
    public var quiet = false
    public var sources: [ContextSource] = []
    public var watches: [AgentWatch] = []
    public var activities: [AgentActivity] = []
    public init() {}
    public mutating func add(_ activity: AgentActivity) {
        activities.append(activity); activities = Array(activities.suffix(200))
    }
    public mutating func watch(_ run: ObservedRun) throws {
        // Dismissal must free capacity; retain the bounded outcome timeline separately.
        if watches.count >= 32 { watches.removeAll { $0.dismissed } }
        guard UUID(uuidString: run.id) != nil, watches.count < 32,
              !watches.contains(where: { $0.runID == run.id && !$0.dismissed }) else { throw AgentError.message("That run is already watched, or the 32-watch limit was reached.") }
        let watch = AgentWatch(run: run); watches.append(watch)
        add(.init(watchID: watch.id, title: "Watching \(run.title)", detail: "Following this exact run. No workflow or device action was started."))
    }
    /// A complete, fresh SDK page set only. No missing-row inference of success.
    @discardableResult public mutating func observe(_ runs: [ObservedRun], permitted: Bool, now: Date) -> Bool {
        guard !paused, permitted else { return false }
        var changed = false
        for i in watches.indices where !watches[i].paused && !watches[i].dismissed && !watches[i].terminalSeen {
            guard let run = runs.first(where: { $0.id == watches[i].runID }), run.observed <= now,
                  now.timeIntervalSince(run.observed) <= 30,
                  watches[i].lastObserved.map({ $0 <= run.observed }) ?? true else { continue }
            guard watches[i].lastPhase != run.phase || watches[i].lastDetail != run.detail else { continue }
            watches[i].lastPhase = run.phase; watches[i].lastDetail = run.detail; watches[i].lastObserved = run.observed
            changed = true
            if run.terminal {
                watches[i].terminalSeen = true
                add(.init(watchID: watches[i].id, title: "\(run.title) · \(run.phase)", detail: "Nook reported this result for the watched run. \(run.detail)", attention: !quiet))
            } else if run.phase == "waitingReview" || run.phase == "waiting" {
                add(.init(watchID: watches[i].id, title: "\(run.title) needs you", detail: "The automation is waiting for review. \(run.detail)", attention: !quiet))
            }
        }
        return changed
    }
    public func validate() throws {
        guard version == 1, sources.count <= 24, watches.count <= 32, activities.count <= 200,
              Set(sources.map(\.id)).count == sources.count, Set(watches.map(\.id)).count == watches.count, Set(activities.map(\.id)).count == activities.count,
              sources.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 120 && ($0.bookmark?.count ?? 0) <= 65536 }),
              watches.allSatisfy({ UUID(uuidString: $0.runID) != nil && $0.title.count <= 120 && $0.lastDetail.count <= 200 && ($0.lastPhase?.count ?? 0) <= 40 && ($0.lastObserved?.timeIntervalSince1970.isFinite ?? true) && $0.created.timeIntervalSince1970.isFinite }),
              activities.allSatisfy({ $0.title.count <= 160 && $0.detail.count <= 400 && $0.date.timeIntervalSince1970.isFinite }) else { throw AgentError.message("Saved continual state is invalid; its file was preserved.") }
    }
}

public struct ContinualFiles {
    public let file: URL
    public init(file: URL) { self.file = file }
    private func check() throws {
        for url in [file.deletingLastPathComponent(), file] where FileManager.default.fileExists(atPath: url.path) {
            let info = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            guard info.isSymbolicLink != true, (info.fileSize ?? 0) <= 4*1024*1024 else { throw AgentError.message("Continual storage must be a bounded local file, not a link.") }
        }
    }
    public func load() throws -> ContinualArchive {
        try check(); guard FileManager.default.fileExists(atPath: file.path) else { return .init() }
        let archive = try JSONDecoder().decode(ContinualArchive.self, from: Data(contentsOf: file)); try archive.validate(); return archive
    }
    public func save(_ archive: ContinualArchive) throws {
        try archive.validate(); try check()
        let data = try JSONEncoder().encode(archive)
        guard data.count <= 4*1024*1024 else { throw AgentError.message("Continual storage limit reached.") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
