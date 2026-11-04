import Foundation
import NookPluginSDK

/// Ephemeral, owned action results. Not Codable and never a conversation archive.
/// Inspection cannot invoke an action; original request/descriptor/chat are fixed at begin.
public struct AgentActionOutcomes {
    public struct Origin: Equatable {
        public let conversationID: UUID
        public let messageID: UUID
        public init(conversationID: UUID, messageID: UUID) {
            self.conversationID = conversationID; self.messageID = messageID
        }
    }
    public struct Page: Codable, Equatable {
        public let request: String
        public let message: String
        public let address: String
        public let phase: String
        public let requests: [String]
        public let field: Int
        public let fieldCount: Int
        public let name: String?
        public let type: String?
        public let present: Bool
        public let page: Int
        public let pageCount: Int
        public let value: PluginValue?
    }
    /// Per-update value snapshot, sealed by this registry before history eviction.
    /// It is not Codable and callers cannot construct one from SDK/body fields.
    public struct Completion {
        public let requestID: UUID
        public let origin: Origin
        public let phase: PluginRunPhase
        private let entry: PluginCatalogEntry
        private let descriptor: Data
        private let values: [String: PluginValue]
        fileprivate init(requestID: UUID, origin: Origin, phase: PluginRunPhase,
            entry: PluginCatalogEntry, descriptor: Data, values: [String: PluginValue]) {
            self.requestID = requestID; self.origin = origin; self.phase = phase
            self.entry = entry; self.descriptor = descriptor; self.values = values
        }
        public func succeededValues(requestID: UUID, currentCatalog: [PluginCatalogEntry]) -> [String: PluginValue]? {
            guard requestID == self.requestID, phase == .succeeded,
                  let current = currentCatalog.first(where: { $0.address == entry.address }),
                  (try? AgentActionOutcomes.descriptor(current)) == descriptor else { return nil }
            return values
        }
    }
    public enum Problem: Error { case unavailable, capacity, invalid }
    private struct Record {
        let requestID: UUID
        let origin: Origin
        let entry: PluginCatalogEntry
        let descriptor: Data
        let order: UInt64
        var phase: PluginRunPhase = .waitingReview
        var values: [String: PluginValue] = [:]
    }
    public static let activeLimit = 16
    public static let recentLimit = 16
    public static let pageScalars = 128
    private var active: [Record] = []
    private var recent: [Record] = []
    private var nextOrder: UInt64 = 0
    public init() {}
    public var hasPending: Bool { !active.isEmpty }
    fileprivate static func descriptor(_ entry: PluginCatalogEntry) throws -> Data {
        guard let action = entry.action, entry.channel == nil, entry.address.name == action.id else { throw Problem.invalid }
        try entry.address.validate(); try action.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(entry)
        guard data.count <= 65536 else { throw Problem.invalid }
        return data
    }
    public mutating func begin(requestID: UUID, entry: PluginCatalogEntry, origin: Origin) throws {
        guard active.count < Self.activeLimit else { throw Problem.capacity }
        guard !active.contains(where: { $0.requestID == requestID }),
              !recent.contains(where: { $0.requestID == requestID }) else { throw Problem.invalid }
        guard nextOrder < UInt64.max else { throw Problem.capacity }
        let bytes = try Self.descriptor(entry)
        nextOrder += 1
        active.append(.init(requestID: requestID, origin: origin, entry: entry, descriptor: bytes, order: nextOrder))
    }
    public func origin(_ requestID: UUID) -> Origin? {
        (active + recent).first { $0.requestID == requestID }?.origin
    }
    public func entry(_ requestID: UUID) -> PluginCatalogEntry? {
        (active + recent).first { $0.requestID == requestID }?.entry
    }
    /// Returns nil for unknown or already terminal IDs. A success that no longer
    /// matches its complete current descriptor/schema becomes valueless failure.
    @discardableResult public mutating func receive(requestID: UUID, update: PluginRunUpdate,
        currentCatalog: [PluginCatalogEntry]) -> PluginRunPhase? {
        receiveWithOutcome(requestID: requestID, update: update, currentCatalog: currentCatalog)?.phase
    }
    /// The current callback owns its completion independently of recent retention.
    @discardableResult public mutating func receiveWithOutcome(requestID: UUID, update: PluginRunUpdate,
        currentCatalog: [PluginCatalogEntry]) -> Completion? {
        guard let index = active.firstIndex(where: { $0.requestID == requestID }) else { return nil }
        guard update.phase.terminal else {
            if active[index].phase != .cancelling { active[index].phase = update.phase }
            let record = active[index]
            return Completion(requestID: record.requestID, origin: record.origin, phase: record.phase,
                entry: record.entry, descriptor: record.descriptor, values: [:])
        }
        var record = active.remove(at: index)
        record.phase = update.phase
        if update.phase == .succeeded {
            let current = currentCatalog.first { $0.address == record.entry.address }
                .flatMap { try? Self.descriptor($0) } == record.descriptor
            if current, let output = record.entry.action?.output,
               (try? output.validate(update.values)) != nil {
                record.values = update.values
            } else { record.phase = .failed }
        }
        let completion = Completion(requestID: record.requestID, origin: record.origin, phase: record.phase,
            entry: record.entry, descriptor: record.descriptor, values: record.values)
        recent.append(record)
        recent.sort { $0.order < $1.order }
        if recent.count > Self.recentLimit { recent.removeFirst(recent.count - Self.recentLimit) }
        return completion
    }
    /// Read the actual immutable accepted values, never a raw terminal's values.
    /// Recheck complete current descriptor bytes at the continuation boundary.
    public func succeededValues(requestID: UUID, currentCatalog: [PluginCatalogEntry]) -> [String: PluginValue]? {
        guard let record = recent.first(where: { $0.requestID == requestID }), record.phase == .succeeded,
              let current = currentCatalog.first(where: { $0.address == record.entry.address }),
              (try? Self.descriptor(current)) == record.descriptor else { return nil }
        return record.values
    }
    public mutating func clear() { active.removeAll(); recent.removeAll() }
    public mutating func retainConversations(_ ids: Set<UUID>) {
        // Pending calls keep their original ownership even if a UI prunes history.
        // They are not visible from a different conversation and remain bounded.
        recent.removeAll { !ids.contains($0.origin.conversationID) }
    }
    private static func index(_ raw: String) throws -> Int {
        guard !raw.isEmpty, raw.utf8.count <= 2,
              raw.utf8.allSatisfy({ (48...57).contains($0) }),
              raw == "0" || raw.first != "0", let result = Int(raw), result < 16 else { throw Problem.invalid }
        return result
    }
    /// One declared field per page, never an excerpt pretending to be complete.
    /// String pages split on Unicode scalars and concatenate to the exact UTF-8.
    public func page(conversationID: UUID, request: String = "latest", field: String = "0",
        page: String = "0") throws -> Page {
        let records = (recent + active).filter { $0.origin.conversationID == conversationID }.sorted { $0.order < $1.order }
        let record: Record
        if request == "latest" {
            guard let last = records.last else { throw Problem.unavailable }; record = last
        } else {
            guard let id = UUID(uuidString: request), let found = records.first(where: { $0.requestID == id }) else { throw Problem.unavailable }
            record = found
        }
        let fieldIndex = try Self.index(field), pageIndex = try Self.index(page)
        let fields = record.phase == .succeeded ? (record.entry.action?.output.fields ?? []) : []
        guard fields.isEmpty ? fieldIndex == 0 : fieldIndex < fields.count else { throw Problem.invalid }
        let parameter = fields.isEmpty ? nil : fields[fieldIndex]
        let value = parameter.flatMap { record.values[$0.name] }
        var shown = value, pages = 1
        if case .string(let text) = value {
            let scalars = Array(text.unicodeScalars)
            pages = max(1, (scalars.count + Self.pageScalars - 1) / Self.pageScalars)
            guard pageIndex < pages else { throw Problem.invalid }
            let start = pageIndex * Self.pageScalars, end = min(start + Self.pageScalars, scalars.count)
            var chunk = ""; chunk.unicodeScalars.append(contentsOf: scalars[start..<end])
            shown = .string(chunk)
        } else { guard pageIndex == 0 else { throw Problem.invalid } }
        return .init(request: record.requestID.uuidString, message: record.origin.messageID.uuidString,
            address: record.entry.address.key, phase: record.phase.rawValue,
            requests: records.map { $0.requestID.uuidString }, field: fieldIndex, fieldCount: fields.count,
            name: parameter?.name, type: parameter?.kind.rawValue, present: value != nil,
            page: pageIndex, pageCount: pages, value: shown)
    }
    public func json(conversationID: UUID, request: String = "latest", field: String = "0", page: String = "0") throws -> String {
        let result = try self.page(conversationID: conversationID, request: request, field: field, page: page)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(result)
        guard bytes.count <= 8192, let text = String(data: bytes, encoding: .utf8) else { throw Problem.invalid }
        return text
    }
}
