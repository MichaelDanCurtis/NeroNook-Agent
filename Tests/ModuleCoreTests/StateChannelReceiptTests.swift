import XCTest
import NookPluginSDK
@testable import ModuleCore

final class StateChannelReceiptTests: XCTestCase {
    private let address = PluginActionAddress("example.provider", "desk_status")
    private var entry: PluginCatalogEntry {
        PluginCatalogEntry(address: address, channel: .init("desk_status", title: "Desk status",
            kind: .state, schema: .init([.init("volume", .number, minimum: 0, maximum: 1),
                                        .init("muted", .boolean)])))
    }
    private func event(_ id: UUID = UUID(), values: [String: PluginValue] = ["volume": .number(0.4), "muted": .boolean(false)], lifetime: Double = 30) -> PluginBusMessage {
        PluginBusMessage(.event, requestID: id, address: address,
                         values: values, lifetime: lifetime)
    }

    func testExactReceiptAndReplayCannotExtendFreshness() throws {
        let id = UUID(), generation = UUID(), now = Date(timeIntervalSince1970: 100)
        let first = try XCTUnwrap(StateChannelReceipt.accept(event(id), entry: entry,
            catalogGeneration: generation, previous: nil, now: now))
        XCTAssertEqual(first.address, address)
        XCTAssertEqual(first.eventID, id)
        XCTAssertEqual(first.catalogGeneration, generation)
        XCTAssertEqual(first.values["volume"], .number(0.4))
        XCTAssertEqual(first.observedAt, now)
        XCTAssertEqual(first.expires, now.addingTimeInterval(30))
        XCTAssertEqual(first.definitionSHA256.count, 64)
        let replay = event(id, lifetime: 300)
        XCTAssertNil(try StateChannelReceipt.accept(replay, entry: entry,
            catalogGeneration: generation, previous: first,
            now: now.addingTimeInterval(10)))
        XCTAssertEqual(first.expires, now.addingTimeInterval(30))
    }

    func testChangedPayloadSchemaOrAddressFailsClosed() throws {
        let id = UUID(), generation = UUID(), now = Date(timeIntervalSince1970: 100)
        let first = try XCTUnwrap(StateChannelReceipt.accept(event(id), entry: entry,
            catalogGeneration: generation, previous: nil, now: now))
        XCTAssertThrowsError(try StateChannelReceipt.accept(
            event(id, values: ["volume": .number(0.8), "muted": .boolean(false)]),
            entry: entry, catalogGeneration: generation, previous: first, now: now))
        XCTAssertThrowsError(try StateChannelReceipt.accept(
            event(values: ["volume": .string("high"), "muted": .boolean(false)]),
            entry: entry, catalogGeneration: generation, previous: first, now: now))
        XCTAssertThrowsError(try StateChannelReceipt.accept(
            event(values: ["volume": .number(2), "muted": .boolean(false)]),
            entry: entry, catalogGeneration: generation, previous: first, now: now))
        XCTAssertThrowsError(try StateChannelReceipt.accept(event(lifetime: 301),
            entry: entry, catalogGeneration: generation, previous: first, now: now))
        let wrong = PluginCatalogEntry(address: .init("other.provider", "desk_status"),
                                       channel: entry.channel)
        XCTAssertThrowsError(try StateChannelReceipt.accept(event(), entry: wrong,
            catalogGeneration: generation, previous: first, now: now))
        let changed = PluginCatalogEntry(address: address, channel: .init("desk_status",
            title: "Updated desk status", kind: .state, schema: entry.channel!.schema))
        XCTAssertThrowsError(try StateChannelReceipt.accept(event(id), entry: changed,
            catalogGeneration: generation, previous: first, now: now))
    }

    func testNewCatalogGenerationHasDistinctIdentity() throws {
        let id = UUID(), old = UUID(), now = Date(timeIntervalSince1970: 100)
        let first = try XCTUnwrap(StateChannelReceipt.accept(event(id), entry: entry,
            catalogGeneration: old, previous: nil, now: now))
        let next = try XCTUnwrap(StateChannelReceipt.accept(event(id), entry: entry,
            catalogGeneration: UUID(), previous: first, now: now.addingTimeInterval(2)))
        XCTAssertNotEqual(first.catalogGeneration, next.catalogGeneration)
    }

    func testPortableEnvelopeIsTypedAndSourceBound() throws {
        let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let generation = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let now = Date(timeIntervalSince1970: 100)
        let receipt = try XCTUnwrap(StateChannelReceipt.accept(event(id), entry: entry,
            catalogGeneration: generation, previous: nil, now: now))
        let encoded = try receipt.localEvidenceEnvelope()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["definitionSHA256"] as? String, receipt.definitionSHA256)
        XCTAssertEqual(object["observedAt"] as? Double, 100)
        XCTAssertEqual(object["expiresAt"] as? Double, 130)
        let values = try XCTUnwrap(object["values"] as? [String: Any])
        XCTAssertEqual(values["volume"] as? Double, 0.4)
        XCTAssertEqual(values["muted"] as? Bool, false)
        let replacementID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let replacement = try XCTUnwrap(StateChannelReceipt.accept(
            event(replacementID, values: ["volume": .number(0.7), "muted": .boolean(false)]),
            entry: entry, catalogGeneration: generation, previous: receipt,
            now: now.addingTimeInterval(10)))
        let replacementEncoded = try replacement.localEvidenceEnvelope()
        if let directory = ProcessInfo.processInfo.environment["NERO_STATE_FIXTURE_OUTPUT"] {
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try encoder.encode(entry).write(to: output.appendingPathComponent("entry.json"))
            try encoded.write(to: output.appendingPathComponent("envelope.json"))
            try replacementEncoded.write(to: output.appendingPathComponent("replacement-envelope.json"))
        }
    }
}
