import AppKit
import SwiftUI
import NookPluginSDK
import ApplicationServices
import ModuleCore

struct AgentToolsView: View {
    @ObservedObject var tools: AgentToolbox
    @State private var editing: MCPConnection?
    var body: some View {
        PluginSettingsPage("Nero’s tools", subtitle: "Choose what Nero can see and do. Review requests before they run.", symbol: "wrench.and.screwdriver", width: 700, height: 680, done: { tools.visible = false }) {
                    if let error = tools.storageError { Text(error).foregroundStyle(.orange) }
                    if let review = tools.reviews.pending.first {
                        PluginSettingsCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(review.title).font(.headline)
                                if tools.reviews.pending.count > 1 { Text("\(tools.reviews.pending.count) requests waiting · review one at a time").font(.caption) }
                                // This is the complete operation, not the bounded chat
                                // preview. Only this view may approve a long request.
                                ScrollView { Text(review.detail).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(minHeight: 100, maxHeight: 250)
                                Text(review.consequence).font(.caption)
                                HStack {
                                    Button("Allow once") { tools.reviews.resolve(review.id, allow: true) }
                                    Button("Decline") { tools.reviews.resolve(review.id, allow: false) }
                                    Button("Stop") { tools.invalidated?(); tools.cancelTurn() }
                                }
                            }.padding(6)
                        }
                    }
                    PluginSettingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Search and read the web", isOn: Binding(get: { tools.settings.web }, set: { tools.update(web: $0) }))
                            Text("Live web tools through your connected Codex account. Searches and source links appear in the conversation. No separate API billing.").font(.caption).pluginSecondaryText()
                            Toggle("Allow on-demand Mac tools", isOn: Binding(get: { tools.settings.mac }, set: { tools.update(mac: $0) }))
                            Text("Lists apps and reads requested windows. Screenshots and all control operations require your review. Observed app text or images may be sent to your agent; there is no background screen recording.").font(.caption).pluginSecondaryText()
                            HStack {
                                Text(AXIsProcessTrusted() ? "Accessibility allowed" : "Accessibility required").font(.caption)
                                Button("Accessibility settings") { openPrivacy("Privacy_Accessibility") }
                                Button("Screen recording settings") { openPrivacy("Privacy_ScreenCapture") }
                            }
                        }.padding(8)
                    }
                    HStack { Text("MCP connections").font(.headline); Spacer(); Button("Add connection…") { editing = .init() } }
                    Text("Connect services separately. Nero never imports this Mac's Codex or browser credentials. A local MCP server runs as your macOS user; connect only software you trust.").font(.caption).pluginSecondaryText()
                    if tools.settings.servers.isEmpty {
                        Text("No MCP servers added yet. Use a remote MCP endpoint or an installed local server.").pluginSecondaryText().padding(.vertical, 12)
                        Button("Add official OpenAI documentation") {
                            var connection = MCPConnection(); connection.name = "OpenAI documentation"; connection.endpoint = "https://developers.openai.com/mcp"; editing = connection
                        }
                    }
                    ForEach(tools.settings.servers) { server in
                        PluginSettingsCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(server.name).font(.headline); Spacer(); Button("Edit…") { editing = server } }
                                Text(server.transport == "stdio" ? server.command : server.endpoint).font(.caption).lineLimit(2).textSelection(.enabled)
                                Text(tools.states[server.id] ?? "Disconnected").font(.caption).pluginSecondaryText()
                                HStack {
                                    Button(tools.connecting.contains(server.id) ? "Connecting…" : "Connect") { tools.connect(server.id) }.disabled(tools.connecting.contains(server.id))
                                    Button("Disconnect") { tools.disconnect(server.id) }
                                    Button("Remove", role: .destructive) { tools.remove(server.id) }
                                }
                            }.padding(6)
                        }
                    }
                    PluginAdvancedSection(detail: "Connection capabilities and privacy limits.") {
                        Text("Web search, Mac Accessibility, reviewed window screenshots and configured MCP tools/resources/prompts work through Nero's own connections. ChatGPT's private hosted tools, this Codex chat's connectors, image generation and cloud computers are not automatically inherited. Add their independently supported MCP services where available. Your existing Nook module permissions remain separate.").font(.caption).pluginSecondaryText()
                    }
                    Text("Changes apply to the next turn and stop pending tool work. Stop requests cancellation; it cannot reverse remote changes that already completed. MCP sign-ins use an independent browser session; OAuth tokens currently stay in memory until disconnect or quit.").font(.caption).pluginSecondaryText()
        }
        .sheet(item: $editing) { configuration in MCPConnectionEditor(tools: tools, original: configuration) }
    }
    private func openPrivacy(_ value: String) { if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?"+value) { NSWorkspace.shared.open(url) } }
}

struct MCPConnectionEditor: View {
    @ObservedObject var tools: AgentToolbox
    let original: MCPConnection
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: MCPConnection
    @State private var arguments = ""
    @State private var secret = ""
    @State private var error = ""
    init(tools: AgentToolbox, original: MCPConnection) { self.tools = tools; self.original = original; _configuration = State(initialValue: original); _arguments = State(initialValue: original.arguments.joined(separator: "\n")) }
    var body: some View {
        PluginSettingsPage("MCP connection", subtitle: "Connect one trusted service to Nero Agent.", symbol: "point.3.connected.trianglepath.dotted", width: 650, height: configuration.transport == "stdio" ? 650 : 500) {
            PluginSettingsSection("Connection") {
                TextField("Name", text: $configuration.name)
                Picker("Transport", selection: $configuration.transport) { Text("Remote HTTP").tag("http"); Text("Local stdio").tag("stdio") }
                if configuration.transport == "http" { TextField("MCP endpoint", text: $configuration.endpoint) }
                else {
                    HStack { TextField("Executable", text: $configuration.command); Button("Choose…") { chooseExecutable() } }
                    VStack(alignment: .leading) { Text("Arguments · one per line").font(.caption); TextEditor(text: $arguments).font(.system(.caption,design: .monospaced)).frame(height: 82) }
                    TextField("Working folder (optional)", text: $configuration.workingDirectory)
                }
                Picker("Sign-in", selection: $configuration.authentication) {
                    Text("None").tag("none"); Text(configuration.transport == "http" ? "Bearer token" : "MCP_API_KEY environment").tag("bearer")
                    if configuration.transport == "http" { Text("OAuth browser sign-in").tag("oauth") }
                }
                if configuration.authentication == "bearer" { SecureField("Secret · leave blank to keep saved value", text: $secret) }
                if configuration.authentication == "oauth" { TextField("OAuth client ID (blank for dynamic registration)", text: $configuration.clientID) }
                Toggle("Trust this server's declared read-only tools", isOn: $configuration.trustedReads)
            }
            Text("All other tool calls require review. Trust is a choice about this server, not a guarantee about its annotations. Secrets are saved in Nero Agent's own Keychain namespace. They are never placed in a model prompt or exported settings.").font(.caption).pluginSecondaryText()
            if configuration.transport == "stdio" { Text("Connecting starts this installed program with your user permissions. No shell expansion or automatic package install is performed. Put no secrets in arguments.").font(.caption).foregroundStyle(.orange) }
            if !error.isEmpty { Text(error).foregroundStyle(.orange).font(.caption) }
        } footer: {
            HStack { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Save connection") {
                do { configuration.arguments = arguments.split(separator: "\n", omittingEmptySubsequences: false).map(String.init); if arguments.isEmpty { configuration.arguments = [] }; if configuration.transport == "stdio", configuration.authentication == "oauth" { configuration.authentication = "none" }; try tools.save(configuration, secret: secret); secret = ""; dismiss() } catch { self.error = error.localizedDescription }
            }.keyboardShortcut(.defaultAction) }
        }
    }
    private func chooseExecutable() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { configuration.command = url.path }
    }
}
