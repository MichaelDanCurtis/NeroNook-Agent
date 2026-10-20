import Foundation
import XCTest
@testable import ModuleCore
import NookPluginSDK

final class ExpressionContractTests: XCTestCase {
    func testBoundedCueAndUnknownMetadataFallback() throws {
        let cue = PluginExpressionCue.named("gentle")!
        XCTAssertEqual(PluginExpressionCue.decode(try JSONEncoder().encode(cue)), cue)
        var value = cue; value.intensity = .nan; XCTAssertThrowsError(try value.validate())
        value = cue; value.durationMs = 3001; XCTAssertThrowsError(try value.validate())
        value = cue; value.intensity = 0.76; XCTAssertThrowsError(try value.validate())
        var fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(cue)) as! [String: Any]
        fields["code"] = "run()"; XCTAssertNil(PluginExpressionCue.decode(try JSONSerialization.data(withJSONObject: fields)))
        XCTAssertNil(PluginExpressionCue.named("flirt")); XCTAssertNil(PluginExpressionCue.named("[laughs]"))
    }
    func testCueCannotEraseTextAndDigestBindsUnicode() throws {
        let segment = PluginExpressionSegment(session: UUID(), sequence: 0, turn: 1, text: "你好 👩🏽‍🚀 cafe\u{301}", cue: .named("gentle"))
        var fields = try JSONSerialization.jsonObject(with: Data(segment.encoded().utf8)) as! [String: Any]
        fields["cue"] = ["delivery": "execute", "url": "https://invalid.example"]
        let malformed = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
        let decoded = try PluginExpressionSegment.decode(malformed)
        XCTAssertEqual(decoded.text, segment.text); XCTAssertNil(decoded.cue)
        fields["text"] = "rewritten"
        XCTAssertThrowsError(try PluginExpressionSegment.decode(String(decoding: JSONSerialization.data(withJSONObject: fields), as: UTF8.self)))
    }
    func testReplayRunTurnOrderingAndBounds() throws {
        let session = UUID(); var state = PluginExpressionAdmission()
        let first = PluginExpressionSegment(session: session, sequence: 0, turn: 1, text: "One", cue: .named("bright"))
        try state.admit(first, session: session, turn: 1)
        XCTAssertThrowsError(try state.admit(first, session: session, turn: 1))
        let second = PluginExpressionSegment(session: session, sequence: 1, turn: 1, text: "Two", cue: nil)
        XCTAssertThrowsError(try state.admit(second, session: UUID(), turn: 1))
        XCTAssertThrowsError(try state.admit(second, session: session, turn: 2))
        try state.admit(second, session: session, turn: 1)
        for n in 2..<32 { try state.admit(.init(session: session, sequence: n, turn: 1, text: "Word", cue: nil), session: session, turn: 1) }
        XCTAssertThrowsError(try state.admit(.init(session: session, sequence: 32, turn: 1, text: "Limit", cue: nil), session: session, turn: 1))
        try state.admit(.init(session: session, sequence: 33, turn: 2, text: "Fresh", cue: nil), session: session, turn: 2)
    }
    func testCapabilityAndExistingSchemaCompatibility() throws {
        XCTAssertEqual(PluginExpressionCapability.decode(PluginExpressionCapability().encoded()), .init())
        XCTAssertNil(PluginExpressionCapability.decode("{\"version\":2}"))
        XCTAssertEqual(PluginSpeechConversation.action.id, "speech_conversation")
        XCTAssertEqual(PluginSpeechConversation.input.fields.map(\.name), ["kind", "text", "mode", "turn"])
        let segment = PluginExpressionSegment(session: UUID(), sequence: 0, turn: 1, text: String(repeating:"x",count:1200), cue: .named("bright"))
        try PluginRunFrame(sequence:0, values:PluginSpeechConversation.values("speakExpression",text:segment.encoded(),turn:1)).validate(PluginSpeechConversation.input)
        XCTAssertThrowsError(try PluginExpressionSegment.decode(String(repeating:"x",count:2049)))
    }
    func testPrefixCueIsOptionalAndDoesNotWaitForReply() {
        XCTAssertNil(AgentAnswer.streamingDelivery("{\"reply\":\"Hi\",\"delivery\":\"bright\"}"))
        XCTAssertNil(AgentAnswer.streamingDelivery("{\"delivery\":\"malicious\"}"))
        XCTAssertNil(AgentAnswer.streamingDelivery("{\"nested\":{\"delivery\":\"bright\"}}"))
        XCTAssertEqual(AgentAnswer.streamingDelivery(" { \"delivery\": \"gentle\", \"reply\":\"Hi")?.delivery, .gentle)
    }
}
