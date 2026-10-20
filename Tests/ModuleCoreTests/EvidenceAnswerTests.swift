import XCTest
import NookPluginSDK
@testable import ModuleCore

final class EvidenceAnswerTests: XCTestCase {
    func testConversationAdapterHasSeparateGrantAndHistoryIsOnlyContext() throws {
        let question = PluginEvidenceQuestion(question: "Who owns it?", snapshot: String(repeating: "b", count: 64), sources: [.init(id: "s1", label: "Launch review · 00:08", text: "Jordan owns the launch draft.")])
        let history = [PluginEvidenceExchange(question: "What is happening with launch?", answer: "Older claim by an assistant.")]
        let values = try PluginEvidenceChatContract.values(question, history: history), decoded = try PluginEvidenceChatContract.decode(values)
        XCTAssertEqual(decoded.0, question); XCTAssertEqual(decoded.1, history)
        XCTAssertThrowsError(try PluginEvidenceQuestion(values: values))
        XCTAssertNotEqual(PluginEvidenceChatContract.id, PluginEvidenceAnswerContract.id)
        let prompt = try EvidenceAnswerDraft.prompt(question, history: history)
        XCTAssertTrue(prompt.contains("NEVER factual evidence")); XCTAssertTrue(prompt.contains("Jordan owns the launch draft."))
        XCTAssertThrowsError(try PluginEvidenceChatContract.validate([.init(question: "Question", answer: String(repeating: "x", count: 3000))]))
        var entry = PluginCatalogEntry(address: .init("test.agent", PluginEvidenceChatContract.id), action: PluginEvidenceChatContract.action)
        XCTAssertTrue(PluginEvidenceChatContract.accepts(entry)); entry.action?.effect = .externalChange; XCTAssertFalse(PluginEvidenceChatContract.accepts(entry))
    }
    func testDraftCanOnlyReturnEvidenceClaimsAndCopiesSnapshotLocally() throws {
        let q = PluginEvidenceQuestion(question: "When is launch?", snapshot: String(repeating: "a", count: 64), sources: [.init(id: "s1", label: "00:00:10 · Microphone", text: "Launch is Friday.")])
        let draft = try JSONDecoder().decode(EvidenceAnswerDraft.self, from: Data(#"{"disposition":"answered","statements":[{"text":"Launch is Friday.","citations":["s1"]}]}"#.utf8))
        let answer = try draft.validated(for: q); XCTAssertEqual(answer.snapshot, q.snapshot)
        XCTAssertLessThan(try PluginEvidenceAnswerContract.json(answer).utf8.count, 2048)
        XCTAssertTrue(try EvidenceAnswerDraft.prompt(q).contains("Launch is Friday."))
        let unknown = try JSONDecoder().decode(EvidenceAnswerDraft.self, from: Data(#"{"disposition":"answered","statements":[{"text":"Launch is Friday.","citations":["invented"]}]}"#.utf8))
        XCTAssertThrowsError(try unknown.validated(for: q))
        let unsupported = try JSONDecoder().decode(EvidenceAnswerDraft.self, from: Data(#"{"disposition":"insufficient","statements":[]}"#.utf8))
        XCTAssertNoThrow(try unsupported.validated(for: q))
        XCTAssertNil(EvidenceAnswerDraft.schema["properties"].flatMap { ($0 as? [String: Any])?["action"] })
    }
}
