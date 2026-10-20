import AppKit
import AuthenticationServices
import Combine
import MCP
import ModuleCore
import NookPluginSDK

@MainActor final class MCPBrowserSignIn: NSObject, OAuthAuthorizationDelegate, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    private var session: ASWebAuthenticationSession?
    nonisolated func presentAuthorizationURL(_ url: URL) async throws -> URL {
        guard url.scheme == "https", url.user == nil, url.password == nil else { throw AgentError.message("The MCP server requested an insecure sign-in URL.") }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task { @MainActor in
                    let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "neronook-agent-mcp") { result, error in
                        if let result { continuation.resume(returning: result) } else { continuation.resume(throwing: error ?? CancellationError()) }
                    }
                    self.session = session; session.presentationContextProvider = self; session.prefersEphemeralWebBrowserSession = true
                    if !session.start() { self.session = nil; continuation.resume(throwing: AgentError.message("Could not open MCP sign-in.")) }
                }
            }
        } onCancel: { Task { @MainActor in self.session?.cancel(); self.session = nil } }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow() }
    func cancel() { session?.cancel(); session = nil }
}

@MainActor final class AgentToolbox: ObservableObject {
    @Published private(set) var settings = AgentIntegrationSettings()
    @Published var visible = false
    @Published private(set) var states: [UUID: String] = [:]
    @Published private(set) var storageError: String?
    @Published private(set) var connecting = Set<UUID>()
    let reviews = AgentToolReviews()
    let mac = MacAgentTools()
    var changed: (() -> Void)?
    var invalidated: (() -> Void)?
    private var sessions: [UUID: AgentMCPSession] = [:]
    private var connectionTasks: [UUID: Task<Void, Never>] = [:]
    private var auth: [UUID: MCPBrowserSignIn] = [:]
    private var epoch = UUID()
    private let file: URL
    private var observers: [NSObjectProtocol] = []
    private var locked = false
    private let test = CommandLine.arguments.contains("--protocol-test")
    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NeroNook-Plugins/cafe.nero.plugin.agent/tools-v1.json")
        if !test { do { settings = try .load(file) } catch { storageError = "Tool settings could not be loaded. The file was kept; tools are disabled until repaired."; settings.web = false } }
        reviews.changed = { [weak self] in self?.objectWillChange.send(); self?.changed?() }
        mac.review = { [weak self] review in guard let self, !self.locked else { throw CancellationError() }; try await self.reviews.request(review) }
        if !test {
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.disconnectAll() } })
            for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
                observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.lock(true) } })
            }
            for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
                observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.lock(false) } })
            }
            observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.lock(true) } })
            observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.lock(false) } })
        }
    }
    var definitions: [[String: Any]] { IntegrationTools.definitions(mac: settings.mac && !locked, mcp: !sessions.isEmpty && !locked) }
    var web: Bool { settings.web && !locked && storageError == nil && !test }
    var keys: [String: Set<String>] { Dictionary(uniqueKeysWithValues: definitions.compactMap { value in guard let name = value["name"] as? String else { return nil }; return (name, IntegrationTools.argumentKeys[name]!) }) }
    var summary: String { "\(web ? "Web on" : "Web off") · \(settings.mac ? "Mac on" : "Mac off") · \(sessions.count) MCP connected" }
    private func lock(_ value: Bool) { locked = value; if value { disconnectAll(); invalidated?() }; changed?() }
    func cancelTurn() { epoch = UUID(); reviews.cancel(); mac.clear(); for session in sessions.values { session.cancel() }; changed?() }
    func update(web: Bool? = nil, mac: Bool? = nil) {
        guard storageError == nil else { return }; invalidated?(); cancelTurn()
        if let web { settings.web = web }; if let mac { settings.mac = mac }; persist()
    }
    func save(_ configuration: MCPConnection, secret: String) throws {
        guard storageError == nil, !test else { throw AgentError.message("Tool settings are unavailable.") }; try configuration.validate()
        if !secret.isEmpty { try PluginCredentials(pluginID: "cafe.nero.plugin.agent").save(secret, account: "mcp." + configuration.id.uuidString) }
        invalidated?(); disconnect(configuration.id)
        if let i = settings.servers.firstIndex(where: { $0.id == configuration.id }) { settings.servers[i] = configuration }
        else { guard settings.servers.count < 16 else { throw AgentError.message("Remove a connection before adding another.") }; settings.servers.append(configuration) }
        persist()
    }
    func remove(_ id: UUID) {
        invalidated?(); disconnect(id); settings.servers.removeAll { $0.id == id }; try? PluginCredentials(pluginID: "cafe.nero.plugin.agent").remove(account: "mcp." + id.uuidString); persist()
    }
    func connect(_ id: UUID) {
        guard !test, !locked, storageError == nil, !connecting.contains(id), let configuration = settings.servers.first(where: { $0.id == id }) else { return }
        invalidated?(); disconnect(id); connecting.insert(id); states[id] = "Connecting…"
        epoch = UUID()
        let session = AgentMCPSession(configuration)
        session.onDisconnect = { [weak self, weak session] in
            guard let self, let session, self.sessions[id] === session else { return }
            self.sessions[id] = nil
            self.connectionTasks.removeValue(forKey: id)?.cancel()
            self.auth.removeValue(forKey: id)?.cancel()
            self.connecting.remove(id)
            self.states[id] = "Connection closed. Reconnect to use this server again."
            self.invalidated?(); self.cancelTurn(); self.changed?()
        }
        session.elicitation = { [weak self, weak session] params in
            guard let self, let session, !self.locked, self.sessions[id] === session else { return .init(action: .cancel) }
            let token = self.epoch
            // No secret form collection. External account credentials belong on the service's sign-in page.
            switch params {
            case .url(let request):
                guard let url = URL(string: request.url), url.scheme == "https", url.user == nil, url.password == nil else { return .init(action: .decline) }
                try await self.reviews.request(.init(title: "\(configuration.name) requests a website", detail: "\(request.message)\n\n\(url.absoluteString)", consequence: "Opens this external sign-in/confirmation page. Enter credentials only there, never in chat."))
                guard !self.locked, self.epoch == token, self.sessions[id] === session else { return .init(action: .cancel) }
                NSWorkspace.shared.open(url); return .init(action: .accept)
            case .form: return .init(action: .decline)
            }
        }
        sessions[id] = session
        connectionTasks[id] = Task { [weak self] in
            guard let self else { return }
            do {
                let secret = configuration.authentication == "bearer" ? try PluginCredentials(pluginID: "cafe.nero.plugin.agent").read(account: "mcp." + id.uuidString) : nil
                var authorizer: OAuthAuthorizer?
                if configuration.transport == "http", configuration.authentication == "oauth" {
                    let browser = MCPBrowserSignIn(); auth[id] = browser
                    let config = OAuthConfiguration(grantType: .authorizationCode, authentication: .none(clientID: configuration.clientID), authorizationRedirectURI: URL(string: "neronook-agent-mcp://oauth/callback")!, clientName: "Nero Agent", authorizationDelegate: browser)
                    authorizer = OAuthAuthorizer(configuration: config)
                }
                try await session.connect(secret: secret, authorizer: authorizer)
                guard !Task.isCancelled, self.sessions[id] === session else { session.disconnect(); return }
                self.states[id] = "Connected · \(session.tools.count) tools"; self.connecting.remove(id); self.connectionTasks[id] = nil; self.changed?()
            } catch {
                guard self.sessions[id] === session else { return }
                session.disconnect(); self.sessions[id] = nil; self.auth[id]?.cancel(); self.auth[id] = nil; self.connecting.remove(id); self.connectionTasks[id] = nil
                // Raw server errors can echo URLs, headers or secrets. Keep those out of UI/history.
                self.states[id] = "Connection failed. Check endpoint, executable or sign-in, then reconnect."; self.changed?()
            }
        }; changed?()
    }
    func disconnect(_ id: UUID) {
        cancelTurn(); connectionTasks.removeValue(forKey: id)?.cancel(); sessions.removeValue(forKey: id)?.disconnect(); auth.removeValue(forKey: id)?.cancel(); connecting.remove(id); states[id] = "Disconnected"; changed?()
    }
    func disconnectAll() { for id in Array(sessions.keys) { disconnect(id) }; cancelTurn() }
    private func persist() { do { if !test { try settings.save(file) } } catch { storageError = "Could not save tool settings. Tools were disconnected; the prior file was retained."; disconnectAll() }; changed?() }
    func run(_ name: String, _ args: [String: String]) async throws -> [String: Any] {
        guard !test, !locked, storageError == nil, keys[name] != nil else { throw AgentError.message("This integration is disabled or disconnected.") }
        let token = epoch
        if name.hasPrefix("mac_") { let result = try await mac.run(name, args); guard token == epoch else { throw CancellationError() }; return result }
        if name == "mcp_connections" {
            let entries = sessions.keys.filter { !connecting.contains($0) }.compactMap { id -> [String: String]? in guard let server = settings.servers.first(where: { $0.id == id }) else { return nil }; return ["id": id.uuidString, "name": server.name] }
            return AgentTools.response(try IntegrationTools.json(entries))
        }
        guard let id = UUID(uuidString: args["server"] ?? ""), !connecting.contains(id), let session = sessions[id], let configuration = settings.servers.first(where: { $0.id == id }) else { throw AgentError.message("Choose a connected MCP server from mcp_connections.") }
        let result: [String: Any]
        switch name {
        case "mcp_tools": result = AgentTools.response(try session.toolPage(cursor: args["cursor"]!))
        case "mcp_call":
            guard let tool = session.tools.first(where: { $0.name == args["tool"] }) else { throw AgentError.message("Discover the exact MCP tool first.") }
            let parsed = try IntegrationTools.parseArguments(args["arguments"]!)
            let canonical = try IntegrationTools.json(parsed)
            if !configuration.trustedReads || tool.annotations.readOnlyHint != true || tool.annotations.destructiveHint == true {
                try await reviews.request(.init(title: "\(configuration.name) · \(tool.title ?? tool.name)", detail: "Tool: \(tool.name)\n" + canonical, consequence: "Calls this external tool with these exact arguments. Server annotations are hints; changes may not be reversible. Stop requests cancellation but cannot undo completed remote effects."))
            }
            guard token == epoch, sessions[id] === session else { throw CancellationError() }
            result = try await session.call(tool.name, arguments: canonical)
        case "mcp_resources": result = AgentTools.response(try await session.resources(cursor: args["cursor"]!))
        case "mcp_read":
            if !configuration.trustedReads { try await reviews.request(.init(title: "Read \(configuration.name) resource", detail: args["uri"]!, consequence: "Sends this resource's content to your connected agent for this answer.")) }
            guard token == epoch else { throw CancellationError() }; result = AgentTools.response(try await session.read(args["uri"]!))
        case "mcp_prompts": result = AgentTools.response(try await session.prompts(cursor: args["cursor"]!))
        case "mcp_prompt": result = AgentTools.response(try await session.prompt(args["name"]!, arguments: args["arguments"]!))
        default: throw AgentError.message("Unknown integration tool.")
        }
        guard token == epoch, sessions[id] === session else { throw CancellationError() }; return result
    }
}
