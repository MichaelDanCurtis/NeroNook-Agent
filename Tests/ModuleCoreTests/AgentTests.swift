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

final class ConversationTests: XCTestCase {
    func testHistoryPreservesTurnsAndRecoversInterruptedWithoutToolPayloads() throws {
        var chat = Conversation(); let first = chat.begin("First question", context: false)
        chat.update(first, text: "First answer", phase: "complete")
        let next = chat.begin("Check my Nook", context: true)
        chat.update(next, activity: .init(title: "Read workspace")); chat.recoverInterrupted()
        XCTAssertEqual(chat.messages.last?.phase, "interrupted")
        XCTAssertEqual(chat.messages.last?.activities.first?.phase, "interrupted")
        XCTAssertTrue(chat.context().contains("First answer")); XCTAssertFalse(chat.context().contains("Read workspace"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ConversationFiles(file: root.appendingPathComponent("history.json"))
        try files.save(.init(selected: chat.id, conversations: [chat]))
        XCTAssertEqual(try files.load()?.conversations, [chat])
        try Data("corrupt".utf8).write(to: files.file)
        XCTAssertThrowsError(try files.load()); XCTAssertEqual(try String(contentsOf: files.file), "corrupt")
    }
    func testHistoryBoundsAndMissingReplyCannotMutateAnotherMessage() throws {
        var chat = Conversation()
        for i in 0..<30 { let id = chat.begin("Question \(i)", context: false); chat.update(id, text: String(repeating: "x", count: 4000), phase: "complete") }
        XCTAssertEqual(chat.messages.count, 40); XCTAssertLessThan(chat.context().utf8.count, 24000)
        let original = chat; chat.update(UUID(), text: "wrong reply")
        XCTAssertEqual(chat, original)
        var malformed = ConversationArchive(selected: chat.id, conversations: [chat, chat])
        XCTAssertThrowsError(try malformed.validate()); malformed.conversations.removeLast(); XCTAssertNoThrow(try malformed.validate())
    }
    func testToolScopeIdentityArgumentsAndWriteRejection() throws {
        let base: [String: Any] = ["tool": "nook_capabilities", "threadId": "thread", "turnId": "turn", "callId": "call", "arguments": [String: String]()]
        XCTAssertNoThrow(try AgentTools.validate(base, thread: "thread", turn: "turn", enabled: true))
        XCTAssertThrowsError(try AgentTools.validate(base, thread: "thread", turn: "turn", enabled: false))
        XCTAssertThrowsError(try AgentTools.validate(base, thread: "other", turn: "turn", enabled: true))
        XCTAssertThrowsError(try AgentTools.validate(base, thread: "thread", turn: "old", enabled: true))
        var forged = base; forged["tool"] = "shell"; XCTAssertThrowsError(try AgentTools.validate(forged, thread: "thread", turn: "turn", enabled: true))
        forged = base; forged["arguments"] = ["extra": "value"]; XCTAssertThrowsError(try AgentTools.validate(forged, thread: "thread", turn: "turn", enabled: true))
        let write = PluginCatalogEntry(address: .init("test.device", "change"), action: .init("change", title: "Change", effect: .externalChange))
        XCTAssertThrowsError(try AgentTools.readAction(write.address.key, arguments: "{}", catalog: [write]))
        let read = PluginCatalogEntry(address: .init("test.device", "read"), action: .init("read", title: "Read", input: .init([.init("offset", .number, minimum: 0)])))
        XCTAssertNoThrow(try AgentTools.readAction(read.address.key, arguments: "{\"offset\":0}", catalog: [read]))
        XCTAssertThrowsError(try AgentTools.readAction(read.address.key, arguments: "{\"offset\":0}", catalog: []))
        XCTAssertThrowsError(try AgentTools.readAction(read.address.key, arguments: "{\"offset\":\"wrong\"}", catalog: [read]))
    }
}
