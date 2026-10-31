import XCTest
import Foundation
import ModuleCore
import NookPluginSDK
@testable import ModuleApp

/// Source regression double only: no managed-runtime or native acceptance claim.
@MainActor private final class OutcomeReasoningRuntime: AgentReasoningRuntime {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    var tool: (([String: Any]) async throws -> [String: Any])?
    var event: ((String, [String: Any]) -> Void)?
    var failed: ((String) -> Void)?
    var threads: [[String: Any]] = [], turns: [[String: Any]] = []
    var thread = "", turn = ""
    func start(binary: URL) async throws {}
    func stop() {}
    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        switch method {
        case "account/read": return ["account": ["type": "chatgpt", "email": "outcome-scripted.invalid"]]
        case "model/list": return ["data": []]
        case "thread/start": threads.append(params); thread = "thread-\(threads.count)"; return ["thread": ["id": thread], "model": "scripted"]
        case "turn/start": turns.append(params); turn = "turn-\(turns.count)"; return ["turn": ["id": turn]]
        default: return [:]
        }
    }
    var definitions: Set<String> {
        Set((threads.last?["dynamicTools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String })
    }
    func finish(action: String? = nil) throws {
        let answer = AgentAnswer(reply: "Authored fixture proposal", action: action)
        let text = String(decoding: try JSONEncoder().encode(answer), as: UTF8.self)
        event?("item/completed", ["threadId": thread, "turnId": turn, "item": ["type": "agentMessage", "text": text]])
        event?("turn/completed", ["threadId": thread, "turn": ["id": turn, "status": "completed"]])
    }
    func resultParams(_ request: String = "latest") -> [String: Any] {
        ["threadId": thread, "turnId": turn, "tool": "nook_action_result", "callId": UUID().uuidString,
         "arguments": ["request": request, "field": "0", "page": "0"]]
    }
}

@MainActor private final class OutcomeMemoryCredentials: AgentCredentialStore {
    func save(_ value: String, account: String) throws { XCTFail("Outcome fixture must not save credentials"); throw AgentActionOutcomes.Problem.invalid }
    func read(account: String) throws -> String { XCTFail("Outcome fixture must not read credentials"); throw AgentActionOutcomes.Problem.invalid }
    func remove(account: String) throws { XCTFail("Outcome fixture must not remove credentials"); throw AgentActionOutcomes.Problem.invalid }
}

final class AgentActionOutcomeRoutingTests: XCTestCase {
    @MainActor private func until(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 { if predicate() { return }; await Task.yield() }
        XCTFail("Source regression did not reach its expected state", file: file, line: line)
    }
    private func descriptor() -> PluginCatalogEntry {
        .init(address: .init("local.neronook.automations", "authored"), action: .init("authored", title: "Authored parent",
            output: .init([.init("answer", .string)]), effect: .localChange, cancellable: true))
    }
    @MainActor private func ready() async -> (AgentModel, OutcomeReasoningRuntime, PluginCatalogEntry) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("authored-outcome-" + UUID().uuidString, isDirectory: true)
        let profile = AgentProfile(root: root, preferences: AgentMemoryPreferences(), credentials: OutcomeMemoryCredentials(),
            restoreState: false, autoReconnect: false, childHome: root.appendingPathComponent("runtime/home"),
            defaultMCPWorkingDirectory: root, visibleLabel: "Authored outcome test · memory-only")
        let runtime = OutcomeReasoningRuntime(directory: profile.runtimeDirectory), entry = descriptor()
        let model = AgentModel(runtime: runtime, restoreState: false, profile: profile)
        model.catalog = [entry]; model.connect(allowSignIn: false)
        await until { model.email != nil && !model.modelsLoading }
        return (model, runtime, entry)
    }
    @MainActor private func proposal(_ model: AgentModel, _ runtime: OutcomeReasoningRuntime, _ entry: PluginCatalogEntry) async throws -> UUID {
        let next = runtime.turns.count + 1
        model.sendChat("Propose only the authored parent", useContext: true)
        await until { runtime.turns.count == next }
        try runtime.finish(action: entry.address.key)
        XCTAssertFalse(model.busy)
        let (current, _) = try model.proposalForReview()
        let id = UUID(); try model.beginActionOutcome(id, entry: current, proposal: true)
        return id
    }
    @MainActor func testLateCompletionStaysWithOriginAndNeverEntersHistoryText() async throws {
        let (model, runtime, entry) = await ready(); defer { model.shutdown() }
        let origin = model.currentID, id = try await proposal(model, runtime, entry)
        model.newConversation(); let second = model.currentID
        model.actionProgress(id, .init(.succeeded, values: ["answer": .string("café 🌿")]))
        XCTAssertTrue(model.actionOutcomeJSON.isEmpty)
        XCTAssertThrowsError(try model.actionOutcomes.page(conversationID: second, request: id.uuidString))
        model.selectConversation(origin)
        let page = try model.actionOutcomes.page(conversationID: origin, request: id.uuidString)
        XCTAssertEqual(page.value, .string("café 🌿"))
        XCTAssertTrue(model.actionOutcomeJSON.contains(id.uuidString))
        XCTAssertFalse(model.conversation.context().contains("café 🌿"))
        XCTAssertFalse(model.conversations.flatMap(\.messages).contains(where: { $0.text.contains("café") }))
        let archive = ConversationArchive(selected: model.currentID, conversations: model.conversations)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(archive), as: UTF8.self).contains("café"))
    }
    @MainActor func testActualOwnedResultToolReadsWithoutInvokingAndBlocksOtherConversation() async throws {
        let (model, runtime, entry) = await ready(); defer { model.shutdown() }
        let origin = model.currentID, id = try await proposal(model, runtime, entry)
        model.actionProgress(id, .init(.succeeded, values: ["answer": .string("café 🌿")]))
        var invokes = 0
        model.readAction = { _, _ in invokes += 1; return [:] }
        model.sendChat("Inspect the last returned result, do not run anything", useContext: true)
        await until { runtime.turns.count == 2 }
        XCTAssertTrue(runtime.definitions.contains("nook_action_result"))
        let response = try await runtime.tool!(runtime.resultParams(id.uuidString))
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
        XCTAssertTrue(encoded.contains(id.uuidString)); XCTAssertEqual(invokes, 0)
        try runtime.finish(); model.newConversation()
        model.sendChat("Inspect a request from another chat", useContext: true)
        await until { runtime.turns.count == 3 }
        do { _ = try await runtime.tool!(runtime.resultParams(id.uuidString)); XCTFail("Other conversation result escaped") } catch {}
        XCTAssertEqual(invokes, 0); XCTAssertNotEqual(model.currentID, origin)
    }
    @MainActor func testReadOriginAndUUIDArePinnedBeforeActualAsyncCallback() async throws {
        let (model, runtime, original) = await ready(); defer { model.shutdown() }
        var entry = original; entry.action?.effect = .readOnly; model.catalog = [entry]
        let owner = model.currentID; var received: UUID?, calls = 0
        model.ownedReadAction = { request, actual, _ in
            calls += 1; received = request
            XCTAssertEqual(model.actionOutcomes.origin(request)?.conversationID, owner)
            XCTAssertEqual(model.actionOutcomes.entry(request), actual)
            try model.validateOwnedReadStart(request, entry: actual)
            model.actionProgress(request, .init(.succeeded, values: ["answer": .string("café 🌿")]))
            return ["answer": .string("café 🌿")]
        }
        model.sendChat("Read the authored action", useContext: true)
        await until { runtime.turns.count == 1 }
        let params: [String: Any] = ["threadId": runtime.thread, "turnId": runtime.turn, "tool": "nook_read_action", "callId": "owned-read",
            "arguments": ["address": entry.address.key, "arguments": "{}"]]
        _ = try await runtime.tool!(params)
        let request = try XCTUnwrap(received)
        XCTAssertEqual(calls, 1); XCTAssertEqual(runtime.turns.count, 1)
        XCTAssertEqual(try model.actionOutcomes.page(conversationID: owner, request: request.uuidString).value, .string("café 🌿"))
        try runtime.finish(); model.newConversation()
        XCTAssertThrowsError(try model.validateOwnedReadStart(request, entry: entry))
    }
    @MainActor func testToolAbsentForContextOffSDKDecisionAndEvidence() async throws {
        let (model, runtime, _) = await ready(); defer { model.shutdown() }
        let question = PluginEvidenceQuestion(question: "Authored?", snapshot: String(repeating: "0", count: 64), sources: [.init(id: "s1", label: "Fixture", text: "Authored")])
        for mode in 0..<4 {
            let expected = runtime.turns.count + 1
            switch mode {
            case 0: model.sendChat("No context", useContext: false)
            case 1: model.ask("SDK ask", useTools: true, interactive: false)
            case 2: model.ask("Decision", decision: true, useTools: true, interactive: true)
            default: model.ask("Evidence", useTools: true, interactive: true, evidence: question)
            }
            await until { runtime.turns.count == expected }
            XCTAssertFalse(runtime.definitions.contains("nook_action_result"))
            do { _ = try await runtime.tool!(runtime.resultParams()); XCTFail("Context-off/noninteractive result tool accepted") } catch {}
            model.cancel(); await Task.yield()
        }
    }
    @MainActor func testCurrentDescriptorMismatchAndTerminalDuplicateCannotPublishValues() async throws {
        let (model, runtime, entry) = await ready(); defer { model.shutdown() }
        let id = try await proposal(model, runtime, entry)
        var changed = entry; changed.action?.title = "Different current contract"
        model.catalog = [changed]
        model.actionProgress(id, .init(.succeeded, values: ["answer": .string("wrong")]))
        let first = try model.actionOutcomes.page(conversationID: model.currentID)
        XCTAssertEqual(first.phase, "failed"); XCTAssertNil(first.value)
        model.catalog = [entry]
        model.actionProgress(id, .init(.succeeded, values: ["answer": .string("late")]))
        XCTAssertEqual(try model.actionOutcomes.page(conversationID: model.currentID), first)
    }
    @MainActor func testActualStopRouteSendsOnlyOwnedSubmittedUUIDAndWaitsForTerminal() async throws {
        let (model, runtime, entry) = await ready(); defer { model.shutdown() }
        let id = try await proposal(model, runtime, entry), owner = model.currentID
        var sent: [PluginBusMessage] = []
        XCTAssertThrowsError(try AgentSubmittedActionStop.send(id.uuidString, model: model, submitted: [], send: { sent.append($0) }))
        try AgentSubmittedActionStop.send(id.uuidString, model: model, submitted: [id], send: { sent.append($0) })
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(sent.first?.operation, .cancel); XCTAssertEqual(sent.first?.requestID, id)
        let pending = try model.actionOutcomes.page(conversationID: owner)
        XCTAssertEqual(pending.phase, "cancelling"); XCTAssertNil(pending.value)
        model.actionProgress(id, .init(.running))
        XCTAssertEqual(try model.actionOutcomes.page(conversationID: owner).phase, "cancelling")
        XCTAssertThrowsError(try AgentSubmittedActionStop.send(id.uuidString, model: model, submitted: [id], send: { sent.append($0) }))
        model.newConversation()
        XCTAssertThrowsError(try AgentSubmittedActionStop.send(id.uuidString, model: model, submitted: [id], send: { sent.append($0) }))
        model.actionProgress(id, .init(.cancelled, values: ["answer": .string("discard")]))
        let ended = try model.actionOutcomes.page(conversationID: owner, request: id.uuidString)
        XCTAssertEqual(ended.phase, "cancelled"); XCTAssertNil(ended.value); XCTAssertEqual(sent.count, 1)
    }
    @MainActor func testInteractiveContinuationRefusesCanonicalEquivalentDescriptorBytes() async throws {
        let (model, runtime, original) = await ready(); defer { model.shutdown() }
        var pinned = original; pinned.action?.effect = .readOnly; pinned.action?.title = "Caf\u{00e9}"
        var changed = pinned; changed.action?.title = "Cafe\u{0301}"
        // Literal source difference: Swift String/entry equality must not defeat the byte pin.
        XCTAssertEqual(pinned, changed)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        XCTAssertNotEqual(try encoder.encode(pinned), try encoder.encode(changed))
        model.catalog = [pinned]
        var requestID: UUID?, reachedDecision = false
        model.ownedReadAction = { request, entry, _ in
            requestID = request
            try model.validateOwnedReadStart(request, entry: entry)
            model.catalog = [changed]
            let update = PluginRunUpdate(.succeeded, values: ["answer": .string("must-not-reach-reasoning")])
            let completion = model.actionProgress(request, update)
            XCTAssertEqual(completion?.phase, .failed)
            let actualDecision = AgentReadCompletion.values(update: update, entry: entry,
                catalog: model.catalog, chat: true, requestID: request, completion: completion)
            reachedDecision = true
            XCTAssertNil(actualDecision)
            // The pre-existing background/continual decision is intentionally unchanged.
            XCTAssertEqual(AgentReadCompletion.values(update: update, entry: entry,
                catalog: model.catalog, chat: false, requestID: request, completion: completion), update.values)
            guard let values = actualDecision else { throw AgentActionOutcomes.Problem.unavailable }
            return values
        }
        model.sendChat("Read the authored action", useContext: true)
        await until { runtime.turns.count == 1 }
        let params: [String: Any] = ["threadId": runtime.thread, "turnId": runtime.turn,
            "tool": "nook_read_action", "callId": "descriptor-byte-check",
            "arguments": ["address": pinned.address.key, "arguments": "{}"]]
        do { _ = try await runtime.tool!(params); XCTFail("Rejected owned success reached reasoning") } catch {}
        XCTAssertTrue(reachedDecision)
        let request = try XCTUnwrap(requestID)
        let page = try model.actionOutcomes.page(conversationID: model.currentID, request: request.uuidString)
        XCTAssertEqual(page.phase, "failed"); XCTAssertNil(page.value)
        XCTAssertFalse(model.conversation.context().contains("must-not-reach-reasoning"))
    }

    @MainActor func testCurrentReadCompletionSurvivesSixteenNewerHistoryResults() async throws {
        let (model, runtime, original) = await ready(); defer { model.shutdown() }
        var entry = original; entry.action?.effect = .readOnly; model.catalog = [entry]
        var reachedDecision = false
        model.ownedReadAction = { request, pinned, _ in
            try model.validateOwnedReadStart(request, entry: pinned)
            model.actionProgress(request, .init(.running))
            // This request is already pending. Complete sixteen later submissions first.
            for index in 0..<16 {
                let newer = UUID(); try model.beginActionOutcome(newer, entry: pinned)
                model.actionProgress(newer, .init(.succeeded, values: ["answer": .string("newer-\(index)")]))
            }
            let update = PluginRunUpdate(.succeeded, values: ["answer": .string("café 🌿")])
            let completion = model.actionProgress(request, update)
            XCTAssertEqual(completion?.requestID, request); XCTAssertEqual(completion?.phase, .succeeded)
            // Bounded history intentionally evicted this older submission, but the
            // current continuation must still receive its actual accepted result.
            XCTAssertNil(model.acceptedActionOutcome(request))
            XCTAssertThrowsError(try model.actionOutcomes.page(conversationID: model.currentID, request: request.uuidString))
            let decision = AgentReadCompletion.values(update: update, entry: pinned,
                catalog: model.catalog, chat: true, requestID: request, completion: completion)
            reachedDecision = true
            XCTAssertEqual(decision, ["answer": .string("café 🌿")])
            XCTAssertNil(completion?.succeededValues(requestID: UUID(), currentCatalog: model.catalog))
            return try XCTUnwrap(decision)
        }
        model.sendChat("Read the still-pending authored action", useContext: true)
        await until { runtime.turns.count == 1 }
        let params: [String: Any] = ["threadId": runtime.thread, "turnId": runtime.turn,
            "tool": "nook_read_action", "callId": "old-current-read",
            "arguments": ["address": entry.address.key, "arguments": "{}"]]
        let response = try await runtime.tool!(params)
        XCTAssertTrue(reachedDecision); XCTAssertEqual(runtime.turns.count, 1)
        let items = try XCTUnwrap(response["contentItems"] as? [[String: Any]])
        let text = try XCTUnwrap(items.first?["text"] as? String)
        let values = try JSONDecoder().decode([String: PluginValue].self, from: Data(text.utf8))
        XCTAssertEqual(values, ["answer": .string("café 🌿")])
    }

}
