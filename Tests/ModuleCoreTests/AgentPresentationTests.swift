import XCTest
@testable import ModuleCore

final class AgentPresentationTests: XCTestCase {
    private func displayed(_ messages: [ChatMessage], budget: Int = 18000) throws -> (AgentPresentation.Messages, [AgentPresentation.Message]) {
        let presentation = AgentPresentation.messages(messages, budget: budget)
        XCTAssertLessThanOrEqual(presentation.json.utf8.count, max(512, budget))
        return (presentation, try JSONDecoder().decode([AgentPresentation.Message].self, from: Data(presentation.json.utf8)))
    }
    func testNewestUnicodeAndEscapedAnswersAlwaysHaveAnExcerpt() throws {
        for text in [String(repeating: "界", count: 9000), String(repeating: "\"\\\n", count: 4000), String(repeating: "👩🏽‍💻", count: 3000)] {
            var chat = Conversation(); let reply = chat.begin("Explain", context: false)
            chat.update(reply, text: text, phase: "complete")
            let (presentation, shown) = try displayed(chat.messages)
            XCTAssertTrue(presentation.omitted); XCTAssertEqual(shown.last?.id, reply)
            XCTAssertFalse(try XCTUnwrap(shown.last).text.isEmpty)
            XCTAssertTrue(shown.last?.excerpt == true)
            XCTAssertEqual(chat.messages.last?.text, String(text.prefix(16000)), "Presentation must not rewrite original chat")
            let (_, small) = try displayed(chat.messages, budget: 512)
            XCTAssertFalse(try XCTUnwrap(small.last).text.isEmpty)
        }
    }
    func testPlaybackBookkeepingDoesNotEraseLongSpokenAnswer() throws {
        var chat = Conversation(); let reply = chat.begin("Explain", context: false)
        let text = String(repeating: "a", count: 9100)
        chat.update(reply, text: text, phase: "complete"); chat.messages[1].voiceHeard = text
        let (_, shown) = try displayed(chat.messages)
        XCTAssertEqual(shown.last?.text, text)
        XCTAssertFalse(AgentPresentation.messages(chat.messages).json.contains("voiceHeard"))
        XCTAssertEqual(chat.messages[1].voiceHeard, text)
    }
    func testLargeMetadataAndSmallBudgetsKeepNewestMessage() throws {
        var latest = ChatMessage(role: "assistant", text: "Readable", phase: "complete")
        latest.activities = (0..<16).map { .init(id: String($0), title: String(repeating: "界", count: 300)) }
        let (_, shown) = try displayed([latest], budget: 512)
        XCTAssertEqual(shown.last?.text, "Readable"); XCTAssertEqual(shown.last?.id, latest.id)
        let oneGrapheme = ChatMessage(role: "assistant", text: "a" + String(repeating: "\u{0301}", count: 4000))
        let (_, grapheme) = try displayed([oneGrapheme], budget: 512)
        XCTAssertFalse(try XCTUnwrap(grapheme.last).text.isEmpty)
        XCTAssertTrue(grapheme.last?.excerpt == true)
    }
    func testReviewsAreOneAtATimeAndExcerptsCannotApprove() throws {
        let pending = (0..<4).map { AgentToolReview(title: "Call \($0)", detail: String(repeating: "x", count: 8192), consequence: "External call") }
        let shown = AgentPresentation.reviews(pending)
        XCTAssertEqual(shown.count, 1); XCTAssertEqual(shown[0].waiting, 4)
        XCTAssertTrue(shown[0].requiresFullReview)
        XCTAssertLessThanOrEqual(try JSONEncoder().encode(shown).count, 4000)
        XCTAssertFalse(AgentPresentation.canApprove(pending[0].id, pending: pending))
        XCTAssertEqual(pending[0].detail.count, 8192)
        let small = AgentToolReview(title: "Exact operation", detail: "target 2", consequence: "Change")
        XCTAssertTrue(AgentPresentation.canApprove(small.id, pending: [small]))
        XCTAssertFalse(AgentPresentation.canApprove(pending[1].id, pending: pending))
    }
    func testEscapedReviewPreviewIsBoundedAndFullDetailsAreNeverClipped() throws {
        let detail = String(repeating: "\u{0001}", count: 40000)
        let review = AgentToolReview(title: String(repeating: "\u{0001}", count: 200), detail: detail, consequence: String(repeating: "\u{0001}", count: 500))
        XCTAssertEqual(review.detail, detail)
        XCTAssertLessThanOrEqual(try JSONEncoder().encode(AgentPresentation.reviews([review])).count, 4000)
        XCTAssertFalse(AgentPresentation.canApprove(review.id, pending: [review]))
    }
    @MainActor func testApprovedReviewCannotSurviveInvalidationBeforeResumption() async throws {
        let reviews = AgentToolReviews(), review = AgentToolReview(title: "Open", detail: "exact target", consequence: "Open")
        let pending = Task { try await reviews.request(review) }
        await Task.yield(); reviews.resolve(review.id, allow: true); reviews.cancel()
        do { try await pending.value; XCTFail("Invalidated approval must not escape") } catch {}
    }
}
