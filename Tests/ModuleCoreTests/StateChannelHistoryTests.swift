import XCTest
import NookPluginSDK
@testable import ModuleCore

final class StateChannelHistoryTests: XCTestCase {
    private let address = PluginActionAddress("example.provider", "desk_status")
    private let generation = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private var entry: PluginCatalogEntry {
        PluginCatalogEntry(address: address, channel: .init("desk_status", title: "Desk status",
            kind: .state, schema: .init([.init("volume", .number, required: false),
                                        .init("muted", .boolean, required: false)])))
    }
    private func receipt(_ time: TimeInterval, _ values: [String: PluginValue],
                         lifetime: Double = 30, epoch: UUID? = nil) throws -> StateChannelReceipt {
        try XCTUnwrap(StateChannelReceipt.accept(
            .init(.event, address: address, values: values, lifetime: lifetime),
            entry: entry, catalogGeneration: epoch ?? generation,
            previous: nil, now: Date(timeIntervalSince1970: time)))
    }

    func testContinuousTypedUpdatesCarryExactRecentReplacement() throws {
        var history = StateChannelHistory()
        let first = try receipt(100, ["volume": .number(0.4)], lifetime: 300)
        history.record(first)
        let second = try receipt(110, ["volume": .number(0.7)], lifetime: 300)
        history.record(second)
        history.record(second) // exact replay cannot renew or erase the chain
        XCTAssertEqual(history.relation(oldEventID: first.eventID, field: "volume",
            now: Date(timeIntervalSince1970: 111)), .superseded(currentEventID: second.eventID))
        let third = try receipt(120, ["volume": .number(0.4)], lifetime: 300)
        history.record(third)
        XCTAssertEqual(history.relation(oldEventID: first.eventID, field: "volume",
            now: Date(timeIntervalSince1970: 121)), .sameValue(currentEventID: third.eventID))
        XCTAssertEqual(history.relation(oldEventID: second.eventID, field: "volume",
            now: Date(timeIntervalSince1970: 121)), .superseded(currentEventID: third.eventID))
    }

    func testGapOmissionAndEpochChangeCannotFabricateReplacement() throws {
        var history = StateChannelHistory()
        let first = try receipt(100, ["volume": .number(0.4), "muted": .boolean(false)], lifetime: 5)
        history.record(first)
        history.record(try receipt(106, ["volume": .number(0.7)]))
        XCTAssertNil(history.relation(oldEventID: first.eventID, field: "volume",
            now: Date(timeIntervalSince1970: 107)))
        let fresh = try receipt(110, ["volume": .number(0.8), "muted": .boolean(false)])
        history.record(fresh)
        let omitted = try receipt(120, ["volume": .number(0.9)])
        history.record(omitted)
        XCTAssertNil(history.relation(oldEventID: fresh.eventID, field: "muted",
            now: Date(timeIntervalSince1970: 121)))
        XCTAssertEqual(history.relation(oldEventID: fresh.eventID, field: "volume",
            now: Date(timeIntervalSince1970: 121)), .superseded(currentEventID: omitted.eventID))
        history.record(try receipt(125, ["volume": .number(1)], epoch: UUID()))
        XCTAssertNil(history.relation(oldEventID: omitted.eventID, field: "volume",
            now: Date(timeIntervalSince1970: 126)))
        history.clear()
        XCTAssertNil(history.current)
    }

    func testArchiveHorizonDoesNotRenewWithLaterUpdates() throws {
        var history = StateChannelHistory()
        let first = try receipt(100, ["volume": .number(0.4)], lifetime: 300)
        history.record(first)
        history.record(try receipt(110, ["volume": .number(0.7)], lifetime: 300))
        history.record(try receipt(350, ["volume": .number(0.9)], lifetime: 300))
        XCTAssertNotNil(history.relation(oldEventID: first.eventID, field: "volume",
            now: Date(timeIntervalSince1970: 351)))
        history.record(try receipt(405, ["volume": .number(1)], lifetime: 300))
        XCTAssertNil(history.relation(oldEventID: first.eventID, field: "volume",
            now: Date(timeIntervalSince1970: 411)))
    }
}
