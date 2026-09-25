import Foundation
import NookPluginSDK

public enum ContextSharing {
    /// Local-only automation observations cannot be fetched through a second tool route.
    public static func plannerCatalog(_ catalog: [PluginCatalogEntry], sources: [ContextSource], paused: Bool) -> [PluginCatalogEntry] {
        guard !paused else { return [] }
        let shareRuns = sources.contains { $0.kind == .nook && $0.enabled && $0.allowCloud }
        return catalog.filter { $0.address.plugin != "local.neronook.workspace" || $0.address.name != "read_runs" || shareRuns }
    }
}
