import XCTest
import NookPluginSDK
@testable import ModuleApp

final class AgentTalkBoundaryTests: XCTestCase {
    @MainActor func testProviderSpeechStartDoesNotEchoAnInterruptCommand() throws {
        let talk = AgentTalk()
        let entry = PluginCatalogEntry(address: .init("test.voice", "speech_conversation"), action: PluginSpeechConversation.action)
        var sent: [PluginBusMessage] = []
        talk.client.send = { sent.append($0) }; talk.client.catalog([entry])
        try talk.client.start(mode: "half")
        let id = try XCTUnwrap(sent.last?.requestID)
        talk.client.receive(.init(.stream, requestID: id, frame: .init(sequence: 0, values: PluginSpeechConversation.values("ready"))))
        talk.client.receive(.init(.stream, requestID: id, frame: .init(sequence: 1, values: PluginSpeechConversation.values("speechStarted", turn: 0))))
        XCTAssertEqual(talk.phase, "listening")
        XCTAssertFalse(sent.contains { $0.operation == .stream && $0.frame?.values["kind"] == .string("interrupt") })
        talk.stop()
        XCTAssertTrue(sent.contains { $0.operation == .cancel })
    }
}
