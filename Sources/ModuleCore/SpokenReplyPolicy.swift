import Foundation

/// A per-spoken-turn override on the same model/account. An unknown model or
/// absent capability never guesses an effort or changes a provider.
public enum SpokenReplyPolicy {
    public static func effort(model: String, catalog: [String: Any], quick: Bool) -> String? {
        guard quick, !model.isEmpty, let entries=catalog["data"] as? [[String:Any]], entries.count<=256,
              let entry=entries.first(where:{($0["model"] as? String ?? $0["id"] as? String)==model}),
              let efforts=entry["supportedReasoningEfforts"] as? [[String:Any]], efforts.count<=16,
              efforts.contains(where:{$0["reasoningEffort"] as? String == "low"}) else{return nil}
        return "low"
    }
    public static let instructions = "For this spoken turn, start with the useful answer. Keep ordinary replies to one or two short conversational sentences. Give more detail when the user asks for it or when safe, accurate guidance needs it. Do not add acknowledgements, filler, or a description of your plan before answering. Keep every tool permission and review requirement."
}
