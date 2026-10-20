import Foundation
import NookPluginSDK

/// Recent, in-memory identity for typed state fields from one permitted channel.
/// This is local metadata, not a durable memory store or an action grant.
public struct StateChannelHistory: Sendable {
    public enum Relation: Equatable, Sendable {
        case sameValue(currentEventID: UUID)
        case superseded(currentEventID: UUID)
    }

    private struct ArchivedField: Sendable {
        let eventID: UUID
        let field: String
        let value: PluginValue
        let retainedUntil: Date
    }

    public private(set) var current: StateChannelReceipt?
    private var archive: [ArchivedField] = []

    public init() {}

    public mutating func clear() {
        current = nil
        archive.removeAll()
    }

    /// A field absent from a replacement snapshot is unknown, never withdrawn.
    /// An expired current receipt or changed catalog epoch breaks continuity.
    public mutating func record(_ receipt: StateChannelReceipt) {
        if let previous = current, previous.eventID == receipt.eventID {
            if previous != receipt { clear() }
            return
        }
        guard let previous = current,
              previous.address == receipt.address,
              previous.catalogGeneration == receipt.catalogGeneration,
              previous.definitionSHA256 == receipt.definitionSHA256,
              previous.expires > receipt.observedAt else {
            clear()
            current = receipt
            return
        }
        archive.removeAll { item in
            item.retainedUntil <= receipt.observedAt ||
            receipt.values[item.field] == nil || previous.values[item.field] == nil
        }
        for (field, value) in previous.values where receipt.values[field] != nil {
            archive.append(ArchivedField(eventID: previous.eventID, field: field,
                                         value: value,
                                         retainedUntil: receipt.observedAt.addingTimeInterval(300)))
        }
        if archive.count > 64 { archive.removeFirst(archive.count - 64) }
        current = receipt
    }

    /// Returns an exact same-field relation only while the latest receipt is
    /// fresh. The caller must still recheck the host grant before using it.
    public func relation(oldEventID: UUID, field: String, now: Date) -> Relation? {
        guard let current, current.observedAt <= now, now < current.expires,
              let value = current.values[field],
              let old = archive.first(where: {
                  $0.eventID == oldEventID && $0.field == field && now < $0.retainedUntil
              }) else { return nil }
        return old.value == value
            ? .sameValue(currentEventID: current.eventID)
            : .superseded(currentEventID: current.eventID)
    }
}
