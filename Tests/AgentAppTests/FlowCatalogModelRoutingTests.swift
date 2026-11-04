import XCTest
import Foundation
import ModuleCore
import NookPluginSDK
@testable import ModuleApp

@MainActor private final class ScriptedFlowReasoningRuntime: AgentReasoningRuntime {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scripted-flow-" + UUID().uuidString)
    var tool: (([String: Any]) async throws -> [String: Any])?
    var event: ((String, [String: Any]) -> Void)?
    var failed: ((String) -> Void)?
    var starts = 0
    var stops = 0
    var threadStarts: [[String: Any]] = []
    var turnStarts: [[String: Any]] = []
    var thread = ""
    var turn = ""
    func start(binary: URL) async throws { starts += 1 }
    func stop() { stops += 1 }
    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        switch method {
        case "account/read": return ["account": ["type": "chatgpt", "email": "scripted.invalid"]]
        case "model/list": return ["data": []]
        case "thread/start":
            threadStarts.append(params); thread = "scripted-thread-\(threadStarts.count)"
            return ["thread": ["id": thread], "model": "scripted"]
        case "turn/start":
            turnStarts.append(params); turn = "scripted-turn-\(turnStarts.count)"
            return ["turn": ["id": turn]]
        default: return [:]
        }
    }
    func params(_ name: String = "nook_flow_catalog", call: String = UUID().uuidString, args: [String: String] = [:]) -> [String: Any] {
        ["threadId": thread, "turnId": turn, "tool": name, "callId": call, "arguments": args]
    }
    func completed() {
        event?("item/completed", ["threadId": thread, "turnId": turn, "item": ["type": "agentMessage", "text": #"{"reply":"Scripted answer","action":null,"arguments":"{}","decision":null}"#]])
        event?("turn/completed", ["threadId": thread, "turn": ["id": turn, "status": "completed"]])
    }
}

final class FlowCatalogModelRoutingTests: XCTestCase {
    @MainActor private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Scripted runtime did not reach the expected state", file: file, line: line)
    }
    @MainActor private func ready() async -> (AgentModel, ScriptedFlowReasoningRuntime) {
        let runtime = ScriptedFlowReasoningRuntime()
        let model = AgentModel(runtime: runtime, restoreState: false)
        // Construction must never restore a real account or start its runtime.
        XCTAssertEqual(runtime.starts, 0)
        XCTAssertEqual(model.selectedModel, "")
        XCTAssertEqual(model.retentionDays, 0)
        model.flowToolsEnabled = { true }
        model.flowDefinitions = { [["type": "function", "name": "nook_flow_catalog", "description": "scripted local flow fixture", "inputSchema": ["type": "object", "properties": [:], "required": [], "additionalProperties": false]]] }
        model.flowKeys = { ["nook_flow_catalog": []] }
        model.flowTool = { _, _ in AgentTools.response("scripted flow result") }
        model.connect(allowSignIn: false)
        await eventually { model.email != nil && !model.modelsLoading }
        return (model, runtime)
    }
    @MainActor private func tools(_ runtime: ScriptedFlowReasoningRuntime) -> Set<String> {
        Set((runtime.threadStarts.last?["dynamicTools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String })
    }

    @MainActor func testActualChatAndTalkRegisterAndRouteDedicatedDynamicTool() async throws {
        let (model, runtime) = await ready()
        defer { model.shutdown() }
        var begins = 0, ends = 0
        model.beginFlowTurn = { begins += 1 }; model.cancelFlowTurn = { ends += 1 }
        model.sendChat("Inspect my local flow", useContext: true)
        await eventually { runtime.turnStarts.count == 1 }
        XCTAssertTrue(tools(runtime).contains("nook_flow_catalog"))
        XCTAssertTrue((runtime.threadStarts.last?["baseInstructions"] as? String ?? "").contains("source and results may be shared"))
        let response = try await XCTUnwrap(runtime.tool)(runtime.params())
        XCTAssertEqual(response["success"] as? Bool, true)
        runtime.completed()
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.reply, "Scripted answer")
        XCTAssertEqual(begins, 1); XCTAssertGreaterThanOrEqual(ends, 1)
        XCTAssertNotNil(model.sendVoice("Inspect again", useContext: true))
        await eventually { runtime.turnStarts.count == 2 }
        XCTAssertTrue(tools(runtime).contains("nook_flow_catalog"))
        XCTAssertEqual(begins, 2)
        runtime.completed()
    }

    @MainActor func testActualSDKAndEvidenceTurnsNeverRegisterOrRouteFlowTools() async throws {
        let evidence = PluginEvidenceQuestion(question: "Who owns it?", snapshot: String(repeating: "b", count: 64), sources: [.init(id: "s1", label: "Fixture", text: "Jordan owns it.")])
        for kind in ["sdk", "decision", "evidence", "evidence-history"] {
            let (model, runtime) = await ready()
            switch kind {
            case "decision": model.ask("Decide", decision: true, useTools: true)
            case "evidence": model.ask(evidence.question, useTools: true, evidence: evidence)
            case "evidence-history": model.ask(evidence.question, useTools: true, evidence: evidence, evidenceHistory: [.init(question: "Prior fixture question", answer: "Prior fixture answer")])
            default: model.ask("SDK ask", useTools: true)
            }
            await eventually { runtime.turnStarts.count == 1 }
            XCTAssertTrue(tools(runtime).isEmpty, kind)
            do { _ = try await XCTUnwrap(runtime.tool)(runtime.params()); XCTFail("SDK route admitted flow tools: " + kind) } catch {}
            model.shutdown()
        }
    }

    @MainActor func testContextAndFlowOptInAreRequiredWhileMacToolsStayIndependent() async throws {
        for optIn in [false, true] {
            let (model, runtime) = await ready()
            model.flowToolsEnabled = { optIn }
            model.integrationKeys = { ["mac_apps": []] }
            model.integrationDefinitions = { [["type": "function", "name": "mac_apps", "inputSchema": ["type": "object", "properties": [:], "required": []]]] }
            model.integrationTool = { _, _ in AgentTools.response("independent Mac fixture") }
            model.sendChat("List apps", useContext: false)
            await eventually { runtime.turnStarts.count == 1 }
            XCTAssertEqual(tools(runtime), ["mac_apps"])
            let response = try await XCTUnwrap(runtime.tool)(runtime.params("mac_apps"))
            XCTAssertEqual(response["success"] as? Bool, true)
            do { _ = try await XCTUnwrap(runtime.tool)(runtime.params()); XCTFail("Context-off turn admitted flow source") } catch {}
            model.shutdown()
        }
        let (model, runtime) = await ready()
        model.flowToolsEnabled = { false }
        model.sendChat("Inspect flow", useContext: true)
        await eventually { runtime.turnStarts.count == 1 }
        XCTAssertFalse(tools(runtime).contains("nook_flow_catalog"))
        model.shutdown()
    }

    @MainActor func testActualDynamicCallbackKeepsThreadTurnDuplicateAnd48CallFence() async throws {
        let (model, runtime) = await ready()
        defer { model.shutdown() }
        var calls = 0
        model.flowTool = { _, _ in calls += 1; return AgentTools.response("bounded fixture") }
        model.sendChat("Inspect", useContext: true)
        await eventually { runtime.turnStarts.count == 1 }
        let callback = try XCTUnwrap(runtime.tool)
        var stale = runtime.params(); stale["turnId"] = "old-turn"
        do { _ = try await callback(stale); XCTFail("Stale turn admitted") } catch {}
        stale = runtime.params(); stale["threadId"] = "old-thread"
        do { _ = try await callback(stale); XCTFail("Stale thread admitted") } catch {}
        _ = try await callback(runtime.params(call: "1"))
        do { _ = try await callback(runtime.params(call: "1")); XCTFail("Duplicate call admitted") } catch {}
        for index in 2...48 { _ = try await callback(runtime.params(call: String(index))) }
        do { _ = try await callback(runtime.params(call: "49")); XCTFail("Call limit exceeded") } catch {}
        XCTAssertEqual(calls, 48)
        runtime.completed()
        do { _ = try await callback(runtime.params()); XCTFail("Completed turn admitted") } catch {}
    }

    @MainActor func testLateToolResultIsRejectedAfterStopDisconnectAndGrantChange() async throws {
        for boundary in ["stop", "disconnect", "grant"] {
            let (model, runtime) = await ready()
            var continuation: CheckedContinuation<[String: Any], Error>?
            model.flowTool = { _, _ in try await withCheckedThrowingContinuation { continuation = $0 } }
            model.sendChat("Inspect", useContext: true)
            await eventually { runtime.turnStarts.count == 1 }
            let callback = try XCTUnwrap(runtime.tool)
            let task = Task { try await callback(runtime.params()) }
            await eventually { continuation != nil }
            switch boundary {
            case "disconnect": runtime.failed?("Scripted disconnect")
            case "grant": model.invalidateFlowCatalog()
            default: model.cancel()
            }
            continuation?.resume(returning: AgentTools.response("LATE SECRET MUST BE DISCARDED"))
            do { _ = try await task.value; XCTFail("Late result survived " + boundary) } catch {}
            XCTAssertFalse(model.busy)
            XCTAssertFalse(model.reply.contains("LATE SECRET"))
            model.shutdown()
        }
    }
}
