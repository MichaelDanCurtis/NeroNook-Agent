import AppKit
import ApplicationServices
import ModuleCore

struct AvailableWindow: Identifiable {
    let id = UUID()
    let app: String
    let title: String
    let pid: pid_t
    let launched: Date?
    let element: AXUIElement
}

enum ContextAdapters {
    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
    @MainActor static func windows() throws -> [AvailableWindow] {
        guard AXIsProcessTrusted() else { throw AgentError.message("Allow Nero Agent in macOS Privacy & Security → Accessibility, then choose a window. No screen observation has started.") }
        var windows: [AvailableWindow] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let ax = AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(ax, 0.2)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &value) == .success, let list = value as? [AXUIElement] else { continue }
            for window in list.prefix(8) {
                let title = String((string(window, kAXTitleAttribute) ?? "Untitled window").prefix(120))
                windows.append(.init(app: app.localizedName ?? "Application", title: title, pid: app.processIdentifier, launched: app.launchDate, element: window))
            }
            if windows.count >= 64 { break }
        }
        return Array(windows.prefix(64))
    }
    @MainActor static func windowText(_ window: AvailableWindow) throws -> String {
        guard AXIsProcessTrusted(), let app = NSRunningApplication(processIdentifier: window.pid), app.launchDate == window.launched, !app.isTerminated else { throw AgentError.message("Selected window is unavailable. Choose it again.") }
        AXUIElementSetMessagingTimeout(window.element, 0.1)
        // Exact AX element, never the new frontmost window. Bound work and skip secure subtrees.
        var queue = [window.element], parts: [String] = [], count = 0, bytes = 0
        let deadline = Date().addingTimeInterval(0.7)
        while !queue.isEmpty, count < 100, bytes < 6000, Date() < deadline {
            let item = queue.removeFirst(); count += 1
            guard let role = string(item, kAXRoleAttribute) else { continue }
            // A text field whose security classification cannot be read is excluded.
            let rawSubrole = string(item, kAXSubroleAttribute)
            if role == kAXTextFieldRole && rawSubrole == nil { continue }
            let subrole = rawSubrole ?? ""
            if subrole == kAXSecureTextFieldSubrole || role == "AXSecureTextField" { continue }
            for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
                if let text = string(item, attribute), !text.isEmpty {
                    let bounded = String(text.prefix(400))
                    if !parts.contains(bounded), bytes + bounded.utf8.count <= 6000 { parts.append(bounded); bytes += bounded.utf8.count }
                }
            }
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(item, kAXChildrenAttribute as CFString, &value) == .success, let children = value as? [AXUIElement] { queue.append(contentsOf: children.prefix(max(0, 100 - count - queue.count))) }
        }
        guard !parts.isEmpty else { throw AgentError.message("This window exposes no readable Accessibility text. No screenshot was captured.") }
        return "Selected window · \(window.app)\n" + parts.joined(separator: "\n")
    }
}
