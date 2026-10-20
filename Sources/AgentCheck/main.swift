import Foundation
import ModuleCore

@main struct Check {
    @MainActor static func main() async throws {
        if CommandLine.arguments.contains("--speech-latency-check") || CommandLine.arguments.contains("--speech-effort-check") {
            do {try await SpeechLatencyCheck.run(binary:AgentRuntime.defaultBinary,compareEffort:CommandLine.arguments.contains("--speech-effort-check"))}
            catch {print("Authored speech timing check could not complete. No credentials or raw service errors were logged.");exit(1)}
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--mcp-catalog"), CommandLine.arguments.count > index+1 {
            var config = MCPConnection(); config.endpoint = CommandLine.arguments[index+1]
            let session = AgentMCPSession(config); defer { session.disconnect() }; try await session.connect()
            print("MCP connected: \(session.tools.count) tools. First names: \(session.tools.prefix(8).map(\.name).joined(separator:", "))"); return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--mcp-check"), CommandLine.arguments.count > index+1 {
            var config = MCPConnection(); config.name = "Local authored qualification"
            let target = CommandLine.arguments[index+1]
            if target.hasPrefix("http") { config.endpoint = target }
            else { config.transport = "stdio"; config.command = "/usr/bin/python3"; config.arguments = [target] }
            let session = AgentMCPSession(config); defer { session.disconnect() }
            try await session.connect()
            guard session.tools.count == 2, try session.toolPage(cursor: "").contains("echo") else { throw AgentError.message("MCP pagination failed") }
            let output = try await session.call("echo", arguments: "{\"text\":\"Nero MCP qualification\"}")
            guard (output["contentItems"] as? [[String:Any]])?.first?["text"] as? String == "MCP receipt: Nero MCP qualification" else { throw AgentError.message("MCP call failed") }
            guard try await session.resources(cursor: "").contains("passage"), try await session.read("nero-test://passage").contains("Ada"), try await session.prompts(cursor: "").contains("describe"), try await session.prompt("describe",arguments:"{\"subject\":\"Nero\"}").contains("Describe Nero") else { throw AgentError.message("MCP resources/prompts failed") }
            if config.transport == "stdio" {
                let pending = Task { try await session.call("slow", arguments: "{}") }
                try await Task.sleep(for: .milliseconds(150));session.cancel()
                do { _ = try await pending.value; throw AgentError.message("MCP cancellation failed") } catch { if error.localizedDescription == "MCP cancellation failed" {throw error} }
                _ = try await session.call("echo",arguments:"{\"text\":\"After Stop\"}")
            }
            print("PASS: real MCP handshake, paginated tools, exact call result, resources, prompt and cancellation/reuse. Authored data only."); return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--account-check"), CommandLine.arguments.count > index + 1 {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NeroNook-Plugins/cafe.nero.plugin.agent/codex-runtime")
            let client = CodexClient(directory: directory)
            defer { client.stop() }
            try await client.start(binary: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            let account = try await client.request("account/read", ["refreshToken": true])
            guard (account["account"] as? [String: Any])?["type"] as? String == "chatgpt" else { print("ACCOUNT CHECK: sign-in needed"); return }
            print("ACCOUNT CHECK: existing managed account present; credential contents remain opaque")
            let models = try await client.request("model/list", [:])
            for entry in (models["data"] as? [[String: Any]] ?? []).prefix(16) {
                if let name = entry["model"] as? String, name.count <= 80,
                   name.range(of: "^[A-Za-z0-9._/-]+$", options: .regularExpression) != nil {
                    print("ACCOUNT CHECK: offered model \(name), default \(entry["isDefault"] as? Bool ?? false)")
                }
            }
            var parameters: [String: Any] = ["cwd": directory.appendingPathComponent("workspace").path, "ephemeral": true, "sandbox": "read-only", "approvalPolicy": "never"]
            if let index = CommandLine.arguments.firstIndex(of: "--model"), CommandLine.arguments.count > index + 1 {
                let name = CommandLine.arguments[index + 1]
                guard name.count <= 80, name.range(of: "^[A-Za-z0-9._/-]+$", options: .regularExpression) != nil else { throw AgentError.message("Invalid model identifier") }
                parameters["model"] = name
            }
            let result = try await client.request("thread/start", parameters)
            if let name = result["model"] as? String, name.count <= 80,
               name.range(of: "^[A-Za-z0-9._/-]+$", options: .regularExpression) != nil {
                print("ACCOUNT CHECK: selected model \(name)")
            }
            guard let id = (result["thread"] as? [String: Any])?["id"] as? String else { throw AgentError.message("No synthetic thread") }
            let (stream, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
            client.event = { method, params in
                guard params["threadId"] as? String == id else { return }
                if method == "error" || method == "turn/completed" {
                    let turn = params["turn"] as? [String: Any]
                    let error = (params["error"] as? [String: Any]) ?? (turn?["error"] as? [String: Any]) ?? [:]
                    let message = (error["message"] as? String ?? "").lowercased()
                    let category = message.contains("usage") || message.contains("limit") || message.contains("quota") ? "usage limit" :
                        message.contains("unauthor") || message.contains("token") || message.contains("auth") ? "authentication" :
                        message.contains("model") ? "model availability" : message.contains("connect") || message.contains("network") ? "network" : "unspecified"
                    print("ACCOUNT CHECK: \(method), \(turn?["status"] as? String ?? "event"), \(category)")
                    if category == "model availability" {
                        // Only bounded model identifiers and known status phrases; never raw service errors.
                        for phrase in ["not supported", "does not exist", "not found", "not available", "unsupported"] where message.contains(phrase) {
                            print("ACCOUNT CHECK: model error category \(phrase)")
                        }
                    }
                    if method == "turn/completed" { continuation.yield(turn?["status"] as? String ?? "unknown"); continuation.finish() }
                }
            }
            _ = try await client.request("turn/start", ["threadId": id, "input": [["type": "text", "text": "Reply with exactly: Shared Apple speech is ready."]], "sandboxPolicy": ["type": "readOnly", "networkAccess": false], "approvalPolicy": "never", "outputSchema": AgentAnswer.schema])
            let timer = Task { try? await Task.sleep(for: .seconds(40)); continuation.finish() }
            var iterator = stream.makeAsyncIterator(); let status = await iterator.next(); timer.cancel()
            print("ACCOUNT CHECK: final \(status ?? "timeout")")
            return
        }
        if CommandLine.arguments.contains("app-server") {
            var accountRequest: Any?, toolRequest: Any?, denied = 0, tools = 0
            func emit(_ value: [String: Any]) { var data = try! JSONSerialization.data(withJSONObject: value); data.append(10); FileHandle.standardOutput.write(data) }
            while let line = readLine(), let data = line.data(using: .utf8), let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let method = message["method"] as? String, let id = message["id"] {
                    if method == "initialize" { emit(["id": id, "result": ["userAgent": "neronook_agent/0.142.5 (fixture)"]]) }
                    if method == "config/read" { emit(["id": id, "result": ["config": ["web_search": "disabled", "features": Dictionary(uniqueKeysWithValues: ["shell_tool", "unified_exec", "apps", "plugins", "hooks", "computer_use", "browser_use", "multi_agent", "code_mode"].map { ($0, false) })]]]) }
                    if method == "test/tools" {
                        toolRequest = id
                        for (index, tool, thread) in [(0, "nook_capabilities", "thread"), (1, "nook_capabilities", "stale"), (2, "shell", "thread")] {
                            emit(["id": 950 + index, "method": "item/tool/call", "params": ["tool": tool, "threadId": thread, "turnId": "turn", "callId": "call-\(index)", "arguments": [String: String]()]])
                        }
                    }
                    if method == "account/read" {
                        accountRequest = id
                        for (index, method) in ["item/commandExecution/requestApproval", "item/fileChange/requestApproval", "account/chatgptAuthTokens/refresh", "item/tool/call", "item/permissions/requestApproval"].enumerated() {
                            emit(["id": 900 + index, "method": method, "params": ["command": "unapproved", "path": "outside"]])
                        }
                    }
                } else if let id = message["id"] as? Int, (950..<953).contains(id) {
                    guard let result = message["result"] as? [String: Any], result["success"] as? Bool == (id == 950) else { exit(9) }
                    tools += 1
                    if tools == 3, let toolRequest { emit(["id": toolRequest, "result": ["checked": tools]]) }
                } else if let id = message["id"] as? Int, (900..<905).contains(id) {
                    guard (message["error"] as? [String: Any])?["code"] as? Int == -32601 else { exit(8) }
                    denied += 1
                    if denied == 5, let accountRequest { emit(["id": accountRequest, "result": ["account": NSNull(), "denied": denied]]) }
                }
            }
            return
        }
        if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--canary" {
            let own = URL(fileURLWithPath: CommandLine.arguments[2]), outside = URL(fileURLWithPath: CommandLine.arguments[3])
            guard (try? String(contentsOf: own, encoding: .utf8)) == "own",
                  (try? String(contentsOf: outside, encoding: .utf8)) == nil else { exit(2) }
            do { try Data("blocked".utf8).write(to: outside); exit(3) } catch {}
            let child = Process(); child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
            do { try child.run(); child.waitUntilExit(); if child.terminationStatus == 0 { exit(4) } } catch {}
            exit(0)
        }
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("nero-agent-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        if CommandLine.arguments.contains("--profile") { print(AgentRuntime.sandbox(binary: AgentRuntime.defaultBinary, directory: root)); return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let own = root.appendingPathComponent("canary"), outside = root.deletingLastPathComponent().appendingPathComponent("nero-outside-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("own".utf8).write(to: own); try Data("outside".utf8).write(to: outside)
        let probe = Process(), binary = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        probe.arguments = ["-p", AgentRuntime.sandbox(binary: binary, directory: root), binary.path, "--canary", own.path, outside.path, "probe"]
        try probe.run(); probe.waitUntilExit()
        guard probe.terminationStatus == 0, try String(contentsOf: outside, encoding: .utf8) == "outside" else { throw AgentError.message("Runtime file/exec containment failed") }
        let client = CodexClient(directory: root)
        client.diagnostic = { FileHandle.standardError.write(Data($0.utf8)) }
        do { try await client.start() } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
        let config = try await client.request("config/read", ["includeLayers": false])
        guard let effective = config["config"] as? [String: Any], effective["web_search"] as? String == "disabled",
              let features = effective["features"] as? [String: Any], features["shell_tool"] as? Bool == false, features["apps"] as? Bool == false else { throw AgentError.message("Isolated configuration check failed") }
        let account = try await client.request("account/read", ["refreshToken": false])
        guard account["account"] is NSNull else { throw AgentError.message("Probe unexpectedly inherited an account") }
        let thread = try await client.request("thread/start", ["cwd": root.appendingPathComponent("workspace").path, "ephemeral": true, "sandbox": "read-only", "approvalPolicy": "never", "dynamicTools": AgentTools.definitions + IntegrationTools.definitions(mac: true, mcp: true), "config": ["web_search": "live"]])
        guard thread["thread"] is [String: Any] else { throw AgentError.message("Runtime rejected registered tools") }
        client.stop()
        let fixture = CodexClient(directory: root.appendingPathComponent("fixture"))
        try await fixture.start(binary: binary)
        let rejected = try await fixture.request("account/read", ["refreshToken": false])
        guard rejected["denied"] as? Int == 5 else { throw AgentError.message("A server request was not denied") }
        fixture.tool = { params in
            _ = try AgentTools.validate(params, thread: "thread", turn: "turn", enabled: true)
            return AgentTools.response("Registered Nook tool fixture")
        }
        let tools = try await fixture.request("test/tools")
        guard tools["checked"] as? Int == 3 else { throw AgentError.message("Registered tool routing failed") }
        fixture.stop()
        print("PASS: real runtime accepts dynamic tool definitions; fixture routes registered tool and rejects stale/unknown calls.")
        print("PASS: five forged tool, permission and credential requests denied. No execution or credential callback exposed.")
        print("PASS: outside-file read/write and arbitrary execution denied; isolated runtime initialized; shell and connectors disabled; no desktop account inherited.")
    }
}
