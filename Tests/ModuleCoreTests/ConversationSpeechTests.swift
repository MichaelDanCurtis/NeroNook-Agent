import XCTest
@testable import ModuleCore

final class ConversationSpeechTests: XCTestCase {
    func testClosedReplyCanSpeakBeforeTurnCompletionButCannotReopenListening() throws {
        var queue=ConversationSpeechQueue()
        let raw=#"{"reply":"Madrid is the capital of Spain.","arguments":""#
        let preview=AgentAnswer.streamingReply(raw)
        XCTAssertTrue(preview.sealed)
        try queue.append(preview.text,final:false,sealed:preview.sealed)
        XCTAssertEqual(queue.next(),"Madrid is the capital of Spain.")
        XCTAssertFalse(queue.drained) // model still owns this turn
        try queue.append(preview.text,final:true,sealed:true)
        XCTAssertNil(queue.next());XCTAssertTrue(queue.drained)
    }
    func testEscapedQuoteAndIncompleteUnicodeNeverSealTheReply() throws {
        let first=AgentAnswer.streamingReply(#"{"reply":"She said \"Hi\" and"#)
        XCTAssertEqual(first.text,"She said \"Hi\" and");XCTAssertFalse(first.sealed)
        XCTAssertFalse(AgentAnswer.streamingReply(#"{"reply":"Hi \uD83D"#).sealed)
        var queue=ConversationSpeechQueue();try queue.append("First",final:false,sealed:true)
        XCTAssertThrowsError(try queue.append("First and more",final:true))
    }
    func testDecimalSurvivesEveryStreamSplitWithoutSpeakingAnIntegerFirst() throws {
        let text = "The amount is 3.14 dollars. Next sentence."
        for split in text.indices {
            var queue = ConversationSpeechQueue()
            try queue.append(String(text[..<split]), final: false)
            var chunks: [String] = []
            while let chunk = queue.next() { chunks.append(chunk) }
            XCTAssertFalse(chunks.contains("The amount is 3."))
            try queue.append(text, final: true)
            while let chunk = queue.next() { chunks.append(chunk) }
            XCTAssertEqual(chunks, ["The amount is 3.14 dollars.", "Next sentence."])
        }
    }
    func testAbbreviationsAndURLsRemainInsideTheirSentence() throws {
        var queue = ConversationSpeechQueue()
        try queue.append("Ask Dr. Smith about the U.S. site at example.com. Then", final: false)
        XCTAssertEqual(queue.next(), "Ask Dr. Smith about the U.S. site at example.com.")
        XCTAssertNil(queue.next())
        try queue.append("Ask Dr. Smith about the U.S. site at example.com. Then stop.", final: true)
        XCTAssertEqual(queue.next(), "Then stop.")
        XCTAssertTrue(queue.drained)
    }
    func testChunkBudgetDoesNotCutADecimalTokenInHalf() throws {
        var queue = ConversationSpeechQueue()
        let prefix = String(repeating: "a ", count: 174)
        try queue.append(prefix + "3.14 dollars are due.", final: true)
        XCTAssertEqual(queue.next(), prefix.trimmingCharacters(in: .whitespaces))
        XCTAssertEqual(queue.next(), "3.14 dollars are due.")
        XCTAssertTrue(queue.drained)
    }
    func testStreamingWaitsForSentenceAndNeverReplaysIt() throws {
        var queue = ConversationSpeechQueue()
        try queue.append("Hello", final: false); XCTAssertNil(queue.next())
        try queue.append("Hello there. Next", final: false); XCTAssertEqual(queue.next(), "Hello there."); XCTAssertNil(queue.next())
        try queue.append("Hello there. Next sentence", final: true); XCTAssertEqual(queue.next(), "Next sentence"); XCTAssertTrue(queue.drained)
        XCTAssertThrowsError(try queue.append("Rewritten", final: true))
    }
    func testLongUnicodeAndUnbrokenWordsRemainBounded() throws {
        var queue = ConversationSpeechQueue(); let text = String(repeating: "界", count: 3000)
        try queue.append(text, final: true); var chunks: [String] = []
        while let next = queue.next() { XCTAssertLessThan(next.utf8.count, 2048); chunks.append(next) }
        XCTAssertEqual(chunks.joined(), text); XCTAssertTrue(queue.drained)
    }
    func testInterruptedContextIncludesOnlyCompletedAudibleSentences() throws {
        var chat = Conversation(); let id = chat.begin("Tell me more", context: false)
        chat.update(id, text: "Heard sentence. Unsaid sentence.", phase: "stopped")
        chat.messages[1].voiceHeard = "Heard sentence."; chat.messages[1].voiceInterrupted = true
        XCTAssertTrue(chat.context().contains("Heard sentence.")); XCTAssertFalse(chat.context().contains("Unsaid sentence."))
        let data = try JSONEncoder().encode(chat); XCTAssertEqual(try JSONDecoder().decode(Conversation.self, from: data), chat)
        chat.messages[1].voiceHeard = ""; chat.messages[1].phase = "complete"
        XCTAssertFalse(chat.context().contains("assistant:"))
    }
}
