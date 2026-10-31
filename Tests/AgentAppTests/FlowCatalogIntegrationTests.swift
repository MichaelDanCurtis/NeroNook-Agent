import XCTest
import Foundation
import ModuleCore
import NookPluginSDK
@testable import ModuleApp

final class FlowCatalogIntegrationTests: XCTestCase {
    func testSourceToolsRequireEveryInteractiveOptInBoundary() {
        for interactive in [false, true] {
            for nook in [false, true] {
                for optIn in [false, true] {
                    for evidence in [false, true] {
                        for decision in [false, true] {
                            XCTAssertEqual(AgentTools.flowToolsAllowed(interactive: interactive, nook: nook, optIn: optIn, evidence: evidence, decision: decision), interactive && nook && optIn && !evidence && !decision)
                        }
                    }
                }
            }
        }
    }

    func testDedicatedBodyLimitDoesNotWidenExistingToolsOrStaleTurn() throws {
        let flow: [String: Set<String>] = ["nook_flow_call": ["address", "arguments", "body"]]
        func request(_ tool: String, _ args: [String: String]) -> [String: Any] {
            ["threadId": "current-thread", "turnId": "current-turn", "callId": "call", "tool": tool, "arguments": args]
        }
        let args = ["address": "any.owner.flow_catalog_author", "arguments": "{}", "body": String(repeating: "a", count: 262144)]
        let params = request("nook_flow_call", args)
        XCTAssertNoThrow(try AgentTools.validate(params, thread: "current-thread", turn: "current-turn", enabled: true, flow: flow))
        XCTAssertThrowsError(try AgentTools.validate(params, thread: "old-thread", turn: "current-turn", enabled: true, flow: flow))
        XCTAssertThrowsError(try AgentTools.validate(params, thread: "current-thread", turn: "old-turn", enabled: true, flow: flow))
        XCTAssertThrowsError(try AgentTools.validate(params, thread: "current-thread", turn: "current-turn", enabled: false, flow: flow))
        XCTAssertThrowsError(try AgentTools.validate(params, thread: "current-thread", turn: "current-turn", enabled: true))
        // Naming a generic tool's field body does not acquire the flow allowance.
        XCTAssertThrowsError(try AgentTools.validate(request("mcp_call", ["body": String(repeating: "x", count: 8193)]), thread: "current-thread", turn: "current-turn", enabled: true, additional: ["mcp_call": ["body"]]))
        var large = args; large["body"]! += "x"
        XCTAssertThrowsError(try AgentTools.validate(request("nook_flow_call", large), thread: "current-thread", turn: "current-turn", enabled: true, flow: flow))
        var wrongField = args; wrongField["address"] = String(repeating: "x", count: 8193)
        XCTAssertThrowsError(try AgentTools.validate(request("nook_flow_call", wrongField), thread: "current-thread", turn: "current-turn", enabled: true, flow: flow))
        var unknown = args; unknown["approve"] = "yes"
        XCTAssertThrowsError(try AgentTools.validate(request("nook_flow_call", unknown), thread: "current-thread", turn: "current-turn", enabled: true, flow: flow))
    }

    func testCatalogAuthorityNeverEntersOrdinaryReadOrProposalDiscovery() throws {
        let reserved = PluginFlowCatalog.actions.map { PluginCatalogEntry(address: .init("arbitrary.owner", $0.id), action: $0) }
        let published = PluginCatalogEntry(address: .init("another.owner", "published_revision_abc"), action: .init("published_revision_abc", title: "Reviewed published flow", input: .init([]), output: .init([]), effect: .localChange))
        XCTAssertEqual(AgentTools.ordinaryCatalog(reserved + [published]), [published])
        for entry in reserved where entry.action?.effect == .readOnly {
            XCTAssertThrowsError(try AgentTools.readAction(entry.address.key, arguments: "{}", catalog: [entry]))
        }
        // A mutated descriptor under a reserved name must not bypass the route.
        let forged = PluginCatalogEntry(address: .init("third.owner", "flow_catalog_author"), action: .init("flow_catalog_author", title: "Ordinary-looking read", input: .init([]), output: .init([])))
        XCTAssertTrue(AgentTools.ordinaryCatalog([forged]).isEmpty)
        XCTAssertThrowsError(try AgentTools.readAction(forged.address.key, arguments: "{}", catalog: [forged]))
        let answer = AgentAnswer(reply: "Review this invocation", action: published.address.key)
        XCTAssertEqual(try answer.proposal(catalog: AgentTools.ordinaryCatalog(reserved + [published]))?.0, published)
        XCTAssertThrowsError(try AgentAnswer(reply: "Opaque publish", action: reserved[4].address.key).proposal(catalog: AgentTools.ordinaryCatalog(reserved)))
    }

    @MainActor func testLongRunningFeatureIsOnlyNegotiatedWhenOffered() {
        XCTAssertEqual(AgentPlugin.negotiated(["actions-v1", "action-stream-v1"]), ["actions-v1", "action-stream-v1"])
        XCTAssertFalse(AgentPlugin.negotiated(["unknown", "flow-catalog-v1"]).contains("actions-long-running-v1"))
        XCTAssertTrue(AgentPlugin.negotiated(["actions-long-running-v1"]).contains("actions-long-running-v1"))
    }

    @MainActor func testLocalFlowOptInIsOffByDefaultAndPersistsSeparately() throws {
        let suite = "FlowCatalogIntegrationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settingsFile = FileManager.default.temporaryDirectory.appendingPathComponent(suite).appendingPathComponent("tools.json")
        let first = AgentToolbox(defaults: defaults, settingsFile: settingsFile)
        XCTAssertFalse(first.localFlowsEnabled)
        var invalidations = 0
        first.invalidated = { invalidations += 1 }
        first.updateLocalFlows(true)
        XCTAssertEqual(invalidations, 1)
        XCTAssertTrue(first.localFlowsEnabled)
        XCTAssertTrue(defaults.bool(forKey: AgentToolbox.localFlowsKey))
        XCTAssertTrue(AgentToolbox(defaults: defaults, settingsFile: settingsFile).localFlowsEnabled)
        first.updateLocalFlows(false)
        XCTAssertFalse(AgentToolbox(defaults: defaults, settingsFile: settingsFile).localFlowsEnabled)
    }

    func testModelInstructionsKeepNativeReviewAndSeparateInvocation() {
        let enabled = AgentConversationInstructions.make(nook: true, web: false, integrations: [], localFlows: true)
        XCTAssertTrue(enabled.contains("source and results may be shared"))
        XCTAssertTrue(enabled.contains("does not run a flow"))
        XCTAssertTrue(enabled.contains("No automatic"))
        XCTAssertTrue(enabled.contains("cannot dispatch live providers"))
        let disabled = AgentConversationInstructions.make(nook: false, web: false, integrations: ["mac_apps"])
        XCTAssertTrue(disabled.contains("off; do not inspect, author, test or publish"))
        XCTAssertTrue(disabled.contains("Mac/MCP tools. Use those registered tools"))
    }
}
