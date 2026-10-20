import CryptoKit
import Foundation
import NookPluginSDK

/// Local provenance for a permitted, host-routed state publication.
///
/// The action router authenticates the publisher and grants before delivering
/// the event. This value does not grant access or prove the provider's claim is
/// physically true. It remains transient and is not sent to ChatGPT.
public struct StateChannelReceipt: Equatable, Sendable {
    public let address: PluginActionAddress
    public let eventID: UUID
    /// Local catalog epoch; this is not the provider's process-session ID.
    public let catalogGeneration: UUID
    public let definitionSHA256: String
    public let values: [String: PluginValue]
    public let observedAt: Date
    public let expires: Date

    /// Portable local research envelope. The caller must separately supply the
    /// currently permitted catalog entry and grant; these bytes grant nothing.
    /// Do not attach this envelope to a ChatGPT request.
    public func localEvidenceEnvelope() throws -> Data {
        let envelope = LocalEvidenceEnvelope(
            version: 1, address: address, eventID: eventID,
            catalogGeneration: catalogGeneration,
            definitionSHA256: definitionSHA256, values: values,
            observedAt: observedAt.timeIntervalSince1970,
            expiresAt: expires.timeIntervalSince1970)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    /// Accept a host-routed event against the exact currently permitted catalog entry.
    /// An identical replay returns nil and cannot extend the original expiry.
    public static func accept(_ message: PluginBusMessage,
                              entry: PluginCatalogEntry,
                              catalogGeneration: UUID,
                              previous: StateChannelReceipt?,
                              now: Date) throws -> StateChannelReceipt? {
        guard message.operation == .event,
              message.address == entry.address,
              let channel = entry.channel, channel.kind == .state,
              let lifetime = message.lifetime, lifetime.isFinite,
              lifetime > 0, lifetime <= 300,
              now.timeIntervalSince1970.isFinite else {
            throw StateChannelReceiptError.invalidEvent
        }
        let values = message.values ?? [:]
        try channel.schema.validate(values)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let definition = try encoder.encode(entry)
        let digest = SHA256.hash(data: definition).map { String(format: "%02x", $0) }.joined()
        if let previous, previous.catalogGeneration == catalogGeneration,
           previous.address == entry.address, previous.eventID == message.requestID {
            guard previous.values == values, previous.definitionSHA256 == digest else {
                throw StateChannelReceiptError.reusedEventID
            }
            return nil
        }
        return StateChannelReceipt(address: entry.address,
                                   eventID: message.requestID,
                                   catalogGeneration: catalogGeneration,
                                   definitionSHA256: digest,
                                   values: values,
                                   observedAt: now,
                                   expires: now.addingTimeInterval(lifetime))
    }
}

private struct LocalEvidenceEnvelope: Encodable {
    let version: Int
    let address: PluginActionAddress
    let eventID: UUID
    let catalogGeneration: UUID
    let definitionSHA256: String
    let values: [String: PluginValue]
    let observedAt: Double
    let expiresAt: Double
}

public enum StateChannelReceiptError: Error {
    case invalidEvent
    case reusedEventID
}
