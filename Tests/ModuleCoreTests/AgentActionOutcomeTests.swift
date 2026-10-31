import XCTest
import NookPluginSDK
@testable import ModuleCore

final class AgentActionOutcomeTests: XCTestCase {
    private func entry(_ fields: [PluginParameter] = [.init("answer", .string)]) -> PluginCatalogEntry {
        .init(address: .init("local.neronook.automations", "published"),
            action: .init("published", title: "Authored result", output: .init(fields)))
    }
    private func origin(_ conversation: UUID = UUID()) -> AgentActionOutcomes.Origin {
        .init(conversationID: conversation, messageID: UUID())
    }
    func testOriginAndExactTypedTerminalAreImmutable() throws {
        var registry = AgentActionOutcomes(); let id = UUID(), owner = origin(), descriptor = entry()
        try registry.begin(requestID: id, entry: descriptor, origin: owner)
        XCTAssertEqual(registry.origin(id), owner)
        registry.receive(requestID: id, update: .init(.succeeded, values: ["answer": .string("café 🌿")]), currentCatalog: [descriptor])
        let first = try registry.page(conversationID: owner.conversationID)
        XCTAssertEqual(first.value, .string("café 🌿")); XCTAssertEqual(first.message, owner.messageID.uuidString)
        XCTAssertEqual(first.type, "string"); XCTAssertTrue(first.present)
        XCTAssertNil(registry.receive(requestID: id, update: .init(.failed, values: ["answer": .string("wrong")]), currentCatalog: [descriptor]))
        XCTAssertEqual(try registry.page(conversationID: owner.conversationID), first)
        XCTAssertThrowsError(try registry.page(conversationID: UUID(), request: id.uuidString))
    }
    func testFailedCancelledAndInterruptedNeverExposeSuppliedValues() throws {
        for phase in [PluginRunPhase.failed, .cancelled, .interrupted] {
            var registry = AgentActionOutcomes(); let id = UUID(), owner = origin(), descriptor = entry()
            try registry.begin(requestID: id, entry: descriptor, origin: owner)
            registry.receive(requestID: id, update: .init(phase, values: ["answer": .string("must-not-expose")]), currentCatalog: [descriptor])
            let page = try registry.page(conversationID: owner.conversationID)
            XCTAssertNil(page.value); XCTAssertFalse(page.present); XCTAssertEqual(page.fieldCount, 0)
            XCTAssertFalse(try registry.json(conversationID: owner.conversationID).contains("must-not-expose"))
        }
    }
    func testWholeDescriptorAndOutputSchemaRevalidateBeforeRetention() throws {
        let original = entry()
        var changed = original; changed.action?.title = "Changed descriptor"
        for (catalog, values) in [([changed], ["answer": PluginValue.string("secret")]),
                                  ([original], ["answer": .boolean(true)]),
                                  ([], ["answer": .string("secret")])] {
            var registry = AgentActionOutcomes(); let id = UUID(), owner = origin()
            try registry.begin(requestID: id, entry: original, origin: owner)
            XCTAssertEqual(registry.receive(requestID: id, update: .init(.succeeded, values: values), currentCatalog: catalog), .failed)
            let page = try registry.page(conversationID: owner.conversationID)
            XCTAssertNil(page.value); XCTAssertEqual(page.phase, "failed")
        }
    }
    func testEveryFieldAndStringPageRoundTripsExactUTF8WithMissingDistinct() throws {
        let text = String(repeating: "e\u{301}🌿\n\"", count: 170)
        XCTAssertLessThanOrEqual(text.utf8.count, 2048)
        let descriptor = entry([.init("literal", .string), .init("count", .number),
            .init("enabled", .boolean), .init("optional", .string, required: false)])
        var registry = AgentActionOutcomes(); let id = UUID(), owner = origin()
        try registry.begin(requestID: id, entry: descriptor, origin: owner)
        registry.receive(requestID: id, update: .init(.succeeded, values: ["literal": .string(text), "count": .number(42), "enabled": .boolean(false)]), currentCatalog: [descriptor])
        let first = try registry.page(conversationID: owner.conversationID)
        var rebuilt = ""
        for index in 0..<first.pageCount {
            let page = try registry.page(conversationID: owner.conversationID, page: String(index))
            guard case .string(let part) = page.value else { return XCTFail("Expected a string part") }
            rebuilt += part
            XCTAssertLessThanOrEqual(part.unicodeScalars.count, 128)
        }
        XCTAssertEqual(Array(rebuilt.utf8), Array(text.utf8))
        XCTAssertEqual(try registry.page(conversationID: owner.conversationID, field: "1").value, .number(42))
        XCTAssertEqual(try registry.page(conversationID: owner.conversationID, field: "2").value, .boolean(false))
        let missing = try registry.page(conversationID: owner.conversationID, field: "3")
        XCTAssertEqual(missing.name, "optional"); XCTAssertFalse(missing.present); XCTAssertNil(missing.value)
        XCTAssertThrowsError(try registry.page(conversationID: owner.conversationID, field: "4"))
        XCTAssertThrowsError(try registry.page(conversationID: owner.conversationID, page: String(first.pageCount)))
        XCTAssertThrowsError(try registry.page(conversationID: owner.conversationID, field: "00"))
    }
    func testFullSixteenFieldsAndEmptyStringRemainInspectable() throws {
        let descriptor = entry((0..<16).map { .init("field\($0)", .string) })
        var values = [String: PluginValue]()
        for i in 0..<16 { values["field\(i)"] = .string(i == 0 ? "" : String(repeating: "\u{1}", count: 2048)) }
        var registry = AgentActionOutcomes(); let owner = origin(), id = UUID()
        try registry.begin(requestID: id, entry: descriptor, origin: owner)
        registry.receive(requestID: id, update: .init(.succeeded, values: values), currentCatalog: [descriptor])
        let empty = try registry.page(conversationID: owner.conversationID)
        XCTAssertEqual(empty.value, .string("")); XCTAssertTrue(empty.present); XCTAssertEqual(empty.pageCount, 1)
        for field in 1..<16 {
            var result = ""
            for page in 0..<16 {
                let part = try registry.page(conversationID: owner.conversationID, field: String(field), page: String(page))
                guard case .string(let text) = part.value else { return XCTFail("String field lost") }; result += text
                let json = try registry.json(conversationID: owner.conversationID, field: String(field), page: String(page))
                let view = PluginCustomView(entry: "chat/index.html", revision: "chat2", state: ["actionOutcome": .string(json)])
                XCTAssertNoThrow(try view.validate())
            }
            XCTAssertEqual(result.utf8.count, 2048); XCTAssertTrue(result.unicodeScalars.allSatisfy { $0.value == 1 })
        }
    }
    func testActiveCapacityRecentEvictionAndLatestUseSubmissionOrder() throws {
        var registry = AgentActionOutcomes(); let owner = origin(), descriptor = entry()
        let ids = (0..<16).map { _ in UUID() }
        for id in ids { try registry.begin(requestID: id, entry: descriptor, origin: owner) }
        XCTAssertThrowsError(try registry.begin(requestID: UUID(), entry: descriptor, origin: owner))
        // Complete newest first: latest is submission order, not callback order.
        for id in ids.reversed() { registry.receive(requestID: id, update: .init(.succeeded, values: ["answer": .string("old")]), currentCatalog: [descriptor]) }
        XCTAssertEqual(try registry.page(conversationID: owner.conversationID).request, ids.last!.uuidString)
        let newest = UUID(); try registry.begin(requestID: newest, entry: descriptor, origin: owner)
        registry.receive(requestID: newest, update: .init(.succeeded, values: ["answer": .string("new")]), currentCatalog: [descriptor])
        XCTAssertThrowsError(try registry.page(conversationID: owner.conversationID, request: ids[0].uuidString))
        XCTAssertEqual(try registry.page(conversationID: owner.conversationID).requests.count, 16)
        for _ in 0..<16 { try registry.begin(requestID: UUID(), entry: descriptor, origin: owner) }
        let json = try registry.json(conversationID: owner.conversationID)
        XCTAssertEqual(try registry.page(conversationID: owner.conversationID).requests.count, 32)
        XCTAssertLessThanOrEqual(json.utf8.count, 8192)
        XCTAssertNoThrow(try PluginCustomView(entry: "chat/index.html", revision: "chat2", state: ["actionOutcome": .string(json)]).validate())
        registry.clear(); XCTAssertThrowsError(try registry.page(conversationID: owner.conversationID))
    }
    func testNegativeZeroRetainsSDKNumberTypeAndNonfiniteFails() throws {
        let descriptor = entry([.init("answer", .number)])
        for number in [-0.0, Double.infinity] {
            var registry = AgentActionOutcomes(); let owner = origin(), id = UUID()
            try registry.begin(requestID: id, entry: descriptor, origin: owner)
            registry.receive(requestID: id, update: .init(.succeeded, values: ["answer": .number(number)]), currentCatalog: [descriptor])
            let page = try registry.page(conversationID: owner.conversationID)
            if number.isFinite {
                guard case .number(let result) = page.value else { return XCTFail("SDK number became text") }
                XCTAssertEqual(result.sign, .minus); XCTAssertEqual(result, 0)
            } else { XCTAssertNil(page.value); XCTAssertEqual(page.phase, "failed") }
        }
    }
    func testToolArgumentsAreClosedAndContextGateStillRequired() throws {
        let params: [String: Any] = ["threadId": "t", "turnId": "u", "callId": "c", "tool": "nook_action_result", "arguments": ["request": "latest", "field": "0", "page": "0"]]
        XCTAssertEqual(try AgentTools.validate(params, thread: "t", turn: "u", enabled: true).0, "nook_action_result")
        XCTAssertThrowsError(try AgentTools.validate(params, thread: "t", turn: "u", enabled: false))
        var bad = params; bad["arguments"] = ["request": "latest", "field": "0", "page": "0", "address": "do-not-invoke"]
        XCTAssertThrowsError(try AgentTools.validate(bad, thread: "t", turn: "u", enabled: true))
    }
}
