import Foundation
import XCTest
import NookPluginSDK
@testable import ModuleApp

final class ExpressionPlaybackTests: XCTestCase {
    @MainActor func testNegotiationRetainsOldClientPlainSpeechAndClearsOnStop() throws {
        let client = PluginSpeechConversationClient()
        let entry = PluginCatalogEntry(address:.init("test.voice","speech_conversation"),action:PluginSpeechConversation.action)
        var sent:[PluginBusMessage]=[]; client.send = { sent.append($0) };client.catalog([entry]);try client.start(mode:"half")
        let id=try XCTUnwrap(sent.last?.requestID)
        func emit(_ sequence:UInt64,_ kind:String,_ text:String? = nil) { client.receive(.init(.stream,requestID:id,frame:.init(sequence:sequence,values:PluginSpeechConversation.values(kind,text:text)))) }
        emit(0,"ready")
        XCTAssertNil(try client.speak("Plain old provider",cue:.named("gentle"),turn:1))
        XCTAssertEqual(sent.last?.frame?.values["kind"],.string("speak"))
        emit(1,"expressionCapabilities",PluginExpressionCapability().encoded())
        let segment=try XCTUnwrap(client.speak("Same words",cue:.named("bright"),turn:1))
        XCTAssertEqual(segment.text,"Same words");XCTAssertEqual(segment.session,id)
        XCTAssertEqual(sent.last?.frame?.values["kind"],.string("speakExpression"))
        XCTAssertNil(try client.speak(String(repeating:"x",count:1201),cue:.named("bright"),turn:1))
        XCTAssertEqual(sent.last?.frame?.values["kind"],.string("speak"))
        client.stop();XCTAssertNil(client.expressionCapability)
        try client.start(mode:"half");XCTAssertNil(client.expressionCapability)
        client.stop()
    }
    @MainActor func testWrongReceiptStopInterruptAndReusedTurnCannotRestorePosture() {
        let playback=PluginExpressionPlayback()
        let old=PluginExpressionSegment(session:UUID(),sequence:0,turn:1,text:"Hello",cue:.named("gentle"))
        playback.stage(old)
        XCTAssertEqual(playback.pose,.init(),"Enqueue is not audible playback")
        XCTAssertFalse(playback.started(PluginExpressionSegment(session:UUID(),sequence:0,turn:1,text:"Hello",cue:.named("gentle")).receipt.encoded()))
        XCTAssertTrue(playback.started(old.receipt.encoded()));XCTAssertNotEqual(playback.pose,.init())
        playback.clear();XCTAssertEqual(playback.pose,.init());XCTAssertFalse(playback.started(old.receipt.encoded()))
        let next=PluginExpressionSegment(session:UUID(),sequence:0,turn:1,text:"Fresh",cue:.named("bright"))
        playback.stage(next);XCTAssertFalse(playback.started(old.receipt.encoded()))
        XCTAssertTrue(playback.started(next.receipt.encoded()));XCTAssertEqual(playback.pose,next.cue?.pose)
        playback.clear()
    }
    @MainActor func testBoundedExpiryAndDuplicateStartCannotExtendCue() async throws {
        let playback=PluginExpressionPlayback()
        let segment=PluginExpressionSegment(session:UUID(),sequence:0,turn:1,text:"Hello",cue:.init(delivery:.gentle,movement:.tilt,intensity:0.35,durationMs:120))
        playback.stage(segment);XCTAssertTrue(playback.started(segment.receipt.encoded()))
        XCTAssertFalse(playback.started(segment.receipt.encoded()))
        try await Task.sleep(for:.milliseconds(180));XCTAssertEqual(playback.pose,.init())
    }
    @MainActor func testAgentProviderBoundaryClearsPostureWithoutEchoingInterrupt() throws {
        let talk=AgentTalk();var sent:[PluginBusMessage]=[]
        talk.client.send={sent.append($0)};talk.client.catalog([.init(address:.init("test.voice","speech_conversation"),action:PluginSpeechConversation.action)])
        try talk.client.start(mode:"half");let id=try XCTUnwrap(sent.last?.requestID)
        talk.client.receive(.init(.stream,requestID:id,frame:.init(sequence:0,values:PluginSpeechConversation.values("ready"))))
        let segment=PluginExpressionSegment(session:id,sequence:0,turn:0,text:"Output",cue:.named("bright"))
        talk.expression.stage(segment);XCTAssertTrue(talk.expression.started(segment.receipt.encoded()))
        talk.client.receive(.init(.stream,requestID:id,frame:.init(sequence:1,values:PluginSpeechConversation.values("speechStarted",turn:0))))
        XCTAssertEqual(talk.expression.pose,.init());XCTAssertEqual(talk.outputLevel,0)
        XCTAssertFalse(sent.contains{$0.frame?.values["kind"] == .string("interrupt")})
        talk.stop();XCTAssertFalse(talk.expression.started(segment.receipt.encoded()))
    }
}
