import Foundation

public enum WorkspaceInventory {
    public static func observe(_ bookmark: Data) throws -> String {
        var stale = false
        let root = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else { throw AgentError.message("Choose this workspace again to renew its folder access.") }
        let access = root.startAccessingSecurityScopedResource(); defer { if access { root.stopAccessingSecurityScopedResource() } }
        let info = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw AgentError.message("The selected workspace is unavailable or became a link.") }
        // Inventory only, not recursive indexing or file contents. Symlinks and hidden files excluded.
        guard let urls = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants]) else { throw AgentError.message("The selected workspace could not be read.") }
        var rows: [(Date, String)] = []
        var examined = 0
        while let url = urls.nextObject() as? URL, examined < 200 {
            examined += 1
            let info = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .contentModificationDateKey, .isDirectoryKey])
            guard info.isSymbolicLink != true else { continue }
            let modified = info.contentModificationDate ?? .distantPast
            rows.append((modified, "\(String(url.lastPathComponent.prefix(120)))\(info.isDirectory == true ? "/" : "") · \(ISO8601DateFormatter().string(from: modified))"))
        }
        return "Workspace inventory · \(root.lastPathComponent)\nFile names and modification times only; up to 200 immediate entries, newest 24 shown.\n" + rows.sorted { $0.0 > $1.0 }.prefix(24).map(\.1).joined(separator: "\n")
    }
}
