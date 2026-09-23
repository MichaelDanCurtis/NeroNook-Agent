import AppKit
import SwiftUI
import Combine
import ModuleCore
import NookPluginSDK

@MainActor final class AgentPlugin: ObservableObject {
    let model = AgentModel()
    let id = "cafe.nero.plugin.agent"
    let hosted = CommandLine.arguments.contains("--neronook-plugin")
    private var session: UUID?
    private var sequence: UInt64 = 0
    private var input = PluginLines()
    private var catalog = PluginCatalogAccumulator()
    private var subscriptions = Set<PluginActionAddress>()
    private var timer: Timer?
    private var forms = false
    private var submitted: Set<UUID> = []
    private var incoming: [UUID] = []
    private var running: Set<UUID> = []
    private var activity: NSObjectProtocol?
    static var askAction: PluginRegisteredAction {
        .init("ask", title: "Ask ChatGPT", input: .init([.init("prompt", .string), .init("context", .string, required: false)]), output: .init([.init("reply", .string)]), cancellable: true, timeoutSeconds: 180)
    }
    static var decisionAction: PluginRegisteredAction {
        .init("decide", title: "Evaluate a condition with ChatGPT", input: askAction.input, output: .init([.init("reply", .string), .init("decision", .boolean)]), cancellable: true, timeoutSeconds: 180)
    }
    init() {
        model.changed = { [weak self] in self?.publish() }
        model.complete = { [weak self] request, update in guard let self, self.running.remove(request) != nil else { return }; self.bus(.init(.update, requestID: request, update: update)) }
        if hosted {
            NSApplication.shared.setActivationPolicy(.accessory)
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Serve Nero Agent")
            FileHandle.standardInput.readabilityHandler = { [weak self] file in
                let data = file.availableData
                Task { @MainActor in
                    guard let self else { return }; guard !data.isEmpty else { self.model.shutdown(); exit(0) }
                    do { for m in try self.input.append(data) { self.receive(m) } } catch { self.model.shutdown(); exit(1) }
                }
            }
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.publish() } }; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func configure() {
        model.settingsVisible = true; NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
    }
    private func receive(_ message: PluginMessage) {
        guard message.pluginID == id else { exit(1) }
        if session == nil {
            guard message.type == "hello" else { exit(1) }; session = message.session
            forms = message.features?.contains("forms-v1") == true
            emit("ready", features: ["dashboard-v1", "panels-v1", "actions-v1", "forms-v1"])
            if message.features?.contains("actions-v1") == true { bus(.init(.register, registration: .init(actions: [Self.askAction, Self.decisionAction]))); bus(.init(.discover)) }
            publish(); return
        }
        guard message.session == session else { exit(1) }
        if message.type == "action", let action = message.action {
            if action == "configure" { configure() }
            if action == "stop", model.busy { model.cancel() }
            if action == "review_proposal", let answer = model.proposal {
                do {
                    guard let (entry, values) = try answer.proposal(catalog: model.catalog) else { return }
                    let request = UUID(); submitted.insert(request); model.proposal = nil
                    bus(.init(.invoke, requestID: request, address: entry.address, values: values)); model.status = "Waiting for action review"
                } catch { model.status = error.localizedDescription; model.proposal = nil }
            }
        }
        guard let message = message.bus else { return }
        switch message.operation {
        case .catalog:
            if (try? catalog.receive(message)) == true {
                model.catalog = catalog.entries.filter { $0.address.plugin != id }
                let permitted = Set(model.catalog.filter { $0.channel?.kind == .state }.map(\.address).sorted { $0.key < $1.key }.prefix(16))
                for address in subscriptions.subtracting(permitted) { model.states[address.key] = nil; bus(.init(.unsubscribe, address: address)) }
                for address in permitted.subtracting(subscriptions) { bus(.init(.subscribe, address: address)) }
                subscriptions = permitted; publish()
            }
        case .event:
            if let address = message.address, subscriptions.contains(address), let lifetime = message.lifetime, lifetime.isFinite, lifetime > 0 {
                model.states[address.key] = (message.values ?? [:], Date().addingTimeInterval(min(300, lifetime))); publish()
            }
        case .execute:
            guard !incoming.contains(message.requestID) else { return }
            incoming.append(message.requestID); if incoming.count > 256 { incoming.removeFirst() }
            guard message.address?.plugin == id, ["ask", "decide"].contains(message.address?.name ?? ""), let values = message.values,
                  (try? Self.askAction.input.validate(values)) != nil, case .string(let prompt) = values["prompt"] else {
                bus(.init(.update, requestID: message.requestID, update: .init(.failed, message: "Invalid prompt"))); return
            }
            let context: String = { if case .string(let value) = values["context"], !value.isEmpty { return value }; return "None" }()
            running.insert(message.requestID)
            model.ask(prompt, context: context, decision: message.address?.name == "decide", request: message.requestID)
        case .cancel: model.cancel(request: message.requestID)
        case .update:
            if submitted.contains(message.requestID), let update = message.update {
                model.status = update.message.isEmpty ? update.phase.rawValue.capitalized : update.message
                if update.phase.terminal { submitted.remove(message.requestID) }
            }
        case .failure:
            if submitted.remove(message.requestID) != nil { model.status = message.error ?? "Action request failed" }
        default: break
        }
    }
    private func publish() {
        guard session != nil else { return }
        model.states = model.states.filter { $0.value.expires > Date() }
        let contextChoices = ["None"] + model.states.keys.sorted().prefix(16)
        let form = PluginForm("message", title: "Ask Nero", revision: model.busy ? "busy" : "ready", action: Self.askAction, inputs: [
            .init("prompt", label: "Message to ChatGPT", style: .text, value: .string("")),
            .init("context", label: "Attach module state", style: .choice, value: .string("None"), choices: contextChoices)
        ], enabled: model.email != nil && !model.busy)
        var sections: [PluginSection] = []
        if !model.prompt.isEmpty { sections.append(.init("You", String(model.prompt.prefix(1200)))) }
        if !model.reply.isEmpty {
            let text = Array(model.reply)
            for start in stride(from: 0, to: min(text.count, 7200), by: 1200) { sections.append(.init(start == 0 ? "Nero" : "Continued", String(text[start..<min(start + 1200, text.count)]))) }
        }
        if let proposal = model.proposal { sections.append(.init("Proposed action · not executed", String(((proposal.action ?? "") + "\n" + proposal.arguments).prefix(1200)))) }
        if sections.isEmpty { sections = [.init("Your account, your choice", "Use the gear button to connect your existing ChatGPT account. Each message sends only your text and the module state you explicitly select. Voice is coming later.")] }
        let contextSections = model.states.keys.sorted().prefix(12).map { key in PluginSection(String(key.prefix(80)), String(model.states[key]!.values.keys.sorted().map { "\($0): \(model.states[key]!.values[$0]!.display)" }.joined(separator: "\n").prefix(1200))) }
        let snapshot = PluginSnapshot(title: "Nero Agent", status: model.status, activity: String(model.status.prefix(100)), actions: [
            .init("stop", "Stop", enabled: model.busy, symbol: "stop.fill"),
            .init("review_proposal", "Review proposed action", enabled: model.proposal != nil && !model.busy, symbol: "checkmark.shield")
        ], badge: model.email == nil ? "Not connected" : "ChatGPT", panels: [
            .init("conversation", "Conversation", sections: sections, forms: forms ? [form] : nil),
            .init("context", "Context preview", sections: contextSections.isEmpty ? [.init("No module context", "Allow Nero Agent to receive selected module updates in Nook Settings → Modules → Actions and connections. Receiving an update here does not send it to ChatGPT. Choose an attachment when asking.")] : contextSections)
        ])
        guard (try? snapshot.validate()) != nil else { return }; emit("snapshot", snapshot: snapshot)
    }
    private func bus(_ value: PluginBusMessage) { emit("bus", bus: value) }
    private func emit(_ type: String, features: [String]? = nil, snapshot: PluginSnapshot? = nil, bus: PluginBusMessage? = nil) {
        guard let session else { return }; if type != "ready" { sequence += 1 }
        do { try FileHandle.standardOutput.write(contentsOf: PluginMessage(type: type, pluginID: id, session: session, sequence: sequence, snapshot: snapshot, features: features, bus: bus).encoded()) }
        catch { model.shutdown(); exit(0) }
    }
}

struct AgentView: View {
    @ObservedObject var model: AgentModel
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label("Nero Agent", systemImage: "sparkles").font(.title2.bold()); Spacer(); Text(model.email == nil ? "Not connected" : "ChatGPT").font(.caption); Button { model.settingsVisible = true } label: { Image(systemName: "gearshape") } }
            ScrollView { VStack(alignment: .leading, spacing: 16) { if !model.prompt.isEmpty { Text(model.prompt).foregroundStyle(.secondary) }; Text(model.reply.isEmpty ? "An assistant for your Nook. Connect your ChatGPT account to begin." : model.reply).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack { TextField("Message to ChatGPT", text: $draft).textFieldStyle(.roundedBorder).onSubmit(send); Button("Send", action: send).disabled(model.email == nil || model.busy || draft.isEmpty); Button("Stop") { model.cancel() }.disabled(!model.busy) }
            Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.padding(20).frame(width: 720, height: 405).preferredColorScheme(.dark).tint(.mint)
            .sheet(isPresented: $model.settingsVisible) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Text("Nero Agent Settings").font(.title2.bold()); Spacer(); Button("Done") { model.settingsVisible = false } }
                    Text(model.email ?? "Use your existing ChatGPT / Codex account.")
                    Text("A separate sign-in keeps Nero Agent’s conversations and tools separate from the Codex desktop. No API key is required.").font(.callout).foregroundStyle(.secondary)
                    Text(model.status).font(.callout)
                    HStack {
                        Button(model.email == nil ? "Sign in with ChatGPT" : "Reconnect") { model.connect() }.disabled(model.connecting || model.busy)
                        if model.connecting { Button("Cancel sign-in") { model.cancelLogin() } }
                        if model.email != nil { Button("Sign out") { model.signOut() }.disabled(model.busy) }
                    }
                    DisclosureGroup("Codex runtime") {
                        Text(model.runtimePath).font(.caption).textSelection(.enabled)
                        Button("Choose runtime…") { model.chooseRuntime() }.disabled(model.busy || model.connecting)
                    }
                    Text("Uses the installed Codex runtime. The preview disables shell and browser tools and restricts the runtime to its own data and macOS support files. Module actions require a separate review in NeroNook.").font(.caption).foregroundStyle(.secondary)
                }.padding(24).frame(width: 520)
            }
    }
    private func send() { guard !draft.isEmpty else { return }; let text = draft; draft = ""; model.ask(text) }
}

@main struct NeroAgentApp: App {
    @StateObject private var plugin: AgentPlugin
    init() { let plugin = AgentPlugin(); _plugin = StateObject(wrappedValue: plugin) }
    var body: some Scene { WindowGroup { AgentView(model: plugin.model).onAppear { if plugin.hosted { NSApp.windows.first { $0.canBecomeKey }?.orderOut(nil) } } }.windowResizability(.contentSize) }
}
