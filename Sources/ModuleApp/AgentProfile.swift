import Foundation
import Darwin
import NookPluginSDK
import ModuleCore

@MainActor protocol AgentPreferences: AnyObject {
    func object(forKey key: String) -> Any?
    func string(forKey key: String) -> String?
    func integer(forKey key: String) -> Int
    func set(_ value: Any?, forKey key: String)
}

@MainActor final class AgentUserDefaultsPreferences: AgentPreferences {
    private let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    func object(forKey key: String) -> Any? { defaults.object(forKey: key) }
    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    func integer(forKey key: String) -> Int { defaults.integer(forKey: key) }
    func set(_ value: Any?, forKey key: String) { defaults.set(value, forKey: key) }
}

/// Closed session preferences. No standard/global/argument defaults fallback.
@MainActor final class AgentMemoryPreferences: AgentPreferences {
    private enum Value { case string(String), integer(Int), boolean(Bool) }
    private var values: [String: Value] = [:]
    func object(forKey key: String) -> Any? {
        switch values[key] {
        case .string(let value): return value
        case .integer(let value): return value
        case .boolean(let value): return value
        case nil: return nil
        }
    }
    func string(forKey key: String) -> String? {
        if case .string(let value) = values[key] { return value }; return nil
    }
    func integer(forKey key: String) -> Int {
        if case .integer(let value) = values[key] { return value }; return 0
    }
    func set(_ value: Any?, forKey key: String) {
        guard let value else { values[key] = nil; return }
        if type(of: value) == Bool.self, let value = value as? Bool { values[key] = .boolean(value) }
        else if type(of: value) == Int.self, let value = value as? Int { values[key] = .integer(value) }
        else if let value = value as? String { values[key] = .string(value) }
        else { preconditionFailure("Unsupported Agent session preference type") }
    }
}

@MainActor protocol AgentCredentialStore: AnyObject {
    func save(_ value: String, account: String) throws
    func read(account: String) throws -> String
    func remove(account: String) throws
}

@MainActor final class AgentKeychainCredentials: AgentCredentialStore {
    private let credentials: PluginCredentials
    init(namespace: String = "cafe.nero.plugin.agent") { credentials = PluginCredentials(pluginID: namespace) }
    func save(_ value: String, account: String) throws { try credentials.save(value, account: account) }
    func read(account: String) throws -> String { try credentials.read(account: account) }
    func remove(account: String) throws { try credentials.remove(account: account) }
}

@MainActor struct AgentProfile {
    let root: URL
    let preferences: any AgentPreferences
    let credentials: any AgentCredentialStore
    let restoreState: Bool
    let autoReconnect: Bool
    let childHome: URL?
    let defaultMCPWorkingDirectory: URL?
    let visibleLabel: String
    var runtimeDirectory: URL { root.appendingPathComponent("codex-runtime", isDirectory: true) }
    var conversationFile: URL { root.appendingPathComponent("conversations-v1.json") }
    var toolsFile: URL { root.appendingPathComponent("tools-v1.json") }
    var continualFile: URL { root.appendingPathComponent("continual/state-v1.json") }
    static var ordinary: AgentProfile {
        AgentProfile(root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NeroNook-Plugins/cafe.nero.plugin.agent"),
            preferences: AgentUserDefaultsPreferences(), credentials: AgentKeychainCredentials(), restoreState: true,
            autoReconnect: true, childHome: nil, defaultMCPWorkingDirectory: nil, visibleLabel: "")
    }
    static func select(marker: Any?, bundleURL: URL, workingDirectory: URL, hosted: Bool) throws -> AgentProfile {
        guard let marker else { return .ordinary }
        #if DEBUG
        guard let marker = marker as? String, marker == "fresh", hosted,
              bundleURL.lastPathComponent == "Plugin.app",
              Data(bundleURL.deletingLastPathComponent().path.utf8) == Data(workingDirectory.path.utf8) else {
            throw AgentError.message("Agent review profile selection is invalid. Owner profile was not opened.")
        }
        return try freshReview(workingDirectory: workingDirectory)
        #else
        throw AgentError.message("Agent review profiles require a DEBUG build. Owner profile was not opened.")
        #endif
    }
    static func freshReview(workingDirectory: URL) throws -> AgentProfile {
        // Exact existing installed working folder; never follow a symlink ancestor.
        guard workingDirectory.isFileURL, workingDirectory.path.hasPrefix("/"),
              !workingDirectory.pathComponents.contains(".."), !workingDirectory.pathComponents.contains(".") else {
            throw AgentError.message("Agent review profile needs an existing local working folder.")
        }
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in workingDirectory.pathComponents.dropFirst() {
            current.appendPathComponent(component, isDirectory: true)
            var info = stat()
            guard lstat(current.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
                throw AgentError.message("Agent review working folder must not contain symlinks.")
            }
        }
        let root = workingDirectory.appendingPathComponent("agent-review-profile", isDirectory: true)
        guard mkdir(root.path, 0o700) == 0 else {
            throw AgentError.message("A fresh Agent review profile could not be created. Existing data was kept; owner profile was not opened.")
        }
        var info = stat()
        guard lstat(root.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o777 == 0o700, info.st_uid == getuid() else {
            throw AgentError.message("Agent review profile permissions could not be verified. Owner profile was not opened.")
        }
        return AgentProfile(root: root, preferences: AgentMemoryPreferences(),
            credentials: AgentKeychainCredentials(namespace: "cafe.nero.plugin.agent.review." + UUID().uuidString.lowercased()),
            restoreState: false, autoReconnect: false,
            childHome: root.appendingPathComponent("codex-runtime/home", isDirectory: true),
            defaultMCPWorkingDirectory: root, visibleLabel: "Isolated review profile · fresh session · owner data not loaded")
    }
}
