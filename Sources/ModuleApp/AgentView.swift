import SwiftUI
import NookPluginSDK

struct AgentView: View {
    @ObservedObject var plugin: AgentPlugin
    @ObservedObject var model: AgentModel
    @ObservedObject var continual: ContinualModel
    private var selectedPanel: String { plugin.focusedPanel }
    var body: some View {
        VStack(spacing: 0) {
            if selectedPanel == "awareness" {
                HStack {
                    Button("Back to conversation") { plugin.focusedPanel = "conversation" }
                    Spacer()
                    Button("Context sources…") { continual.sourcesVisible = true }
                }.padding(12)
            }
            PluginWebSurface(root: Bundle.main.resourceURL!.appendingPathComponent("Views"), panelID: selectedPanel, definition: selectedPanel == "conversation" ? plugin.chatView : plugin.awarenessView) { event in
                try plugin.handle(event)
            }.id(selectedPanel)
        }.frame(minWidth: 640, minHeight: 400)
        .sheet(isPresented: Binding(get: { plugin.tools.visible }, set: { plugin.tools.visible = $0 })) { AgentToolsView(tools: plugin.tools) }
        .sheet(isPresented: $continual.sourcesVisible) { ContextSourcesView(model: continual) }
        .sheet(isPresented: $model.settingsVisible) {
            PluginSettingsPage("Nero Agent", subtitle: "Your account, conversation history and connected tools.", symbol: "sparkle", width: 640, height: 660, done: { model.settingsVisible = false }) {
                PluginSettingsSection("Account", detail: "Use your existing ChatGPT / Codex sign-in. Speech recognition and playback are managed by Nero Voice.") {
                    Text(model.email ?? "No account connected").font(.headline)
                    Text(model.status).font(.callout).pluginSecondaryText()
                    HStack {
                        Button(model.email == nil ? "Sign in with ChatGPT" : "Reconnect") { plugin.talk.stop(); model.connect() }.disabled(model.connecting || model.busy)
                        if model.connecting { Button("Cancel sign-in") { model.cancelLogin() } }
                        if model.email != nil { Button("Sign out") { plugin.talk.stop(); model.signOut() }.disabled(model.busy || model.connecting) }
                    }
                }
                PluginSettingsSection("Conversation history", detail: "Choose how long to keep conversations on this Mac.") {
                    Picker("Keep chats", selection: Binding(get: { model.retentionDays }, set: { model.setRetention($0) })) {
                        Text("Until quit").tag(0); Text("7 days").tag(7); Text("30 days").tag(30)
                    }.disabled(model.busy || model.historyError != nil)
                    Text("Up to 20 chats, 40 messages each. Saves conversation text and tool activity labels, not raw tool results. Until quit stops saving future changes; previously saved files are left untouched.").font(.caption).pluginSecondaryText()
                    if let error = model.historyError { Text(error).foregroundStyle(.orange) }
                }
                PluginSettingsSection("Tools & context", detail: "Choose what Nero can read or control. Proposed changes still need your review.") {
                    Button("Manage web, Mac & MCP tools…") { model.settingsVisible = false; DispatchQueue.main.asyncAfter(deadline: .now()+0.2) { plugin.tools.visible = true } }
                    Text("Nook context uses only permitted SDK tools. Web, Mac and MCP connections are separate; private ChatGPT tools and this Mac’s other sign-ins are not automatically shared.").font(.caption).pluginSecondaryText()
                }
                PluginAdvancedSection(detail: "Use the default runtime unless you are troubleshooting sign-in or testing a different Codex installation. Changing it ends Talk.") {
                    Text("Codex runtime").font(.headline)
                    Text(model.runtimePath).font(.caption).textSelection(.enabled)
                    Button("Choose runtime…") { plugin.talk.stop(); model.chooseRuntime() }.disabled(model.busy || model.connecting)
                }
            }
        }
    }
}
