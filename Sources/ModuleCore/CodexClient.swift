import Foundation
import NookPluginSDK

public enum AgentError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public enum AgentRuntime {
    public static let testedVersion = "codex-cli 0.142.5"
    public static var defaultBinary: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex") }
    public static let configuration = """
    approval_policy = "never"
    sandbox_mode = "read-only"
    web_search = "disabled"
    cli_auth_credentials_store = "file"
    project_doc_max_bytes = 0
    allow_login_shell = false
    [history]
    persistence = "none"
    [analytics]
    enabled = false
    [features]
    shell_tool = false
    unified_exec = false
    apps = false
    plugins = false
    hooks = false
    memories = false
    chronicle = false
    browser_use = false
    browser_use_external = false
    computer_use = false
    in_app_browser = false
    image_generation = false
    workspace_dependencies = false
    multi_agent = false
    goals = false
    code_mode = false
    tool_suggest = false
    skill_mcp_dependency_install = false
    shell_snapshot = false
    realtime_conversation = false
    [apps._default]
    enabled = false
    """
    public static func sandbox(binary: URL, directory: URL) -> String {
        func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        let path = directory.resolvingSymlinksInPath().path
        return """
        (version 1)
        (allow default)
        (deny file-read-data)
        (deny file-write*)
        (deny process-exec)
        (allow process-fork)
        (allow process-exec (literal \(quote(binary.resolvingSymlinksInPath().path))))
        (allow signal (target self))
        (allow sysctl-read)
        (allow process-info* (target self))
        (allow file-map-executable)
        (allow mach-lookup)
        (allow network*)
        (allow file-read-metadata)
        (allow file-read-data (vnode-type DIRECTORY))
        (allow file-read-data (subpath "/System") (subpath "/usr") (subpath "/Library") (subpath "/private/etc") (subpath "/private/var/db") (subpath "/dev") (literal \(quote(binary.resolvingSymlinksInPath().path))) (subpath \(quote(path))))
        (allow file-write* (subpath \(quote(path))) (literal "/dev/null"))
        """
    }
}

/// Bounded stdio client. Owns only its dedicated runtime; never desktop auth/config.
@MainActor public final class CodexClient {
    public var event: ((String, [String: Any]) -> Void)?
    public var failed: ((String) -> Void)?
    public var diagnostic: ((String) -> Void)?
    public let directory: URL
    private var process: Process?
    private var input: Pipe?
    private var buffer = Data()
    private var counter = 0
    private var generation = UUID()
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    public init(directory: URL) { self.directory = directory }
    public func start(binary: URL = AgentRuntime.defaultBinary) async throws {
        stop()
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { throw AgentError.message("Choose the installed Codex runtime in Settings.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let work = directory.appendingPathComponent("workspace"), tmp = directory.appendingPathComponent("tmp")
        for folder in [work, tmp] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        try Data(AgentRuntime.configuration.utf8).write(to: directory.appendingPathComponent("config.toml"), options: .atomic)
        let child = Process(), output = Pipe(), input = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        child.arguments = ["-p", AgentRuntime.sandbox(binary: binary, directory: directory), binary.path, "app-server", "--strict-config", "--listen", "stdio://"]
        child.currentDirectoryURL = work
        child.environment = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path, "CODEX_HOME": directory.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": tmp.path]
        child.standardInput = input; child.standardOutput = output
        if diagnostic != nil {
            let errors = Pipe(); child.standardError = errors
            errors.fileHandleForReading.readabilityHandler = { [weak self] file in
                let data = file.availableData
                Task { @MainActor in self?.diagnostic?(String(decoding: data.prefix(2000), as: UTF8.self)) }
            }
        } else { child.standardError = FileHandle.nullDevice }
        let token = UUID(); generation = token; process = child; self.input = input; buffer = Data()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if data.isEmpty { self.stop(); self.failed?("Codex connection ended. Reconnect when ready."); return }
                do { try self.receive(data) } catch { self.stop(); self.failed?("Codex sent an invalid or oversized response.") }
            }
        }
        child.terminationHandler = { [weak self] _ in Task { @MainActor in
            guard let self, self.generation == token else { return }; self.stop(); self.failed?("The isolated Codex runtime stopped. Check its installed version and reconnect.")
        } }
        try child.run()
        let initialization = try await request("initialize", ["clientInfo": ["name": "neronook_agent", "title": "Nero Agent", "version": "0.1.0"], "capabilities": ["experimentalApi": false]])
        guard (initialization["userAgent"] as? String)?.hasPrefix("neronook_agent/0.142.5 ") == true else {
            stop(); throw AgentError.message("This preview was verified with Codex 0.142.5. Its isolation must be checked before using a different runtime version.")
        }
        try send(["method": "initialized", "params": [:]])
        let result = try await request("config/read", ["includeLayers": false])
        guard let config = result["config"] as? [String: Any], config["web_search"] as? String == "disabled",
              let features = config["features"] as? [String: Any],
              ["shell_tool", "unified_exec", "apps", "plugins", "hooks", "computer_use", "browser_use", "multi_agent", "code_mode"].allSatisfy({ features[$0] as? Bool == false }) else {
            stop(); throw AgentError.message("This runtime did not accept Nero Agent’s restricted configuration.")
        }
    }
    public func request(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        guard process?.isRunning == true else { throw AgentError.message("Connect Codex first.") }
        counter += 1; let id = counter; let token = generation
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try send(["id": id, "method": method, "params": params]) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error) }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard let self, self.generation == token else { return }
                self.pending.removeValue(forKey: id)?.resume(throwing: AgentError.message("Codex did not respond in time."))
            }
        }
    }
    public func stop() {
        generation = UUID(); let child = process; process = nil
        try? input?.fileHandleForWriting.close(); input = nil
        for continuation in pending.values { continuation.resume(throwing: AgentError.message("Codex connection closed.")) }; pending = [:]
        if child?.isRunning == true { child?.terminate() }
        if let child { DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if child.isRunning { kill(child.processIdentifier, SIGKILL) } } }
    }
    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        guard data.count <= 131072 else { throw AgentError.message("This request is too large.") }
        guard let input else { throw AgentError.message("Codex connection closed.") }; data.append(10); try input.fileHandleForWriting.write(contentsOf: data)
    }
    private func receive(_ data: Data) throws {
        guard buffer.count + data.count <= 2_097_152 else { throw AgentError.message("Response too large") }; buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard line.count <= 1_048_576, let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { throw AgentError.message("Invalid response") }
            if let method = object["method"] as? String {
                if let id = object["id"] {
                    // No runtime request can grant tools, credentials, permissions, or side effects.
                    try send(["id": id, "error": ["code": -32601, "message": "This client does not permit runtime tool or permission requests."]])
                } else { event?(method, object["params"] as? [String: Any] ?? [:]) }
            } else if let id = object["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                if let error = object["error"] as? [String: Any] { continuation.resume(throwing: AgentError.message(String((error["message"] as? String ?? "Codex request failed").prefix(400)))) }
                else { continuation.resume(returning: object["result"] as? [String: Any] ?? [:]) }
            }
        }
    }
}
