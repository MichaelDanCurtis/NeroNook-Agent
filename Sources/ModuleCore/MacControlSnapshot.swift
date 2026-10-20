import Foundation
import CryptoKit

/// The reviewed control and its path to the selected window. Values are compared
/// by digest so an ancestor's document text is not duplicated in the snapshot.
public struct MacControlSnapshot: Equatable {
    public struct Node: Equatable {
        public let role: String
        public let subrole: String?
        public let identifier: String?
        public let title: String?
        public let description: String?
        public let valueDigest: Data?
        public init(role: String, subrole: String? = nil, identifier: String? = nil, title: String? = nil, description: String? = nil, value: String? = nil) {
            self.role = role; self.subrole = subrole; self.identifier = identifier
            self.title = title; self.description = description
            valueDigest = value.map { Data(SHA256.hash(data: Data($0.utf8))) }
        }
        public var label: String { title.flatMap { $0.isEmpty ? nil : $0 } ?? description ?? "" }
    }
    public let path: [Node]
    public init(path: [Node]) { self.path = path }
    public func validate(current: MacControlSnapshot, sameElements: Bool) throws {
        guard sameElements, !path.isEmpty, path.count <= 32, path == current.path else {
            throw AgentError.message("The control or its window context changed. Refresh the window and review a new request. Nothing was run.")
        }
    }
    public var reviewPath: String { path.map { $0.role + ($0.label.isEmpty ? "" : " · " + $0.label) }.joined(separator: " → ") }
}
