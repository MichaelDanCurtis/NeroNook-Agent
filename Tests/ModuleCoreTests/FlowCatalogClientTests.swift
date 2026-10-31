import XCTest
import Foundation
import NookPluginSDK
@testable import ModuleCore

/// Accountless scripted PluginBus transport. These checks do not assert an
/// installed host, human review, provider execution or model-account adoption.
@MainActor final class FlowCatalogClientTests: XCTestCase {
    @MainActor private final class Harness {
        let session = UUID()
        var sent: [PluginBusMessage] = []
        var times: [TimeInterval] = []
        var onSend: ((PluginBusMessage) -> Void)?
        var client: FlowCatalogClient!
        var sequences: [UUID: UInt64] = [:]
        init(names: [String], budget: Int = 60_000, timeout: Duration? = nil, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
            client = FlowCatalogClient(send: { [weak self] message in
                guard let self else { return }
                self.sent.append(message); self.times.append(ProcessInfo.processInfo.systemUptime)
                self.onSend?(message)
            }, resultBudgetBytes: budget, requestTimeout: timeout, now: now)
            update(names: names); client.beginTurn()
        }
        func entries(_ names: [String]) -> [PluginCatalogEntry] {
            names.compactMap { name in PluginFlowCatalog.actions.first(where: { $0.id == name }).map {
                PluginCatalogEntry(address: .init("example.catalog", name), action: $0)
            } }
        }
        func update(names: [String], session: UUID? = nil, features: Set<String> = PluginFlowCatalog.requiredFeatures, extra: [PluginCatalogEntry] = []) {
            client.update(catalog: entries(names) + extra, features: features, session: session ?? self.session)
        }
        func running(_ message: PluginBusMessage) {
            _ = client.receive(.init(.update, requestID: message.requestID, address: message.address, update: .init(.running)))
        }
        func frame(_ request: PluginBusMessage, _ values: [String: PluginValue], sequence: UInt64? = nil) {
            let seq = sequence ?? sequences[request.requestID, default: 0]
            sequences[request.requestID] = seq + 1
            _ = client.receive(.init(.stream, requestID: request.requestID, address: request.address, frame: .init(sequence: seq, values: values)))
        }
        func ready(_ request: PluginBusMessage) {
            frame(request, ["kind": .string("ready"), "meta": .string(Self.json([
                "version": 1, "request": request.requestID.uuidString.lowercased(), "profile": PluginFlowCatalog.nativeProfile,
                "chunkBytes": 1536, "bodyLimit": 262144, "state": "receiving"
            ]))])
        }
        func output(_ request: PluginBusMessage, body: Data, hash: String? = nil) {
            frame(request, ["kind": .string("begin"), "bytes": .number(Double(body.count)), "sha256": .string(hash ?? FlowCatalogClient.sha(body)), "meta": .string("{}")])
            for (index, offset) in stride(from: 0, to: body.count, by: 1536).enumerated() {
                let data = body.subdata(in: offset..<min(body.count, offset + 1536))
                frame(request, ["kind": .string("chunk"), "index": .number(Double(index)), "data": .string(data.base64EncodedString())])
            }
            frame(request, ["kind": .string("end")])
        }
        func success(_ request: PluginBusMessage, _ result: [String: Any]) {
            _ = client.receive(.init(.update, requestID: request.requestID, address: request.address, update: .init(.succeeded, values: ["result": .string(Self.json(result))])))
        }
        static func json(_ object: Any) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self) }
    }
    private let flow = "11111111-1111-4111-8111-111111111111"
    private let revision = "22222222-2222-4222-8222-222222222222"
    private let storage = String(repeating: "a", count: 64)
    private func arguments(_ name: String, _ values: [String: Any], body: String = "") -> [String: String] {
        ["address": "example.catalog/" + name, "arguments": Harness.json(values), "body": body]
    }
    private func inspectArguments() -> [String: String] { arguments("flow_catalog_inspect", ["version": 1, "kind": "source", "flow": flow, "revision": revision, "storage": storage]) }
    private func page(_ response: [String: Any]) throws -> [String: Any] {
        let items = try XCTUnwrap(response["contentItems"] as? [[String: Any]])
        return try FlowCatalogJSON.object(try XCTUnwrap(items.first?["text"] as? String), limit: 90_000)
    }
    private func assertFailure(_ operation: () async throws -> Any, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await operation(); XCTFail("Expected a refusal", file: file, line: line) } catch {}
    }
    private func waitForInvoke(_ harness: Harness) async throws -> PluginBusMessage {
        for _ in 0..<1000 {
            if let request = harness.sent.first(where: { $0.operation == .invoke }) { return request }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw AgentError.message("Fixture did not invoke")
    }

    func testPartialGrantExactDescriptorFeaturesAndActiveTurn() async throws {
        let h = Harness(names: ["flow_catalog_discover"])
        XCTAssertEqual(h.client.definitions.count, 3)
        let body = try page(await h.client.run(name: "nook_flow_catalog", arguments: [:]))
        XCTAssertTrue((body["text"] as? String)?.contains("flow_catalog_discover") == true)
        var changed = h.entries(["flow_catalog_discover"])[0]; changed.action?.title += "!"
        XCTAssertFalse(FlowCatalogClient.matches(changed))
        h.client.update(catalog: [changed], features: PluginFlowCatalog.requiredFeatures, session: h.session)
        XCTAssertTrue(h.client.definitions.isEmpty)
        h.update(names: ["flow_catalog_discover"], features: ["actions-v1"])
        XCTAssertTrue(h.client.definitions.isEmpty)
        h.update(names: ["flow_catalog_discover"])
        h.client.cancelTurn()
        await assertFailure { try await h.client.run(name: "nook_flow_catalog", arguments: [:]) }
        h.client.beginTurn()
        _ = try await h.client.run(name: "nook_flow_catalog", arguments: [:])
    }

    func testAllowlistAndStrictArgumentsPreventUnregisteredDispatch() async throws {
        let h = Harness(names: ["flow_catalog_discover"])
        let invalid: [[String: String]] = [
            ["address": "example.catalog/run_draft", "arguments": "{}", "body": ""],
            ["address": "example.catalog/flow_catalog_discover", "arguments": "{\"version\":1,\"version\":1,\"kind\":\"flows\"}", "body": ""],
            arguments("flow_catalog_discover", ["version": 1, "kind": "flows", "extra": true]),
            arguments("flow_catalog_discover", ["version": 1, "kind": "flows"], body: "{}"),
            arguments("flow_catalog_discover", ["version": 1.5, "kind": "flows"])
        ]
        for args in invalid { await assertFailure { try await h.client.run(name: "nook_flow_call", arguments: args) } }
        XCTAssertTrue(h.sent.isEmpty)
        XCTAssertThrowsError(try FlowCatalogJSON.object("{\"x\":{\"a\":1,\"\\u0061\":2}}", limit: 100))
        XCTAssertNil(FlowCatalogJSON.integer(["version": true], "version"))
        XCTAssertNil(FlowCatalogJSON.boolean(["executed": 0], "executed"))
    }

    func testReentrantDiscoveryResultCompletesOriginalRequest() async throws {
        let h = Harness(names: ["flow_catalog_discover"])
        h.onSend = { request in
            if request.operation == .invoke {
                h.running(request)
                h.success(request, ["version": 1, "kind": "flows", "items": [], "next": ""])
            }
        }
        let result = try page(await h.client.run(name: "nook_flow_call", arguments: arguments("flow_catalog_discover", ["version": 1, "kind": "flows"])))
        XCTAssertEqual(result["request"] as? String, h.sent[0].requestID.uuidString.lowercased())
        XCTAssertTrue(h.sent.allSatisfy { $0.operation != .cancel })
    }

    func testMaximumUnicodeControlBodyAllPagesFitModelBudgetAndHash() async throws {
        let h = Harness(names: ["flow_catalog_inspect"])
        var raw = Data(String(repeating: "\u{0}\\\"🌿é\n", count: 20_000).utf8)
        while raw.count > 262_144 { raw.removeLast() }
        while String(data: raw, encoding: .utf8) == nil { raw.removeLast() }
        raw.append(Data(repeating: 65, count: 262_144 - raw.count))
        let bytes = raw
        h.onSend = { request in
            if request.operation == .invoke { h.running(request); h.ready(request) }
            if request.frame?.values["kind"] == .string("fetch") {
                h.output(request, body: bytes)
                h.success(request, ["version": 1, "request": request.requestID.uuidString.lowercased(), "bytes": bytes.count, "sha256": FlowCatalogClient.sha(bytes)])
            }
        }
        var response = try await h.client.run(name: "nook_flow_call", arguments: inspectArguments())
        var assembled = Data(), pages = 0
        while true {
            XCTAssertLessThanOrEqual(try JSONSerialization.data(withJSONObject: response).count, 96_000)
            let result = try page(response), text = try XCTUnwrap(result["text"] as? String)
            let data = Data(text.utf8)
            XCTAssertEqual(result["offset"] as? Int, assembled.count)
            XCTAssertEqual(result["pageSHA256"] as? String, FlowCatalogClient.sha(data))
            XCTAssertEqual(result["sha256"] as? String, FlowCatalogClient.sha(bytes))
            assembled.append(data); pages += 1
            guard let next = result["next"] as? Int else { break }
            response = try await h.client.run(name: "nook_flow_result", arguments: ["handle": try XCTUnwrap(result["handle"] as? String), "offset": String(next)])
        }
        XCTAssertEqual(assembled, bytes)
        XCTAssertLessThan(pages + 2, 48, "A full maximum body must fit the existing turn tool-call allowance")
    }

    func testMalformedOrderedOutputFailsAndLateOutputIsDiscarded() async throws {
        for fault in ["sequence", "base64", "index", "hash", "earlyEnd", "duplicateBegin", "unknownField"] {
            let h = Harness(names: ["flow_catalog_inspect"]), bytes = Data("abc".utf8)
            h.onSend = { request in
                if request.operation == .invoke { h.running(request); h.ready(request) }
                if request.frame?.values["kind"] == .string("fetch") {
                    var begin: [String: PluginValue] = ["kind": .string("begin"), "bytes": .number(3), "sha256": .string(fault == "hash" ? String(repeating: "a", count: 64) : FlowCatalogClient.sha(bytes)), "meta": .string("{}")]
                    if fault == "unknownField" { begin["data"] = .string("hidden") }
                    h.frame(request, begin, sequence: fault == "sequence" ? 9 : nil)
                    if fault == "duplicateBegin" { h.frame(request, begin) }
                    if fault != "earlyEnd" {
                        h.frame(request, ["kind": .string("chunk"), "index": .number(fault == "index" ? 1 : 0), "data": .string(fault == "base64" ? "YWJj\n" : "YWJj")])
                    }
                    h.frame(request, ["kind": .string("end")])
                }
            }
            await assertFailure { try await h.client.run(name: "nook_flow_call", arguments: self.inspectArguments()) }
            let request = try XCTUnwrap(h.sent.first)
            XCTAssertTrue(h.sent.contains { $0.operation == .cancel })
            XCTAssertFalse(h.client.receive(.init(.update, requestID: request.requestID, update: .init(.succeeded))))
        }
    }

    func testAuthorUploadHashesOriginalBytesPacesSealAndPropose() async throws {
        let h = Harness(names: ["flow_catalog_author"])
        let body = Harness.json(["profile": PluginFlowCatalog.nativeProfile, "padding": String(repeating: "café🌿", count: 500)])
        var uploaded = Data(), streamTimes: [TimeInterval] = [], opening: PluginBusMessage?
        h.onSend = { request in
            if request.operation == .invoke { opening = request; h.running(request); h.ready(request) }
            guard request.operation == .stream else { return }
            streamTimes.append(ProcessInfo.processInfo.systemUptime)
            switch request.frame?.values["kind"] {
            case .string("chunk"):
                if case .string(let encoded) = request.frame?.values["data"] { uploaded.append(Data(base64Encoded: encoded)!) }
            case .string("seal"):
                h.frame(request, ["kind": .string("sealed"), "meta": .string("{\"version\":1,\"state\":\"sealed\"}")])
            case .string("propose"):
                h.success(request, ["version": 1, "request": request.requestID.uuidString.lowercased(), "mode": "draft", "flow": self.flow,
                                    "revision": self.revision, "storage": self.storage, "review": self.storage, "callable": false, "executable": true])
            default: break
            }
        }
        _ = try await h.client.run(name: "nook_flow_call", arguments: arguments("flow_catalog_author", ["version": 1, "profile": PluginFlowCatalog.nativeProfile, "mode": "create", "flow": flow], body: body))
        XCTAssertEqual(uploaded, Data(body.utf8))
        XCTAssertEqual(opening?.values?["bytes"], .number(Double(uploaded.count)))
        XCTAssertEqual(opening?.values?["sha256"], .string(FlowCatalogClient.sha(uploaded)))
        let frames = h.sent.compactMap(\.frame)
        XCTAssertEqual(frames.map(\.sequence), Array(0..<UInt64(frames.count)))
        XCTAssertEqual(frames.suffix(2).compactMap { $0.values["kind"] }, [.string("seal"), .string("propose")])
        for pair in zip(streamTimes, streamTimes.dropFirst()) { XCTAssertGreaterThanOrEqual(pair.1 - pair.0, 0.069) }
    }

    func testFixtureUploadNeedsSeparateInspectAndVerifiesOutput() async throws {
        let sourceFlow = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", sourceRevision = "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"
        let values: [String: Any] = ["version": 1, "profile": PluginFlowCatalog.nativeProfile, "mode": "fixture", "flow": sourceFlow, "revision": sourceRevision, "storage": storage]
        let args = arguments("flow_catalog_test", values, body: "{\"inputs\":{},\"fixtures\":{}}")
        let refused = Harness(names: ["flow_catalog_test"])
        await assertFailure { try await refused.client.run(name: "nook_flow_call", arguments: args) }
        XCTAssertTrue(refused.sent.isEmpty)
        let h = Harness(names: ["flow_catalog_test", "flow_catalog_inspect"])
        let output = Data("{\"mode\":\"fixture\",\"outputs\":{},\"steps\":[]}".utf8)
        h.onSend = { request in
            if request.operation == .invoke { h.running(request); h.ready(request) }
            if request.frame?.values["kind"] == .string("seal") { h.frame(request, ["kind": .string("sealed"), "meta": .string("{\"version\":1,\"state\":\"sealed\"}")]) }
            if request.frame?.values["kind"] == .string("test") {
                h.output(request, body: output)
                h.success(request, ["version": 1, "mode": "fixture", "phase": "simulated", "flow": sourceFlow.lowercased(), "revision": sourceRevision.lowercased(), "storage": self.storage])
            }
        }
        let result = try page(await h.client.run(name: "nook_flow_call", arguments: args))
        XCTAssertEqual(result["text"] as? String, String(decoding: output, as: UTF8.self))
        XCTAssertFalse(h.sent.contains { $0.frame?.values["kind"] == .string("propose") })
    }

    func testPublishSurvivesUnrelatedPublicationCatalogAdditionBeforeTerminal() async throws {
        let h = Harness(names: ["flow_catalog_publish"])
        h.onSend = { request in
            guard request.operation == .invoke else { return }
            h.running(request)
            h.update(names: ["flow_catalog_publish"], extra: [.init(address: .init("local.published", "run_published"), action: .init("run_published", title: "Published", effect: .localChange))])
            h.success(request, ["version": 1, "request": request.requestID.uuidString.lowercased(), "mode": "publication", "flow": self.flow,
                                "revision": self.revision, "storage": self.storage, "review": self.storage,
                                "address": "local.published/run_published", "descriptor": self.storage, "callable": true, "executed": false, "status": "published"])
        }
        _ = try await h.client.run(name: "nook_flow_call", arguments: arguments("flow_catalog_publish", ["version": 1, "profile": PluginFlowCatalog.nativeProfile, "flow": flow, "base": revision, "base_storage": storage]))
        XCTAssertEqual(h.sent.filter { $0.operation == .invoke }.count, 1)
        XCTAssertFalse(h.sent.contains { $0.operation == .cancel })
    }

    func testObserveValidatesObservedOriginalNotObserveRequestID() async throws {
        for phase in ["active", "completed", "uncertain"] {
            let h = Harness(names: ["flow_catalog_observe"]), original = UUID()
            h.onSend = { request in
                if request.operation == .invoke {
                    h.running(request); h.success(request, ["version": 1, "request": original.uuidString.lowercased(), "phase": phase, "valuesAvailable": false])
                }
            }
            let result = try page(await h.client.run(name: "nook_flow_call", arguments: arguments("flow_catalog_observe", ["version": 1, "request": original.uuidString.lowercased()])))
            XCTAssertTrue((result["text"] as? String)?.contains(original.uuidString.lowercased()) == true)
        }
        let h = Harness(names: ["flow_catalog_observe"])
        h.onSend = { request in if request.operation == .invoke { h.success(request, ["version": 1, "phase": "active", "valuesAvailable": false]) } }
        await assertFailure { try await h.client.run(name: "nook_flow_call", arguments: self.arguments("flow_catalog_observe", ["version": 1, "request": UUID().uuidString])) }
    }

    func testRevocationReconnectFeatureLossAndReentrantLateResultCancel() async throws {
        for change in ["revoke", "session", "features", "stop"] {
            let h = Harness(names: ["flow_catalog_discover"])
            let task = Task { try await h.client.run(name: "nook_flow_call", arguments: self.arguments("flow_catalog_discover", ["version": 1, "kind": "flows"])) }
            let request = try await waitForInvoke(h)
            h.onSend = { message in
                if message.operation == .cancel { XCTAssertFalse(h.client.receive(.init(.update, requestID: message.requestID, update: .init(.succeeded)))) }
            }
            switch change {
            case "revoke": h.update(names: [])
            case "session": h.update(names: ["flow_catalog_discover"], session: UUID())
            case "features": h.update(names: ["flow_catalog_discover"], features: ["actions-v1"])
            default: h.client.cancelTurn()
            }
            await assertFailure { try await task.value }
            XCTAssertEqual(h.sent.filter { $0.operation == .cancel }.count, 1)
            XCTAssertFalse(h.client.receive(.init(.update, requestID: request.requestID, update: .init(.succeeded))))
        }
    }

    func testStalledRequestAndTaskCancellationHaveIndependentRetirement() async throws {
        let h = Harness(names: ["flow_catalog_discover"], timeout: .milliseconds(60))
        await assertFailure { try await h.client.run(name: "nook_flow_call", arguments: self.arguments("flow_catalog_discover", ["version": 1, "kind": "flows"])) }
        XCTAssertEqual(h.sent.filter { $0.operation == .cancel }.count, 1)
        let h2 = Harness(names: ["flow_catalog_discover"])
        let task = Task { try await h2.client.run(name: "nook_flow_call", arguments: self.arguments("flow_catalog_discover", ["version": 1, "kind": "flows"])) }
        _ = try await waitForInvoke(h2); task.cancel()
        await assertFailure { try await task.value }
        XCTAssertEqual(h2.sent.filter { $0.operation == .cancel }.count, 1)
    }

    func testOpeningReviewGets120SecondsAndRepeatedReviewCannotRenewIt() async throws {
        var clock: TimeInterval = 100
        let h = Harness(names: ["flow_catalog_publish"], now: { clock })
        let task = Task { try await h.client.run(name: "nook_flow_call", arguments: self.arguments("flow_catalog_publish", ["version": 1, "profile": PluginFlowCatalog.nativeProfile, "flow": self.flow, "base": self.revision, "base_storage": self.storage])) }
        let request = try await waitForInvoke(h)
        _ = h.client.receive(.init(.update, requestID: request.requestID, update: .init(.waitingReview)))
        clock = 190
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(h.sent.contains { $0.operation == .cancel }, "Native opening review must survive the ordinary 30s execution timeout")
        _ = h.client.receive(.init(.update, requestID: request.requestID, update: .init(.waitingReview)))
        clock = 221
        await assertFailure { try await task.value }
        XCTAssertEqual(h.sent.filter { $0.operation == .cancel }.count, 1)
    }

    func testPageOrderAndRefreshExpireHandles() async throws {
        let h = Harness(names: ["flow_catalog_discover"], budget: 4096)
        let first = try page(await h.client.run(name: "nook_flow_catalog", arguments: [:]))
        let handle = try XCTUnwrap(first["handle"] as? String), next = try XCTUnwrap(first["next"] as? Int)
        await assertFailure { try await h.client.run(name: "nook_flow_result", arguments: ["handle": handle, "offset": "0"]) }
        h.update(names: ["flow_catalog_discover"])
        await assertFailure { try await h.client.run(name: "nook_flow_result", arguments: ["handle": handle, "offset": String(next)]) }
        h.client.beginTurn()
        await assertFailure { try await h.client.run(name: "nook_flow_result", arguments: ["handle": handle, "offset": String(next)]) }
    }

    func testGrammarExampleIsCompleteNativeAndFixtureShape() throws {
        let body = try XCTUnwrap(FlowCatalogGrammar.example["body"] as? [String: Any])
        let document = try XCTUnwrap(body["document"] as? [String: Any])
        XCTAssertEqual(document["schemaVersion"] as? Int, 3)
        XCTAssertEqual(document["id"] as? String, flow)
        XCTAssertEqual((document["nodes"] as? [Any])?.count, 2)
        XCTAssertNoThrow(try FlowCatalogJSON.object(Harness.json(body), limit: 262144))
        XCTAssertNoThrow(try FlowCatalogJSON.object(Harness.json(FlowCatalogGrammar.example["fixtureBody"]!), limit: 262144))
    }
}
