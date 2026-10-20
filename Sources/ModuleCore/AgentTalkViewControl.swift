import NookPluginSDK

/// The exact existing custom-view event definition, shared by the real view and
/// the JavaScript-to-SDK validation test. This is not a registered shared action.
public enum AgentTalkViewControl {
    public static let definition = PluginViewEventDefinition("talk", input: .init([
        .init("command", .string), .init("value", .string, required: false), .init("context", .boolean, required: false)
    ]))
    public static func expression(_ values: [String: PluginValue]) throws -> Bool {
        try definition.input.validate(values)
        guard values["command"] == .string("expression"), case .string(let value) = values["value"], ["true", "false"].contains(value) else {
            throw AgentError.message("Choose whether expressive delivery is enabled.")
        }
        return value == "true"
    }
}
