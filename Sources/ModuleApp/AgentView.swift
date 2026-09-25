import SwiftUI
import NookPluginSDK

struct AgentView: View {
    @ObservedObject var plugin: AgentPlugin
    @ObservedObject var model: AgentModel
    @ObservedObject var continual: ContinualModel
    @State private var selectedPanel = "conversation"
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Agent view", selection: $selectedPanel) { Text("Conversation").tag("conversation"); Text("Activity").tag("awareness") }.pickerStyle(.segmented).frame(width: 240)
                Spacer(); Text(model.busy ? "Working" : continual.phase).font(.caption).foregroundStyle(.mint)
                Button("Nero can see…") { continual.sourcesVisible = true }
            }.padding(12)
            PluginWebSurface(root: Bundle.main.resourceURL!.appendingPathComponent("Views"), panelID: selectedPanel, definition: selectedPanel == "conversation" ? plugin.chatView : plugin.awarenessView) { event in
                try plugin.handle(event)
            }.id(selectedPanel)
        }.frame(minWidth: 640, minHeight: 400).preferredColorScheme(.dark).tint(.mint)
        .sheet(isPresented: $continual.sourcesVisible) { ContextSourcesView(model: continual) }
        .sheet(isPresented: $model.settingsVisible) {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("Nero Agent Settings").font(.title2.bold()); Spacer(); Button("Done") { model.settingsVisible = false } }
                Text(model.email ?? "Use your existing ChatGPT / Codex account.")
                Text("Your messages use Nero Agent’s separate ChatGPT sign-in. Enable Nook context on a message to let it read tools you have permitted in NeroNook.").font(.callout).foregroundStyle(.secondary)
                Text(model.status).font(.callout)
                HStack {
                    Button(model.email == nil ? "Sign in with ChatGPT" : "Reconnect") { model.connect() }.disabled(model.connecting || model.busy)
                    if model.connecting { Button("Cancel sign-in") { model.cancelLogin() } }
                    if model.email != nil { Button("Sign out") { model.signOut() }.disabled(model.busy || model.connecting) }
                }
                Divider()
                Picker("Keep conversations on this Mac", selection: Binding(get: { model.retentionDays }, set: { model.setRetention($0) })) {
                    Text("Until quit").tag(0); Text("7 days").tag(7); Text("30 days").tag(30)
                }.disabled(model.busy || model.historyError != nil)
                Text("Up to 20 chats, 40 messages each. Only conversation text and tool activity labels are saved; raw tool results are not. Until quit stops saving future changes and leaves any previously saved file untouched.").font(.caption).foregroundStyle(.secondary)
                if let error = model.historyError { Text(error).foregroundStyle(.orange) }
                DisclosureGroup("Codex runtime") {
                    Text(model.runtimePath).font(.caption).textSelection(.enabled)
                    Button("Choose runtime…") { model.chooseRuntime() }.disabled(model.busy || model.connecting)
                }
                Text("Nook reads use explicitly permitted SDK tools. Proposed changes still need review in NeroNook. Shell, browser and unregistered tools remain unavailable.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width: 550)
        }
    }
}
