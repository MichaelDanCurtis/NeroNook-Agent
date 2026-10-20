import Foundation

/// Only models explicitly offered by this plugin's authenticated runtime.
public struct AgentModelChoice: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isDefault: Bool
    public static func parse(_ catalog: [String: Any]) throws -> [Self] {
        guard let entries = catalog["data"] as? [[String: Any]], entries.count <= 256 else {
            throw AgentError.message("The model list could not be read. Refresh it before choosing a model.")
        }
        var seen = Set<String>(), choices: [Self] = []
        for entry in entries where entry["hidden"] as? Bool != true {
            if let modalities = entry["inputModalities"] as? [String], !modalities.contains("text") { continue }
            guard let id = entry["model"] as? String, !id.isEmpty, id.utf8.count <= 160,
                  !id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  seen.insert(id).inserted else { continue }
            let name = entry["displayName"] as? String ?? id
            choices.append(Self(id: id, name: String(name.prefix(96)), isDefault: entry["isDefault"] as? Bool == true))
        }
        return choices
    }
    public static func page(_ choices: [Self], selected: String, index: Int) -> [Self] {
        let page = min(max(0,index), max(0,(choices.count-1)/12))
        var result = Array(choices.dropFirst(page*12).prefix(12))
        if !selected.isEmpty, !result.contains(where:{$0.id == selected}), let current = choices.first(where:{$0.id == selected}) { result.insert(current,at:0) }
        return result
    }
    public static func validate(_ selected: String, choices: [Self]) throws {
        guard selected.isEmpty || choices.contains(where: { $0.id == selected }) else {
            throw AgentError.message("Your selected agent model is unavailable. Choose another model or Account default; nothing was sent.")
        }
    }
}
