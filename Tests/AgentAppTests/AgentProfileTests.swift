import XCTest
import Foundation
import Darwin
import NookPluginSDK
@testable import ModuleCore
@testable import ModuleApp

@MainActor private final class ProfileRuntime: AgentReasoningRuntime {
    let directory: URL
    var tool: (([String: Any]) async throws -> [String: Any])?
    var event: ((String, [String: Any]) -> Void)?
    var failed: ((String) -> Void)?
    var starts = 0
    var stops = 0
    init(directory: URL) { self.directory = directory }
    func start(binary: URL) async throws { starts += 1 }
    func stop() { stops += 1 }
    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        if method == "account/read" { return ["account": ["type": "chatgpt", "email": "authored.invalid"]] }
        if method == "model/list" { return ["data": []] }
        return [:]
    }
}

@MainActor private final class ProfileCredentials: AgentCredentialStore {
    var saved: [String: String] = [:]
    var reads: [String] = []
    var removed: [String] = []
    func save(_ value: String, account: String) throws { saved[account] = value }
    func read(account: String) throws -> String { reads.append(account); return saved[account] ?? "" }
    func remove(account: String) throws { removed.append(account); saved[account] = nil }
}

final class AgentProfileTests: XCTestCase {
    private func fixture() throws -> URL {
        // Resolve the existing parent with POSIX realpath, never Foundation's /var alias rewrite.
        let parent = FileManager.default.temporaryDirectory.path
        guard let buffer = realpath(parent, nil) else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { free(buffer) }
        guard let physical = String(validatingUTF8: buffer) else { throw NSError(domain: "AuthoredFixture", code: 1) }
        let root = URL(fileURLWithPath: physical, isDirectory: true).appendingPathComponent("agent-profile-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    @MainActor private func profile(_ root: URL, preferences: AgentMemoryPreferences? = nil,
                                    credentials: ProfileCredentials? = nil, restore: Bool = false) -> AgentProfile {
        AgentProfile(root: root, preferences: preferences ?? AgentMemoryPreferences(), credentials: credentials ?? ProfileCredentials(), restoreState: restore, autoReconnect: false,
            childHome: root.appendingPathComponent("codex-runtime/home"), defaultMCPWorkingDirectory: root,
            visibleLabel: "Authored isolated profile")
    }

    @MainActor func testClosedMemoryPreferencesDoNotShareValuesOrFallback() {
        let a = AgentMemoryPreferences(), b = AgentMemoryPreferences()
        a.set("full", forKey: "talkDuplex"); a.set(false, forKey: "talkQuickReplies"); a.set(7, forKey: "agent.historyDays")
        XCTAssertEqual(a.string(forKey: "talkDuplex"), "full")
        XCTAssertEqual(a.object(forKey: "talkQuickReplies") as? Bool, false)
        XCTAssertEqual(a.integer(forKey: "agent.historyDays"), 7)
        XCTAssertNil(b.object(forKey: "talkDuplex")); XCTAssertEqual(b.integer(forKey: "agent.historyDays"), 0)
        a.set(nil, forKey: "talkDuplex"); XCTAssertNil(a.string(forKey: "talkDuplex"))
    }

    @MainActor func testFreshReviewCreatesExclusivePrivateRootAndRefusesReopen() throws {
        let working = try fixture()
        let selected = try AgentProfile.freshReview(workingDirectory: working)
        XCTAssertEqual(selected.root.path, working.appendingPathComponent("agent-review-profile").path)
        let attrs = try FileManager.default.attributesOfItem(atPath: selected.root.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertFalse(selected.restoreState); XCTAssertFalse(selected.autoReconnect)
        XCTAssertTrue(selected.visibleLabel.contains("review profile"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: selected.root.path), [])
        XCTAssertThrowsError(try AgentProfile.freshReview(workingDirectory: working))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: selected.root.path), [])
    }

    @MainActor func testExplicitInvalidMarkerRefusesBeforeAnyProfileDirectoryCreation() throws {
        let working = try fixture(), app = working.appendingPathComponent("Plugin.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false)
        XCTAssertThrowsError(try AgentProfile.select(marker: "unknown", bundleURL: app, workingDirectory: working, hosted: true))
        XCTAssertThrowsError(try AgentProfile.select(marker: "fresh", bundleURL: app, workingDirectory: working, hosted: false))
        XCTAssertThrowsError(try AgentProfile.select(marker: 1, bundleURL: app, workingDirectory: working, hosted: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: working.appendingPathComponent("agent-review-profile").path))
        #if DEBUG
        let selected = try AgentProfile.select(marker: "fresh", bundleURL: app, workingDirectory: working, hosted: true)
        XCTAssertFalse(selected.autoReconnect)
        #endif
    }

    @MainActor func testActualPluginRestoresOnlyExplicitAuthoredProfile() async throws {
        let root = try fixture(), a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        let preferences = AgentMemoryPreferences(), credentials = ProfileCredentials()
        preferences.set(7, forKey: "agent.historyDays"); preferences.set("full", forKey: "talkDuplex")
        preferences.set(false, forKey: "talkQuickReplies"); preferences.set(true, forKey: AgentToolbox.localFlowsKey)
        let selected = profile(a, preferences: preferences, credentials: credentials, restore: true)
        var conversation = Conversation(); _ = conversation.begin("A fixture question", context: false); conversation.title = "Authored A"
        try ConversationFiles(file: selected.conversationFile).save(.init(selected: conversation.id, conversations: [conversation]))
        var tools = AgentIntegrationSettings(); tools.web = false; try tools.save(selected.toolsFile)
        var state = ContinualArchive(); state.paused = true; state.quiet = true
        try ContinualFiles(file: selected.continualFile).save(state)
        // Opaque synthetic existence sentinel, never a credential or actual runtime launch.
        try FileManager.default.createDirectory(at: selected.runtimeDirectory, withIntermediateDirectories: true)
        try Data("authored-not-auth".utf8).write(to: selected.runtimeDirectory.appendingPathComponent("auth.json"))
        let runtimeA = ProfileRuntime(directory: selected.runtimeDirectory)
        let pluginA = AgentPlugin(profile: selected, runtime: runtimeA)
        let selectedB = profile(b), runtimeB = ProfileRuntime(directory: selectedB.runtimeDirectory)
        let pluginB = AgentPlugin(profile: selectedB, runtime: runtimeB)
        defer { pluginA.model.shutdown(); pluginB.model.shutdown(); pluginA.continual.shutdown(); pluginB.continual.shutdown() }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(runtimeA.starts, 0); XCTAssertEqual(runtimeB.starts, 0); XCTAssertEqual(credentials.reads, [])
        XCTAssertEqual(pluginA.model.conversation.title, "Authored A")
        XCTAssertEqual(pluginA.model.messages.last?.phase, "interrupted")
        XCTAssertFalse(pluginA.tools.settings.web); XCTAssertTrue(pluginA.tools.localFlowsEnabled)
        XCTAssertTrue(pluginA.continual.archive.quiet); XCTAssertTrue(pluginA.continual.archive.paused)
        XCTAssertEqual(pluginA.talk.mode, "full"); XCTAssertFalse(pluginA.talk.quickReplies)
        XCTAssertEqual(pluginB.model.conversation.title, "New conversation")
        XCTAssertTrue(pluginB.continual.archive.sources.isEmpty); XCTAssertFalse(pluginB.tools.localFlowsEnabled)
        XCTAssertEqual(pluginB.talk.mode, "half"); XCTAssertTrue(pluginB.talk.quickReplies)
        XCTAssertEqual(pluginA.chatView.state["profileLabel"], .string("Authored isolated profile"))
    }

    @MainActor func testActualSettingsHandlersAndShutdownWriteOnlySelectedProfile() throws {
        let root = try fixture(), preferences = AgentMemoryPreferences()
        let selected = profile(root.appendingPathComponent("a"), preferences: preferences)
        let runtime = ProfileRuntime(directory: selected.runtimeDirectory)
        let plugin = AgentPlugin(profile: selected, runtime: runtime)
        defer { plugin.model.shutdown(); plugin.continual.shutdown() }
        try plugin.talk.chooseMode("full"); try plugin.talk.chooseReplyPace("default")
        let view = plugin.chatView
        try plugin.handle(.init(panelID: "conversation", revision: view.revision, name: "speech_provider", values: ["key": .string("")]))
        plugin.model.setRetention(7); plugin.model.newConversation()
        plugin.tools.update(web: false); plugin.tools.updateLocalFlows(true); plugin.continual.quiet(true)
        plugin.model.shutdown(); plugin.continual.shutdown()
        XCTAssertEqual(preferences.string(forKey: "talkDuplex"), "full")
        XCTAssertEqual(preferences.object(forKey: "talkQuickReplies") as? Bool, false)
        XCTAssertEqual(preferences.string(forKey: "speechProvider"), "")
        XCTAssertEqual(preferences.integer(forKey: "agent.historyDays"), 7)
        XCTAssertEqual(preferences.object(forKey: AgentToolbox.localFlowsKey) as? Bool, true)
        XCTAssertNotNil(try ConversationFiles(file: selected.conversationFile).load())
        XCTAssertFalse(try AgentIntegrationSettings.load(selected.toolsFile).web)
        XCTAssertTrue(try ContinualFiles(file: selected.continualFile).load().quiet)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("b").path))
        XCTAssertEqual(runtime.starts, 0)
    }

    @MainActor func testToolboxUsesInjectedCredentialAdapterForRealSaveAndRemove() throws {
        let root = try fixture(), credentials = ProfileCredentials(), selected = profile(root, credentials: credentials)
        let tools = AgentToolbox(profile: selected)
        var configuration = MCPConnection(); configuration.name = "Authored server"; configuration.endpoint = "https://example.invalid/mcp"
        try tools.save(configuration, secret: "authored-placeholder")
        let account = "mcp." + configuration.id.uuidString
        XCTAssertEqual(credentials.saved[account], "authored-placeholder"); XCTAssertEqual(credentials.reads, [])
        XCTAssertEqual(try AgentIntegrationSettings.load(selected.toolsFile).servers.map(\.id), [configuration.id])
        tools.remove(configuration.id)
        XCTAssertEqual(credentials.removed, [account]); XCTAssertNil(credentials.saved[account])
        XCTAssertEqual(try AgentIntegrationSettings.load(selected.toolsFile).servers.count, 0)
    }

    @MainActor func testExplicitConnectUsesFakeRuntimeWithoutRestoringAnyOtherProfile() async throws {
        let selected = profile(try fixture())
        let runtime = ProfileRuntime(directory: selected.runtimeDirectory)
        let model = AgentModel(runtime: runtime, profile: selected)
        defer { model.shutdown() }
        XCTAssertEqual(runtime.starts, 0)
        model.connect(allowSignIn: false)
        for _ in 0..<1000 { if model.email != nil { break }; await Task.yield() }
        XCTAssertEqual(model.email, "authored.invalid"); XCTAssertEqual(runtime.starts, 1)
        XCTAssertEqual(model.retentionDays, 0)
    }

    @MainActor func testManagementIdleReflectsActualConnectingTurnAndProposalState() async throws {
        let selected = profile(try fixture())
        let runtime = ProfileRuntime(directory: selected.runtimeDirectory)
        let plugin = AgentPlugin(profile: selected, runtime: runtime)
        defer { plugin.model.shutdown(); plugin.continual.shutdown() }
        XCTAssertEqual(plugin.chatView.state["managementIdle"], .boolean(true))
        plugin.model.connect(allowSignIn: false)
        XCTAssertFalse(plugin.managementIdle)
        for _ in 0..<1000 { if plugin.model.email != nil && !plugin.model.modelsLoading { break }; await Task.yield() }
        XCTAssertTrue(plugin.managementIdle)
        plugin.model.proposal = AgentAnswer(reply: "Authored proposal", action: "authored.action")
        XCTAssertEqual(plugin.chatView.state["managementIdle"], .boolean(false))
        plugin.model.proposal = nil
        XCTAssertTrue(plugin.managementIdle)
    }

    @MainActor func testOptionalChildHomeAndMCPDefaultsRemainExplicitAndNilByDefault() throws {
        let root = try fixture(), home = root.appendingPathComponent("home")
        let ordinary = CodexClient(directory: root), isolated = CodexClient(directory: root, childHome: home)
        XCTAssertNil(ordinary.childHome); XCTAssertEqual(isolated.childHome, home)
        let configuration = MCPConnection()
        let old = AgentMCPSession(configuration), selected = AgentMCPSession(configuration, childHome: home, defaultWorkingDirectory: root)
        XCTAssertNil(old.childHome); XCTAssertNil(old.defaultWorkingDirectory)
        XCTAssertEqual(selected.childHome, home); XCTAssertEqual(selected.defaultWorkingDirectory, root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.path))
    }
}
