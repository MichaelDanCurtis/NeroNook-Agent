import SwiftUI
import ModuleCore
import NookPluginSDK

extension AgentPlugin {
    var awarenessView: PluginCustomView {
        func json<T: Encodable>(_ value: T) -> String { String(decoding: (try? JSONEncoder().encode(value)) ?? Data("[]".utf8), as: UTF8.self) }
        let c = continual
        let watches = c.archive.watches.filter { !$0.dismissed }
        let activities = Array(c.archive.activities.reversed())
        let watchPage = min(c.watchPage, max(0, (watches.count - 1) / 6))
        let runPage = min(c.runPage, max(0, (c.runs.count - 1) / 6))
        let activityPage = min(c.activityPage, max(0, (activities.count - 1) / 8))
        let sources = c.archive.sources.prefix(8).map { s in
            ["id": s.id.uuidString, "name": String(s.name.prefix(80)), "kind": s.kind.rawValue,
             "scope": s.enabled ? (s.allowCloud ? "Available to ChatGPT" : "Local only") : "Excluded",
             "health": c.notices[s.id].map { String($0.prefix(120)) } ?? (c.context.snapshot(sources: [s], cloud: false, now: Date()).isEmpty ? "Waiting for fresh context" : "Fresh context available")]
        }
        var view = PluginCustomView(entry: "awareness/index.html", revision: "awareness1", state: [
            "phase": .string(model.busy ? "Working" : c.phase), "status": .string(c.storageError ?? c.status), "paused": .boolean(c.archive.paused || c.locked), "quiet": .boolean(c.archive.quiet),
            "sources": .string(json(sources)), "watches": .string(json(Array(watches.dropFirst(watchPage * 6).prefix(6)))),
            "runs": .string(json(Array(c.runs.dropFirst(runPage * 6).prefix(6)))), "activities": .string(json(Array(activities.dropFirst(activityPage * 8).prefix(8)))),
            "watchPage": .number(Double(watchPage)), "watchPages": .number(Double(max(1, (watches.count + 5) / 6))),
            "runPage": .number(Double(runPage)), "runPages": .number(Double(max(1, (c.runs.count + 5) / 6))),
            "activityPage": .number(Double(activityPage)), "activityPages": .number(Double(max(1, (activities.count + 7) / 8))),
            "unread": .number(Double(c.archive.activities.filter { !$0.read }.count)), "sourceCount": .number(Double(c.archive.sources.count)), "hasNook": .boolean(c.archive.sources.contains { $0.kind == .nook })
        ], events: [
            .init("pause"), .init("quiet"), .init("clear"), .init("refresh"), .init("sources"), .init("nook"), .init("acknowledge"),
            .init("watch", input: .init([.init("id", .string)])),
            .init("manage", input: .init([.init("id", .string), .init("action", .string)])),
            .init("page", input: .init([.init("group", .string), .init("index", .number, minimum: 0, maximum: 40)]))
        ])
        // Escaped/unusual Unicode titles must never break the host heartbeat.
        for key in ["activities", "sources", "runs", "watches"] where (try? view.validate()) == nil {
            view.state[key] = .string("[]")
            view.state["status"] = .string("Some long items are omitted from this page. Use sources or another page to continue.")
        }
        return view
    }
    func handleAwareness(_ event: PluginViewEvent) throws {
        try awarenessView.validate(event)
        switch event.name {
        case "pause": continual.setPaused(!continual.archive.paused)
        case "quiet": continual.quiet(!continual.archive.quiet)
        case "clear": continual.clearContext()
        case "refresh": continual.refresh()
        case "sources": openChat(); continual.sourcesVisible = true
        case "nook": continual.addNook()
        case "acknowledge": continual.acknowledge()
        case "watch": if case .string(let id) = event.values["id"] { continual.watch(id) }
        case "manage": if case .string(let id) = event.values["id"], let uuid = UUID(uuidString: id), case .string(let action) = event.values["action"], ["pause", "dismiss"].contains(action) { continual.changeWatch(uuid, action: action) }
        case "page":
            if case .string(let group) = event.values["group"], case .number(let n) = event.values["index"], n.rounded() == n {
                if group == "watch" { continual.watchPage = min(Int(n), max(0, (continual.archive.watches.filter { !$0.dismissed }.count - 1) / 6)) }
                if group == "run" { continual.runPage = min(Int(n), max(0, (continual.runs.count - 1) / 6)) }
                if group == "activity" { continual.activityPage = min(Int(n), max(0, (continual.archive.activities.count - 1) / 8)) }
            }
        default: break
        }
    }
}

struct ContextSourcesView: View {
    @ObservedObject var model: ContinualModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { VStack(alignment: .leading) { Text("Nero can see").font(.title2.bold()); Text("Choose the context. You stay in control.").foregroundStyle(.secondary) }; Spacer(); Button("Done") { model.sourcesVisible = false } }
            HStack { Button("Add workspace…") { model.addWorkspace() }; Button("Choose window…") { model.chooseWindow() }; Button("Add Nook activity") { model.addNook() } }
            Text("New sources stay on this Mac. “Available to ChatGPT” permits the selected preview to be read only when you enable context for a chat message. Nothing here grants control of an app.").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let goals = model.archive.watches.filter { !$0.dismissed && !$0.terminalSeen }
                    if !goals.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Active goals").font(.headline)
                            Text("Follow the final outcome of these exact automation runs. Goals share the Nook activity source's observation and ChatGPT controls.").font(.caption).foregroundStyle(.secondary)
                            ForEach(goals) { goal in Text("\(goal.title) · \(goal.paused ? "Paused" : "Watching")").font(.callout) }
                        }.padding(12)
                    }
                    if model.archive.sources.isEmpty { Text("No sources selected. Nero is not observing your screen or workspace.").padding(.vertical, 25) }
                    ForEach(model.archive.sources) { source in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Image(systemName: source.kind == .workspace ? "folder" : source.kind == .window ? "macwindow" : "square.stack.3d.up"); Text(source.name).font(.headline).lineLimit(2); Spacer(); Button("Remove") { model.removeSource(source.id) }.accessibilityIdentifier("source-remove-\(source.id)") }
                            HStack {
                                Toggle("Observe", isOn: Binding(get: { source.enabled }, set: { model.updateSource(source.id, enabled: $0) }))
                                Toggle("Available to ChatGPT", isOn: Binding(get: { source.allowCloud }, set: { model.updateSource(source.id, cloud: $0) })).disabled(!source.enabled)
                            }
                            if let notice = model.notices[source.id] { Text(notice).font(.caption).foregroundStyle(.orange) }
                            if let fact = model.context.snapshot(sources: [source], cloud: false, now: Date()).first {
                                Text("Updated \(fact.observed.formatted(date: .omitted, time: .standard)) · expires after 30 seconds").font(.caption).foregroundStyle(.secondary)
                                DisclosureGroup("Preview observed context") { Text(fact.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6) }
                            } else { Text(source.enabled ? "No fresh context" : "Excluded").font(.caption).foregroundStyle(.secondary) }
                        }.padding(14).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            HStack { Button(model.archive.paused ? "Resume awareness" : "Pause awareness") { model.setPaused(!model.archive.paused) }; Button("Clear current context") { model.clearContext() }; Spacer(); Button("Refresh") { model.refresh() } }
            Text(model.storageError ?? model.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(22).frame(width: 650, height: 550).preferredColorScheme(.dark)
        .sheet(isPresented: $model.windowPickerVisible) {
            VStack(alignment: .leading, spacing: 15) {
                HStack { Text("Choose one window").font(.title2.bold()); Spacer(); Button("Cancel") { model.windowPickerVisible = false } }
                Text("Nero reads the selected window’s Accessibility text. Password fields are skipped. No screenshots are stored. Window selection must be renewed after restarting Agent.").font(.callout).foregroundStyle(.secondary)
                ScrollView { VStack(alignment: .leading) { ForEach(model.windowChoices) { window in Button { model.selectWindow(window) } label: { VStack(alignment: .leading) { Text(window.app).font(.headline); Text(window.title).font(.caption) }.frame(maxWidth: .infinity, alignment: .leading).padding(9) }.buttonStyle(.bordered) } } }
            }.padding(22).frame(width: 570, height: 430)
        }
    }
}
