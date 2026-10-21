import AppKit
import SwiftUI
import Combine
import ModuleCore
import NookPluginSDK

@MainActor final class AgentPlugin: ObservableObject {
    @Published var focusedPanel = "conversation"
    let model = AgentModel()
    private var modelPage = 0
    let tools = AgentToolbox()
    let speech = PluginSpeechClient()
    let talk = AgentTalk()
    private var streaming = false
    private var speechObservation: AnyCancellable?
    private var toolsObservation: AnyCancellable?
    let continual = ContinualModel()
    let id = "cafe.nero.plugin.agent"
    let hosted = CommandLine.arguments.contains("--neronook-plugin")
    private var session: UUID?
    private var sequence: UInt64 = 0
    private var input = PluginLines()
    private var catalog = PluginCatalogAccumulator()
    private var subscriptions = Set<PluginActionAddress>()
    private var catalogGenerations: [PluginActionAddress: UUID] = [:]
    private var recentStateEvents: [PluginActionAddress: [UUID]] = [:]
    private var stateHistories: [PluginActionAddress: StateChannelHistory] = [:]
    private var timer: Timer?
    private var forms = false
    private var customViews = false
    private var reads: [UUID: (entry: PluginCatalogEntry, chat: Bool, continuation: CheckedContinuation<[String: PluginValue], Error>)] = [:]
    private var submitted: Set<UUID> = []
    private var incoming: [UUID] = []
    private var running: Set<UUID> = []
    private var activity: NSObjectProtocol?
    static var evidenceAction: PluginRegisteredAction {
        var action = PluginEvidenceAnswerContract.action; action.title = "Ask Nero Agent · ChatGPT with citations"; return action
    }
    static var evidenceChatAction: PluginRegisteredAction {
        var action = PluginEvidenceChatContract.action; action.title = "Ask Nero Agent · meeting chat with citations"; return action
    }
    static var askAction: PluginRegisteredAction {
        .init("ask", title: "Ask ChatGPT", input: .init([.init("prompt", .string), .init("context", .string, required: false)]), output: .init([.init("reply", .string)]), cancellable: true, timeoutSeconds: 180)
    }
    static var decisionAction: PluginRegisteredAction {
        .init("decide", title: "Evaluate a condition with ChatGPT", input: askAction.input, output: .init([.init("reply", .string), .init("decision", .boolean)]), cancellable: true, timeoutSeconds: 180)
    }
    init() {
        toolsObservation = tools.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        tools.changed = { [weak self] in self?.objectWillChange.send(); self?.publish() }
        tools.invalidated = { [weak self] in self?.talk.stop(); self?.model.cancel() }
        model.integrationDefinitions = { [weak self] in self?.tools.definitions ?? [] }
        model.integrationKeys = { [weak self] in self?.tools.keys ?? [:] }
        model.webSearch = { [weak self] in self?.tools.web == true }
        model.integrationTool = { [weak self] name, arguments in guard let self else { throw CancellationError() }; return try await self.tools.run(name, arguments) }
        model.cancelIntegrations = { [weak self] in self?.tools.cancelTurn() }
        talk.bind(model); talk.available = { [weak self] in self?.streaming == true }
        talk.client.send = { [weak self] in self?.bus($0) }
        talk.changed = { [weak self] in self?.objectWillChange.send();self?.publish() }
        speech.send = { [weak self] in self?.bus($0) }
        speech.select(UserDefaults.standard.string(forKey: "speechProvider") ?? "")
        speechObservation = speech.objectWillChange.sink { [weak self] in Task { @MainActor in self?.objectWillChange.send(); self?.publish() } }

        model.changed = { [weak self] in
            guard let self else { return }; if self.talk.active && self.model.email == nil { self.talk.stop() }; self.objectWillChange.send(); self.publish()
        }
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
                    guard let self else { return }; guard !data.isEmpty else { self.talk.stop(); self.speech.stop(); self.continual.shutdown(); self.tools.disconnectAll(); self.model.shutdown(); exit(0) }
                    do { for m in try self.input.append(data) { self.receive(m) } } catch { self.talk.stop(); self.speech.stop(); self.continual.shutdown(); self.tools.disconnectAll(); self.model.shutdown(); exit(1) }
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
            guard message.type == "hello" else { exit(1) }; session = message.session; PluginAppearanceStore.shared.beginSession(pluginID:id,session:message.session)
            streaming = message.features?.contains("action-stream-v1") == true
            talk.client.accessRequestsAvailable = message.features?.contains("action-access-v1") == true
            customViews = message.features?.contains("custom-views-v1") == true
            forms = message.features?.contains("forms-v1") == true
            emit("ready", features: ["appearance-v1", "dashboard-v1", "panels-v1", "actions-v1", "forms-v1"] + (streaming ? ["action-stream-v1"] : []) + (talk.client.accessRequestsAvailable ? ["action-access-v1"] : []) + (customViews ? ["custom-views-v1"] : []))
            if message.features?.contains("actions-v1") == true { bus(.init(.register, registration: .init(actions: [Self.askAction, Self.decisionAction, Self.evidenceAction, Self.evidenceChatAction]))); bus(.init(.discover)) }
            publish(); return
        }
        guard message.session == session else { exit(1) }
        if message.type == "appearance" { _ = PluginAppearanceStore.shared.receive(message); return }
        if message.type == "action", let action = message.action {
            if action == "configure" { configure() }
            if action == "stop" { if talk.active {talk.stop()}else if model.busy{model.cancel()} }
            if action == "review_proposal" { reviewProposal() }
            if action == "open_chat" { openChat() }
        }
        if message.type == "viewEvent", let event = message.viewEvent { do { try handle(event) } catch { model.status = error.localizedDescription }; return }
        guard let message = message.bus else { return }
        speech.receive(message); talk.client.receive(message)
        switch message.operation {
        case .catalog:
            if (try? catalog.receive(message)) == true {
                let oldChannels = Dictionary(uniqueKeysWithValues: model.catalog.compactMap { entry in
                    entry.channel?.kind == .state ? (entry.address, entry) : nil
                })
                speech.catalog(catalog.entries);talk.client.catalog(catalog.entries)
                model.catalog = catalog.entries.filter { $0.address.plugin != id && !PluginSpeechContract.accepts($0) && !PluginSpeechConversation.accepts($0) }
                for key in Array(reads.keys) where !model.catalog.contains(reads[key]!.entry) {
                    reads.removeValue(forKey: key)?.continuation.resume(throwing: AgentError.message("Tool access changed. The result was discarded."))
                }
                let newChannels = Dictionary(uniqueKeysWithValues: model.catalog.compactMap { entry in
                    entry.channel?.kind == .state ? (entry.address, entry) : nil
                })
                let permitted = Set(newChannels.keys.sorted { $0.key < $1.key }.prefix(16))
                // A provider reconnect can return the same entry bytes. Treat
                // every completed host catalog as a new local epoch, so recent
                // fact history never bridges a possible provider restart.
                let changed = Set(oldChannels.keys).union(newChannels.keys)
                for address in changed {
                    model.states[address.key] = nil
                    recentStateEvents[address] = nil
                    stateHistories[address] = nil
                    catalogGenerations[address] = permitted.contains(address) ? UUID() : nil
                }
                for address in subscriptions.subtracting(permitted).union(changed.intersection(subscriptions)) {
                    bus(.init(.unsubscribe, address: address))
                }
                for address in permitted.subtracting(subscriptions).union(changed.intersection(permitted)) {
                    bus(.init(.subscribe, address: address))
                }
                subscriptions = permitted; continual.catalogChanged(); publish()
            }
        case .event:
            if let address = message.address, subscriptions.contains(address),
               let entry = model.catalog.first(where: { $0.address == address && $0.channel?.kind == .state }),
               let generation = catalogGenerations[address] {
                do {
                    let accepted = try StateChannelReceipt.accept(message, entry: entry,
                        catalogGeneration: generation, previous: model.states[address.key], now: Date())
                    guard let accepted else { return }
                    var recent = recentStateEvents[address, default: []]
                    guard !recent.contains(accepted.eventID) else { return }
                    recent.append(accepted.eventID)
                    if recent.count > 256 { recent.removeFirst() }
                    recentStateEvents[address] = recent
                    var history = stateHistories[address] ?? StateChannelHistory()
                    history.record(accepted)
                    stateHistories[address] = history
                    model.states[address.key] = accepted; publish()
                } catch { return }
            }
        case .execute:
            guard !talk.active else { bus(.init(.update,requestID:message.requestID,update:.init(.failed,message:"Finish the voice conversation before another Agent request.")));return }
            guard !incoming.contains(message.requestID) else { return }
            incoming.append(message.requestID); if incoming.count > 256 { incoming.removeFirst() }
            if message.address == PluginActionAddress(id, PluginEvidenceAnswerContract.id) || message.address == PluginActionAddress(id, PluginEvidenceChatContract.id) {
                do {
                    let evidence: PluginEvidenceQuestion, history: [PluginEvidenceExchange]
                    if message.address?.name == PluginEvidenceChatContract.id { (evidence, history) = try PluginEvidenceChatContract.decode(message.values ?? [:]) }
                    else { evidence = try PluginEvidenceQuestion(values: message.values ?? [:]); history = [] }
                    running.insert(message.requestID)
                    model.ask(evidence.question, request: message.requestID, evidence: evidence, evidenceHistory: history)
                } catch { bus(.init(.update, requestID: message.requestID, update: .init(.failed, message: "Invalid evidence question"))) }
                return
            }
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
        func json<T: Encodable>(_ value: T) -> String { String(data: (try? JSONEncoder().encode(value)) ?? Data(), encoding: .utf8) ?? "[]" }
        func choices(_ values: [[String: String]], selected: String) -> [[String: String]] {
            let ordered = values.filter { $0["key"] == selected } + values.filter { $0["key"] != selected }
            return ordered.map { ["key": $0["key"] ?? "", "name": AgentPresentation.prefix($0["name"] ?? "", bytes: 128)] }
        }
        var messageBudget = 18000
        var shown = AgentPresentation.messages(model.messages, budget: messageBudget)
        let history = model.conversations.reversed().map { ["id": $0.id.uuidString, "title": AgentPresentation.prefix($0.title, bytes: 96)] }
        let talkState: [String:PluginValue] = ["controls":.string((try? talk.client.controls?.encoded()) ?? ""),"accessAvailable":.boolean(talk.client.accessRequestsAvailable),"active":.boolean(talk.active),"ready":.boolean(talk.client.ready),"mode":.string(talk.mode),"replyPace":.string(talk.quickReplies ? "quick":"default"),"phase":.string(talk.client.awaitingPermission ? "permission" : talk.phase),"partial":.string(AgentPresentation.prefix(talk.recoveryDraft.isEmpty ? talk.partial : talk.recoveryDraft,bytes:1400)),"status":.string(AgentPresentation.prefix(talk.active && talk.client.ready ? talk.status:talk.client.status,bytes:400)),"level":.number(talk.level),"outputLevel":.number(talk.outputLevel),"expression":.string(json(talk.expression.pose)),"expressionEnabled":.boolean(talk.expressionEnabled),"provider":.string(talk.client.selectedKey),"providers":.string(json(choices(talk.client.providers.map{["key":$0.address.key,"name":$0.address.plugin]},selected:talk.client.selectedKey)))]
        var view = PluginCustomView(entry: "chat/index.html", revision: "chat2", state: [
            "talk": .string(json(talkState)),
            "models": .string(json(AgentModelChoice.page(model.models, selected: model.selectedModel, index:modelPage))), "modelPage": .number(Double(min(modelPage,max(0,(model.models.count-1)/12)))), "modelPages": .number(Double(max(1,(model.models.count+11)/12))), "selectedModel": .string(model.selectedModel),
            "modelsLoading": .boolean(model.modelsLoading), "modelStatus": .string(model.modelStatus),
            "toolSummary": .string(tools.summary), "toolReviews": .string(json(AgentPresentation.reviews(tools.reviews.pending))),
            "speechProviders": .string(json(choices(speech.providers.map { ["key": $0.address.key, "name": $0.address.plugin] }, selected: speech.selectedKey))),
            "speechProvider": .string(speech.selectedKey), "speechActive": .boolean(speech.active), "speechStatus": .string(String(speech.status.prefix(240))),
            "messages": .string(shown.json), "history": .string(json(history)), "conversation": .string(model.currentID.uuidString),
            "busy": .boolean(model.busy), "connected": .boolean(model.email != nil), "status": .string(model.status),
            "title": .string(model.conversation.title), "retention": .number(Double(model.retentionDays)),
            "historyError": .string(model.historyError ?? ""), "omitted": .boolean(shown.omitted),
            "proposal": .string(model.proposal.map { AgentPresentation.prefix(($0.action ?? "") + "\n" + $0.arguments, bytes: 1600) } ?? ""),
            "contextCount": .number(Double(model.catalog.count)), "presence": .string(talk.active ? talk.phase : continual.phase), "watchCount": .number(Double(continual.archive.watches.filter { !$0.dismissed && !$0.terminalSeen }.count))
        ], events: [
            .init("tools"), .init("tool_review", input: .init([.init("id", .string), .init("allow", .boolean)])), .init("link", input: .init([.init("url", .string)])),
            AgentTalkViewControl.definition,
            .init("speech_provider", input: .init([.init("key", .string)])), .init("read", input: .init([.init("id", .string)])), .init("stop_speech"),
            .init("send", input: .init([.init("text", .string), .init("context", .boolean)])), .init("stop"), .init("new"), .init("retry"),
            .init("select", input: .init([.init("id", .string)])), .init("settings", input: .init([.init("command", .string, required:false), .init("id", .string, required:false)])), .init("review"), .init("open", input: .init([.init("page", .string, required:false)])), .init("copy", input: .init([.init("id", .string)]))
        ])
        view.avatarReactions=true;view.avatarPlayback=speech.avatarPlayback
        view.state["reactionSpeaking"] = .boolean(speech.avatarPlayback != nil)
        while (try? view.validate()) == nil, messageBudget > 512 {
            messageBudget = max(512, messageBudget / 2)
            shown = AgentPresentation.messages(model.messages, budget: messageBudget)
            view.state["messages"] = .string(shown.json)
            view.state["omitted"] = .boolean(shown.omitted)
        }
        return view
    }
    func handle(_ event: PluginViewEvent) throws {
        if event.panelID == "awareness" { try handleAwareness(event); return }
        guard event.panelID == "conversation" else { throw AgentError.message("Unknown view.") }; try chatView.validate(event)
        if event.name == PluginAvatarPlayback.event {
            guard case .string(let raw)=event.values["id"],let id=UUID(uuidString:raw),case .string(let kind)=event.values["kind"] else {throw ModuleProblem("Invalid avatar reaction.")}
            if kind == "stop" {speech.stopReaction(id)}
            else if let reaction=PluginAvatarReaction(rawValue:kind), !(talk.active || model.busy) {try speech.react(reaction,id:id)}
            publish();return
        }
        switch event.name {
        case "tools": tools.visible = true; openChat()
        case "tool_review": if case .string(let id) = event.values["id"], let id = UUID(uuidString: id), case .boolean(let allow) = event.values["allow"] {
            guard !allow || AgentPresentation.canApprove(id, pending: tools.reviews.pending) else { throw AgentError.message("Open the full request in Tools before approving it. No operation was run.") }
            tools.reviews.resolve(id, allow: allow)
        }
        case "link": if case .string(let value) = event.values["url"], let url = URL(string: value), ["https", "http"].contains(url.scheme ?? ""), url.host != nil, url.user == nil, url.password == nil { NSWorkspace.shared.open(url) }
        case "talk":
            guard !CommandLine.arguments.contains("--protocol-test"),case .string(let command)=event.values["command"] else{return}
            switch command {
            case "start":speech.stop();let context:Bool={if case .boolean(let value)=event.values["context"]{return value};return false}();try talk.start(context:context)
            case "stop":talk.stop()
            case "settings":talk.stop();try talk.client.openSettings(mode:talk.mode)
            case "mode":if case .string(let value)=event.values["value"]{try talk.chooseMode(value)}
            case "sensitivity":if case .string(let value)=event.values["value"],let number=Int(value){try talk.client.setInterruptionSensitivity(number)}
            case "expression":try talk.chooseExpression(AgentTalkViewControl.expression(event.values))
            case "pace":if case .string(let value)=event.values["value"]{try talk.chooseReplyPace(value)}
            case "provider":if case .string(let value)=event.values["value"]{talk.client.select(value)}
            default:break
            }
        case "speech_provider": if case .string(let key) = event.values["key"] { speech.select(key); UserDefaults.standard.set(key, forKey: "speechProvider") }
        case "read": if case .string(let id) = event.values["id"], let message = model.messages.first(where: { $0.id.uuidString == id && $0.role == "assistant" && $0.phase == "complete" }) { try speech.read(message.text) }
        case "stop_speech": speech.stop()
        case "send": speech.stop(); if case .string(let text) = event.values["text"], case .boolean(let context) = event.values["context"], !model.busy { if talk.active {try talk.sendText(text)} else {model.sendChat(text, useContext: context)} }
        case "stop": if talk.active{talk.stop()}else{model.cancel()}
        case "new": talk.stop(); speech.stop(); model.newConversation()
        case "retry": talk.stop(); model.retry()
        case "select": talk.stop(); speech.stop(); if case .string(let id) = event.values["id"], let uuid = UUID(uuidString: id) { model.selectConversation(uuid) }
        case "copy":
            if case .string(let id) = event.values["id"], let message = model.messages.first(where: { $0.id.uuidString == id }), !message.text.isEmpty {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.text, forType: .string); model.status = "Copied message"
            }
        case "settings":
            if case .string("model") = event.values["command"], case .string(let value) = event.values["id"] { try model.chooseModel(value) }
            else if case .string("refresh_models") = event.values["command"] { model.refreshModels() }
            else if case .string("model_page") = event.values["command"], case .string(let value) = event.values["id"], let page = Int(value), page >= 0, page < max(1,(model.models.count+11)/12) { modelPage = page; publish() }
            else { configure() }
        case "review": reviewProposal()
        case "open": focusedPanel = event.values["page"] == .string("activity") ? "awareness" : "conversation"; openChat()
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
        var snapshot = PluginSnapshot(title: "Nero Agent", status: talk.active ? talk.status : (model.busy ? model.status : continual.phase + " · " + model.status), activity: String((model.busy ? model.status : continual.phase + " · " + continual.status).prefix(100)), actions: customViews ? [] : [
            .init("open_chat", "Open chat", symbol: "arrow.up.left.and.arrow.down.right"),
            .init("stop", "Stop", enabled: model.busy || talk.active, symbol: "stop.fill"),
            .init("review_proposal", "Review proposed action", enabled: model.proposal != nil && !model.busy, symbol: "checkmark.shield")
        ], badge: model.email == nil ? "Not connected" : "ChatGPT", panels: [
            customViews ? .init("conversation", "Conversation", customView: chatView) : .init("conversation", "Conversation", sections: sections, forms: forms ? [form] : nil),
        ] + (customViews ? [] : [
            .init("awareness", "Activity", sections: [.init("Continual Agent", continual.phase + " · Open Agent to manage sources and watches.")]),
            .init("context", "Context preview", sections: contextSections.isEmpty ? [.init("No module context", "Allow Nero Agent to receive selected module updates in Nook Settings → Modules → Actions and connections. Receiving an update here does not send it to ChatGPT. Choose an attachment when asking.")] : contextSections)
        ]))
        snapshot.assistantSpeech = .init(speaking:talk.phase == "speaking",level:talk.outputLevel,expression:talk.expression.pose)
        if !tools.reviews.pending.isEmpty || model.proposal != nil {
            snapshot.attention = .init(id:"action-review",kind:.needsYou,title:"Nero needs your approval")
        }
        guard (try? snapshot.validate()) != nil else {
            emit("snapshot", snapshot: .init(title: "Nero Agent", status: "View unavailable · open Agent", actions: [.init("open_chat", "Open Agent"), .init("stop", "Stop reply", enabled: model.busy)])); return
        }; emit("snapshot", snapshot: snapshot)
    }
    private func bus(_ value: PluginBusMessage) { emit("bus", bus: value) }
    private func emit(_ type: String, features: [String]? = nil, snapshot: PluginSnapshot? = nil, bus: PluginBusMessage? = nil) {
        guard let session else { return }; if type != "ready" { sequence += 1 }
        do { try FileHandle.standardOutput.write(contentsOf: PluginMessage(type: type, pluginID: id, session: session, sequence: sequence, snapshot: snapshot, features: features, bus: bus).encoded()) }
        catch { tools.disconnectAll(); continual.shutdown(); model.shutdown(); exit(0) }
    }
}

@main struct NeroAgentApp: App {
    @StateObject private var plugin: AgentPlugin
    init() { let plugin = AgentPlugin(); _plugin = StateObject(wrappedValue: plugin) }
    var body: some Scene { WindowGroup { AgentView(plugin: plugin, model: plugin.model, continual: plugin.continual).pluginThemed().onAppear { if plugin.hosted { NSApp.windows.first { $0.canBecomeKey }?.orderOut(nil) } } }.defaultSize(width: 850, height: 540) }
}
