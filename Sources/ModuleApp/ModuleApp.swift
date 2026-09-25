import AppKit
import SwiftUI
import Combine
import ModuleCore
import NookPluginSDK

@MainActor final class AgentPlugin: ObservableObject {
    let model = AgentModel()
    let continual = ContinualModel()
    let id = "cafe.nero.plugin.agent"
    let hosted = CommandLine.arguments.contains("--neronook-plugin")
    private var session: UUID?
    private var sequence: UInt64 = 0
    private var input = PluginLines()
    private var catalog = PluginCatalogAccumulator()
    private var subscriptions = Set<PluginActionAddress>()
    private var timer: Timer?
    private var forms = false
    private var customViews = false
    private var reads: [UUID: (entry: PluginCatalogEntry, chat: Bool, continuation: CheckedContinuation<[String: PluginValue], Error>)] = [:]
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
        model.changed = { [weak self] in self?.objectWillChange.send(); self?.publish() }
        continual.changed = { [weak self] in self?.objectWillChange.send(); self?.publish() }
        continual.catalog = { [weak self] in self?.model.catalog ?? [] }
        continual.read = { [weak self] entry, values in
            guard let self else { throw CancellationError() }; return try await self.invokeRead(entry, values: values, chat: false)
        }
        continual.invalidatePlanner = { [weak self] in self?.model.invalidateLocalContext() }
        model.catalogForPlanner = { [weak self] in self?.continual.plannerCatalog ?? [] }
        model.localContext = { [weak self] in guard let self else { throw CancellationError() }; return try self.continual.cloudContext() }
        model.readAction = { [weak self] entry, values in
            guard let self else { throw CancellationError() }; return try await self.invokeRead(entry, values: values, chat: true)
        }
        model.cancelReads = { [weak self] in
            guard let self else { return }; let pending = self.reads.filter { $0.value.chat }; for id in pending.keys { self.reads[id] = nil }
            for (id, item) in pending { self.bus(.init(.cancel, requestID: id)); item.continuation.resume(throwing: CancellationError()) }
        }
        model.complete = { [weak self] request, update in guard let self, self.running.remove(request) != nil else { return }; self.bus(.init(.update, requestID: request, update: update)) }
        if hosted {
            NSApplication.shared.setActivationPolicy(.accessory)
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Serve Nero Agent")
            FileHandle.standardInput.readabilityHandler = { [weak self] file in
                let data = file.availableData
                Task { @MainActor in
                    guard let self else { return }; guard !data.isEmpty else { self.continual.shutdown(); self.model.shutdown(); exit(0) }
                    do { for m in try self.input.append(data) { self.receive(m) } } catch { self.continual.shutdown(); self.model.shutdown(); exit(1) }
                }
            }
        }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.publish() } }; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func invokeRead(_ entry: PluginCatalogEntry, values: [String: PluginValue], chat: Bool) async throws -> [String: PluginValue] {
        guard session != nil, model.catalog.contains(entry), entry.action?.effect == .readOnly, reads.count < 16 else { throw AgentError.message("That read action is unavailable.") }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                reads[id] = (entry, chat, continuation)
                bus(.init(.invoke, requestID: id, address: entry.address, values: values))
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    guard let self, let pending = self.reads.removeValue(forKey: id) else { return }
                    self.bus(.init(.cancel, requestID: id)); pending.continuation.resume(throwing: AgentError.message("The Nook tool did not respond in time."))
                }
            }
        } onCancel: { Task { @MainActor [weak self] in
            guard let self, let pending = self.reads.removeValue(forKey: id) else { return }
            self.bus(.init(.cancel, requestID: id)); pending.continuation.resume(throwing: CancellationError())
        } }
    }
    func configure() {
        model.settingsVisible = true; openChat()
    }
    private func receive(_ message: PluginMessage) {
        guard message.pluginID == id else { exit(1) }
        if session == nil {
            guard message.type == "hello" else { exit(1) }; session = message.session
            customViews = message.features?.contains("custom-views-v1") == true
            forms = message.features?.contains("forms-v1") == true
            emit("ready", features: ["dashboard-v1", "panels-v1", "actions-v1", "forms-v1"] + (customViews ? ["custom-views-v1"] : []))
            if message.features?.contains("actions-v1") == true { bus(.init(.register, registration: .init(actions: [Self.askAction, Self.decisionAction]))); bus(.init(.discover)) }
            publish(); return
        }
        guard message.session == session else { exit(1) }
        if message.type == "action", let action = message.action {
            if action == "configure" { configure() }
            if action == "stop", model.busy { model.cancel() }
            if action == "review_proposal" { reviewProposal() }
            if action == "open_chat" { openChat() }
        }
        if message.type == "viewEvent", let event = message.viewEvent { do { try handle(event) } catch { model.status = error.localizedDescription }; return }
        guard let message = message.bus else { return }
        switch message.operation {
        case .catalog:
            if (try? catalog.receive(message)) == true {
                model.catalog = catalog.entries.filter { $0.address.plugin != id }
                for key in Array(reads.keys) where !model.catalog.contains(reads[key]!.entry) {
                    reads.removeValue(forKey: key)?.continuation.resume(throwing: AgentError.message("Tool access changed. The result was discarded."))
                }
                let permitted = Set(model.catalog.filter { $0.channel?.kind == .state }.map(\.address).sorted { $0.key < $1.key }.prefix(16))
                for address in subscriptions.subtracting(permitted) { model.states[address.key] = nil; bus(.init(.unsubscribe, address: address)) }
                for address in permitted.subtracting(subscriptions) { bus(.init(.subscribe, address: address)) }
                subscriptions = permitted; continual.catalogChanged(); publish()
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
            if let pending = reads[message.requestID], let update = message.update, update.phase.terminal {
                reads[message.requestID] = nil
                if update.phase == .succeeded, model.catalog.contains(pending.entry), (try? pending.entry.action?.output.validate(update.values)) != nil { pending.continuation.resume(returning: update.values) }
                else { pending.continuation.resume(throwing: AgentError.message(update.message.isEmpty ? "The Nook tool could not complete." : update.message)) }
            }
            if submitted.contains(message.requestID), let update = message.update {
                model.actionProgress(message.requestID, update)
                if update.phase.terminal { submitted.remove(message.requestID) }
            }
        case .failure:
            reads.removeValue(forKey: message.requestID)?.continuation.resume(throwing: AgentError.message(message.error ?? "The tool request failed."))
            if submitted.remove(message.requestID) != nil { model.actionProgress(message.requestID, .init(.failed, message: message.error ?? "Action request failed")) }
        default: break
        }
    }
    func openChat() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
            if let screen = window.screen ?? NSScreen.main {
                let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
                var frame = window.frame; frame.size.width = min(frame.width, visible.width); frame.size.height = min(frame.height, visible.height)
                frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
                frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
                window.setFrame(frame, display: true)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }
    func reviewProposal() {
        do {
            guard session != nil else { throw AgentError.message("Open this module through NeroNook to review an action.") }
            let (entry, values) = try model.proposalForReview()
            let request = UUID(); submitted.insert(request); model.proposal = nil
            bus(.init(.invoke, requestID: request, address: entry.address, values: values)); model.actionProgress(request, .init(.waitingReview, message: "Waiting for action review"))
        } catch { model.status = error.localizedDescription; model.proposal = nil }
    }
    var chatView: PluginCustomView {
        var shown: [ChatMessage] = []; var budget = 0
        for var message in model.messages.reversed() {
            message.text = String(message.text.prefix(9000))
            let size = (try? JSONEncoder().encode(message).count) ?? 0
            guard budget + size <= 18000 else { break }; budget += size; shown.append(message)
        }
        func json<T: Encodable>(_ value: T) -> String { String(data: (try? JSONEncoder().encode(value)) ?? Data(), encoding: .utf8) ?? "[]" }
        let history = model.conversations.reversed().map { ["id": $0.id.uuidString, "title": $0.title] }
        var view = PluginCustomView(entry: "chat/index.html", revision: "chat1", state: [
            "messages": .string(json(Array(shown.reversed()))), "history": .string(json(history)), "conversation": .string(model.currentID.uuidString),
            "busy": .boolean(model.busy), "connected": .boolean(model.email != nil), "status": .string(model.status),
            "title": .string(model.conversation.title), "retention": .number(Double(model.retentionDays)),
            "historyError": .string(model.historyError ?? ""), "omitted": .boolean(shown.count < model.messages.count),
            "proposal": .string(model.proposal.map { String((($0.action ?? "") + "\n" + $0.arguments).prefix(2000)) } ?? ""),
            "contextCount": .number(Double(model.catalog.count)), "presence": .string(continual.phase), "watchCount": .number(Double(continual.archive.watches.filter { !$0.dismissed && !$0.terminalSeen }.count))
        ], events: [
            .init("send", input: .init([.init("text", .string), .init("context", .boolean)])), .init("stop"), .init("new"), .init("retry"),
            .init("select", input: .init([.init("id", .string)])), .init("settings"), .init("review"), .init("open"), .init("copy", input: .init([.init("id", .string)]))
        ])
        while (try? view.validate()) == nil, !shown.isEmpty {
            shown.removeLast()
            view.state["messages"] = .string(json(Array(shown.reversed())))
            view.state["omitted"] = .boolean(true)
        }
        return view
    }
    func handle(_ event: PluginViewEvent) throws {
        if event.panelID == "awareness" { try handleAwareness(event); return }
        guard event.panelID == "conversation" else { throw AgentError.message("Unknown view.") }; try chatView.validate(event)
        switch event.name {
        case "send": if case .string(let text) = event.values["text"], case .boolean(let context) = event.values["context"], !model.busy { model.sendChat(text, useContext: context) }
        case "stop": model.cancel()
        case "new": model.newConversation()
        case "retry": model.retry()
        case "select": if case .string(let id) = event.values["id"], let uuid = UUID(uuidString: id) { model.selectConversation(uuid) }
        case "copy":
            if case .string(let id) = event.values["id"], let message = model.messages.first(where: { $0.id.uuidString == id }), !message.text.isEmpty {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string); model.status = "Copied message"
            }
        case "settings": configure()
        case "review": reviewProposal()
        case "open": openChat()
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
        if sections.isEmpty { sections = [.init("Your account, your choice", "Use the gear button to connect your existing ChatGPT account. Each message sends only your text and the module state you explicitly select. Open chat to start a conversation.")] }
        let contextSections = model.states.keys.sorted().prefix(12).map { key in PluginSection(String(key.prefix(80)), String(model.states[key]!.values.keys.sorted().map { "\($0): \(model.states[key]!.values[$0]!.display)" }.joined(separator: "\n").prefix(1200))) }
        let snapshot = PluginSnapshot(title: "Nero Agent", status: model.busy ? model.status : continual.phase + " · " + model.status, activity: String((model.busy ? model.status : continual.phase + " · " + continual.status).prefix(100)), actions: customViews ? [] : [
            .init("open_chat", "Open chat", symbol: "arrow.up.left.and.arrow.down.right"),
            .init("stop", "Stop", enabled: model.busy, symbol: "stop.fill"),
            .init("review_proposal", "Review proposed action", enabled: model.proposal != nil && !model.busy, symbol: "checkmark.shield")
        ], badge: model.email == nil ? "Not connected" : "ChatGPT", panels: [
            customViews ? .init("conversation", "Conversation", customView: chatView) : .init("conversation", "Conversation", sections: sections, forms: forms ? [form] : nil),
            customViews ? .init("awareness", "Activity", customView: awarenessView) : .init("awareness", "Activity", sections: [.init("Continual Agent", continual.phase + " · Open Agent to manage sources and watches.")]),
        ] + (customViews ? [] : [
            .init("context", "Context preview", sections: contextSections.isEmpty ? [.init("No module context", "Allow Nero Agent to receive selected module updates in Nook Settings → Modules → Actions and connections. Receiving an update here does not send it to ChatGPT. Choose an attachment when asking.")] : contextSections)
        ]))
        guard (try? snapshot.validate()) != nil else {
            emit("snapshot", snapshot: .init(title: "Nero Agent", status: "View unavailable · open Agent", actions: [.init("open_chat", "Open Agent"), .init("stop", "Stop reply", enabled: model.busy)])); return
        }; emit("snapshot", snapshot: snapshot)
    }
    private func bus(_ value: PluginBusMessage) { emit("bus", bus: value) }
    private func emit(_ type: String, features: [String]? = nil, snapshot: PluginSnapshot? = nil, bus: PluginBusMessage? = nil) {
        guard let session else { return }; if type != "ready" { sequence += 1 }
        do { try FileHandle.standardOutput.write(contentsOf: PluginMessage(type: type, pluginID: id, session: session, sequence: sequence, snapshot: snapshot, features: features, bus: bus).encoded()) }
        catch { continual.shutdown(); model.shutdown(); exit(0) }
    }
}

@main struct NeroAgentApp: App {
    @StateObject private var plugin: AgentPlugin
    init() { let plugin = AgentPlugin(); _plugin = StateObject(wrappedValue: plugin) }
    var body: some Scene { WindowGroup { AgentView(plugin: plugin, model: plugin.model, continual: plugin.continual).onAppear { if plugin.hosted { NSApp.windows.first { $0.canBecomeKey }?.orderOut(nil) } } }.defaultSize(width: 850, height: 540) }
}
