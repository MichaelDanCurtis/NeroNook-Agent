import Foundation
import ModuleCore

@main struct Check {
    @MainActor static func main() async throws {
        if CommandLine.arguments.contains("app-server") {
            var accountRequest: Any?, denied = 0
            func emit(_ value: [String: Any]) { var data = try! JSONSerialization.data(withJSONObject: value); data.append(10); FileHandle.standardOutput.write(data) }
            while let line = readLine(), let data = line.data(using: .utf8), let message = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let method = message["method"] as? String, let id = message["id"] {
                    if method == "initialize" { emit(["id": id, "result": ["userAgent": "neronook_agent/0.142.5 (fixture)"]]) }
                    if method == "config/read" { emit(["id": id, "result": ["config": ["web_search": "disabled", "features": Dictionary(uniqueKeysWithValues: ["shell_tool", "unified_exec", "apps", "plugins", "hooks", "computer_use", "browser_use", "multi_agent", "code_mode"].map { ($0, false) })]]]) }
                    if method == "account/read" {
                        accountRequest = id
                        for (index, method) in ["item/commandExecution/requestApproval", "item/fileChange/requestApproval", "account/chatgptAuthTokens/refresh", "item/tool/call", "item/permissions/requestApproval"].enumerated() {
                            emit(["id": 900 + index, "method": method, "params": ["command": "unapproved", "path": "outside"]])
                        }
                    }
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
        client.stop()
        let fixture = CodexClient(directory: root.appendingPathComponent("fixture"))
        try await fixture.start(binary: binary)
        let rejected = try await fixture.request("account/read", ["refreshToken": false])
        guard rejected["denied"] as? Int == 5 else { throw AgentError.message("A server request was not denied") }
        fixture.stop()
        print("PASS: five forged tool, permission and credential requests denied. No execution or credential callback exposed.")
        print("PASS: outside-file read/write and arbitrary execution denied; isolated runtime initialized; shell and connectors disabled; no desktop account inherited.")
    }
}
