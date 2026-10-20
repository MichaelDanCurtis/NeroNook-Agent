import AppKit
import ApplicationServices
import ScreenCaptureKit
import ModuleCore

/// On-demand Mac adapters. Handles belong to one fresh observed window, never a coordinate guess.
@MainActor final class MacAgentTools {
    struct Window {
        let choice: AvailableWindow
        let expires: Date
    }
    struct Element {
        let value: AXUIElement
        let window: String
        let role: String
        let label: String
        let path: [AXUIElement]
        let snapshot: MacControlSnapshot
    }
    private var epoch = UUID()
    private var windows: [String: Window] = [:]
    private var elements: [String: Element] = [:]
    var review: ((AgentToolReview) async throws -> Void)?
    func clear() { epoch = UUID(); windows = [:]; elements = [:] }
    func run(_ name: String, _ arguments: [String: String]) async throws -> [String: Any] {
        switch name {
        case "mac_apps":
            let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.prefix(128).map { ["name": $0.localizedName ?? "Application", "id": $0.bundleIdentifier ?? ""] }
            return AgentTools.response(try IntegrationTools.json(MacInventory(apps: apps, accessibility: AXIsProcessTrusted(), screenRecording: CGPreflightScreenCaptureAccess())))
        case "mac_windows":
            let available = try ContextAdapters.windows().filter { window in NSRunningApplication(processIdentifier: window.pid)?.bundleIdentifier == arguments["app"] }
            var output: [[String: String]] = []
            windows = windows.filter { $0.value.expires > Date() }
            for choice in available.prefix(16) {
                let handle = UUID().uuidString; windows[handle] = .init(choice: choice, expires: Date().addingTimeInterval(45))
                output.append(["window": handle, "app": choice.app, "title": choice.title])
            }
            return AgentTools.response(try IntegrationTools.json(output))
        case "mac_read_window":
            let handle = arguments["window"]!, window = try window(handle)
            var queue: [(value: AXUIElement, path: [AXUIElement], nodes: [MacControlSnapshot.Node])] = [(window.choice.element, [], [])]
            var result: [[String: String]] = [], count = 0
            elements = elements.filter { windows[$0.value.window]?.expires ?? .distantPast > Date() }
            let deadline = Date().addingTimeInterval(2)
            while !queue.isEmpty, count < 250, result.count < 90, Date() < deadline {
                let observed = queue.removeFirst(), item = observed.value; count += 1
                guard let role = ContextAdapters.string(item, kAXRoleAttribute), !secure(item, role) else { continue }
                let node = snapshot(item, role: role)
                let label = String(node.label.prefix(240))
                let value = ContextAdapters.string(item, kAXValueAttribute)
                let id = UUID().uuidString
                let path = observed.path + [item], nodes = observed.nodes + [node]
                elements[id] = .init(value: item, window: handle, role: role, label: label, path: path, snapshot: .init(path: nodes))
                var row = ["element": id, "role": role, "label": label]
                if let value { row["value"] = String(value.prefix(900)) }
                if !label.isEmpty || value != nil || [kAXButtonRole, kAXTextFieldRole, kAXTextAreaRole].contains(role) { result.append(row) }
                var children: CFTypeRef?
                if path.count < 32, AXUIElementCopyAttributeValue(item, kAXChildrenAttribute as CFString, &children) == .success, let children = children as? [AXUIElement] {
                    queue.append(contentsOf: children.prefix(max(0,250-count-queue.count)).map { ($0, path, nodes) })
                }
            }
            return AgentTools.response(try IntegrationTools.json(result))
        case "mac_screenshot":
            let id = arguments["window"]!, selected = try window(id)
            try await approve("Share window image", detail: "\(selected.choice.app) · \(selected.choice.title)", consequence: "Captures only this window and sends its image to your connected agent for this answer. No recording or image archive is made.")
            _ = try window(id)
            guard CGPreflightScreenCaptureAccess() else { throw AgentError.message("Allow Nero Agent in System Settings → Privacy & Security → Screen & System Audio Recording. No image was captured.") }
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let matches = content.windows.filter { $0.owningApplication?.processID == selected.choice.pid && $0.title == selected.choice.title }
            guard matches.count == 1, let target = matches.first else { throw AgentError.message("The exact window could not be matched safely. Refresh its windows and try again.") }
            let configuration = SCStreamConfiguration(); let scale = min(1, 1440/max(1,target.frame.width))
            configuration.width = max(1,Int(target.frame.width*scale)); configuration.height = max(1,Int(target.frame.height*scale)); configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target), configuration: configuration)
            _ = try window(id); try Task.checkCancellation()
            let rep = NSBitmapImageRep(cgImage: image)
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.65]), data.count < 2_500_000 else { throw AgentError.message("This window image exceeds its limit.") }
            return ["contentItems": [["type": "inputImage", "imageUrl": "data:image/jpeg;base64," + data.base64EncodedString()]], "success": true]
        case "mac_open":
            let target = arguments["target"]!
            let url: URL
            if let parsed = URL(string: target), parsed.scheme == "https", parsed.host != nil, parsed.user == nil, parsed.password == nil { url = parsed }
            else if target.range(of: "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)+$", options: .regularExpression) != nil, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) { url = app }
            else { throw AgentError.message("Use an installed app bundle identifier or HTTPS URL.") }
            try await approve("Open on your Mac", detail: target, consequence: "Opens this application or website. You can close it normally.")
            guard NSWorkspace.shared.open(url) else { throw AgentError.message("macOS could not open that target.") }; return AgentTools.response("Opened \(target).")
        default:
            let key = arguments["element"]!, selected = try element(key)
            let context = try window(selected.window)
            let value = arguments["text"] ?? arguments["direction"] ?? ""
            if name == "mac_type" {
                guard [kAXTextFieldRole, kAXTextAreaRole, "AXComboBox"].contains(selected.role), value.utf8.count <= 8192 else { throw AgentError.message("Choose an editable text element and keep the replacement under 8 KiB.") }
                var settable: DarwinBoolean = false
                guard AXUIElementIsAttributeSettable(selected.value, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue else { throw AgentError.message("This element does not allow direct text editing.") }
            }
            if name == "mac_scroll", !["up", "down", "left", "right"].contains(value) { throw AgentError.message("Choose a scroll direction.") }
            let detail = "\(context.choice.app) · \(context.choice.title)\n\(selected.snapshot.reviewPath)" + (value.isEmpty ? "" : "\n\n" + value)
            guard detail.utf8.count <= 32000 else { throw AgentError.message("This control's context is too large to review safely. Choose a smaller, specific control. Nothing was run.") }
            try await approve(name == "mac_type" ? "Replace text" : name == "mac_press" ? "Press control" : "Scroll", detail: detail, consequence: name == "mac_type" ? "Replaces this field's entire value. No automatic undo is provided." : "Operates this exact control. The app determines its effect; automatic undo is not guaranteed.")
            let fresh = try element(key)
            let result: AXError
            if name == "mac_type" { result = AXUIElementSetAttributeValue(fresh.value, kAXValueAttribute as CFString, value as CFString) }
            else { result = AXUIElementPerformAction(fresh.value, (name == "mac_press" ? kAXPressAction : "AXScroll" + value.capitalized) as CFString) }
            guard result == .success else { throw AgentError.message("This application rejected the Accessibility action. No alternate input was attempted.") }
            clear(); return AgentTools.response("macOS accepted the requested control operation. Read the window again to verify the resulting state.")
        }
    }
    private struct MacInventory: Encodable {
        var apps: [[String: String]]; var accessibility: Bool; var screenRecording: Bool
    }
    private func secure(_ value: AXUIElement, _ role: String) -> Bool {
        let subrole = ContextAdapters.string(value, kAXSubroleAttribute)
        return role == "AXSecureTextField" || subrole == kAXSecureTextFieldSubrole || (role == kAXTextFieldRole && subrole == nil)
    }
    private func window(_ id: String) throws -> Window {
        guard AXIsProcessTrusted(), let result = windows[id], result.expires > Date(), let app = NSRunningApplication(processIdentifier: result.choice.pid), !app.isTerminated, app.launchDate == result.choice.launched,
              !["com.apple.SecurityAgent", "com.apple.loginwindow", "com.apple.keychainaccess"].contains(app.bundleIdentifier ?? ""), String((ContextAdapters.string(result.choice.element, kAXTitleAttribute) ?? "Untitled window").prefix(120)) == result.choice.title else { throw AgentError.message("Mac access is missing or the window changed/expired. Refresh the exact window.") }
        var current: CFTypeRef?
        let appElement = AXUIElementCreateApplication(result.choice.pid)
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &current) == .success,
              let current = current as? [AXUIElement], current.contains(where: { CFEqual($0, result.choice.element) }) else { throw AgentError.message("The selected window closed. Refresh its windows.") }
        return result
    }
    private func element(_ id: String) throws -> Element {
        guard let result = elements[id] else { throw AgentError.message("Refresh this window before operating a control.") }; _ = try window(result.window)
        let current = try currentPath(result.value, window: windows[result.window]!.choice.element)
        let sameElements = current.elements.count == result.path.count && zip(current.elements, result.path).allSatisfy { CFEqual($0.0, $0.1) }
        try result.snapshot.validate(current: current.snapshot, sameElements: sameElements)
        return result
    }
    private func snapshot(_ value: AXUIElement, role: String) -> MacControlSnapshot.Node {
        .init(role: role, subrole: ContextAdapters.string(value, kAXSubroleAttribute), identifier: ContextAdapters.string(value, kAXIdentifierAttribute), title: ContextAdapters.string(value, kAXTitleAttribute), description: ContextAdapters.string(value, kAXDescriptionAttribute), value: ContextAdapters.string(value, kAXValueAttribute))
    }
    private func currentPath(_ element: AXUIElement, window: AXUIElement) throws -> (elements: [AXUIElement], snapshot: MacControlSnapshot) {
        var current = element, path: [AXUIElement] = [], nodes: [MacControlSnapshot.Node] = []
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(700))
        for _ in 0..<32 {
            guard ContinuousClock.now < deadline else { throw AgentError.message("The control's context is not responding quickly enough to verify safely. Nothing was run.") }
            AXUIElementSetMessagingTimeout(current, 0.1)
            guard !path.contains(where: { CFEqual($0, current) }), let role = ContextAdapters.string(current, kAXRoleAttribute), !secure(current, role) else { throw AgentError.message("This control is unavailable or protected. Refresh the window.") }
            path.append(current); nodes.append(snapshot(current, role: role))
            if CFEqual(current, window) { return (Array(path.reversed()), .init(path: Array(nodes.reversed()))) }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = unsafeBitCast(parent, to: AXUIElement.self)
        }
        throw AgentError.message("The control no longer belongs to the observed window. Refresh and review a new request. Nothing was run.")
    }
    private func approve(_ title: String, detail: String, consequence: String) async throws {
        let token = epoch
        guard let review else { throw AgentError.message("Tool review is unavailable.") }; try await review(.init(title: title, detail: detail, consequence: consequence)); guard token == epoch else { throw CancellationError() }; try Task.checkCancellation()
    }
}
