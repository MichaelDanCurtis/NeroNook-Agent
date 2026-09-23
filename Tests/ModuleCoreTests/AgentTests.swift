import XCTest
import NookPluginSDK
@testable import ModuleCore

final class AgentTests: XCTestCase {
    func testProposalCannotInventActionOrArguments() throws {
        let entry = PluginCatalogEntry(address: .init("test.provider", "set_level"), action: .init("set_level", title: "Set level", input: .init([.init("level", .number, minimum: 0, maximum: 100)]), effect: .externalChange))
        XCTAssertThrowsError(try AgentAnswer(reply: "Done", action: "test.provider/erase", arguments: "{}").proposal(catalog: [entry]))
        XCTAssertThrowsError(try AgentAnswer(reply: "Set", action: entry.address.key, arguments: "{\"level\":101}").proposal(catalog: [entry]))
        XCTAssertThrowsError(try AgentAnswer(reply: "Set", action: entry.address.key, arguments: "{\"level\":50,\"admin\":true}").proposal(catalog: [entry]))
        let p = try XCTUnwrap(AgentAnswer(reply: "Set", action: entry.address.key, arguments: "{\"level\":50}").proposal(catalog: [entry]))
        XCTAssertEqual(p.1, ["level": .number(50)])
        XCTAssertThrowsError(try AgentAnswer(reply: "Set", action: entry.address.key, arguments: "{\"level\":50}").proposal(catalog: []))
    }
    func testStreamingReplyHandlesEscapesAndSplitUnicode() {
        XCTAssertEqual(AgentAnswer.partialReply("{\"reply\":\"Hello"), "Hello")
        XCTAssertEqual(AgentAnswer.partialReply("{\"reply\":\"Line\\nTwo\",\"action\":null}"), "Line\nTwo")
        XCTAssertEqual(AgentAnswer.partialReply("{\"reply\":\"Hello\\u00"), "Hello")
        XCTAssertEqual(AgentAnswer.partialReply("{\"reply\":\"Say \\\"Hi\\\""), "Say \"Hi\"")
    }
}
