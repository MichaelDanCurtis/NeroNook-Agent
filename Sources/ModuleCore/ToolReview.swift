import Foundation

public struct AgentToolReview: Codable, Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let consequence: String
    public init(id: UUID = UUID(), title: String, detail: String, consequence: String) {
        self.id = id; self.title = String(title.prefix(200)); self.detail = detail; self.consequence = String(consequence.prefix(500))
    }
}

/// A concrete one-shot review. The model never receives a method to resolve it.
@MainActor public final class AgentToolReviews {
    public private(set) var pending: [AgentToolReview] = []
    private var continuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var timers: [UUID: Task<Void, Never>] = [:]
    private var epoch = UUID()
    public var changed: (() -> Void)?
    public init() {}
    public func request(_ review: AgentToolReview) async throws {
        try Task.checkCancellation()
        guard pending.count < 4, continuations[review.id] == nil else { throw AgentError.message("Too many pending tool reviews.") }
        guard review.detail.utf8.count <= 131072 else { throw AgentError.message("This request is too large to review completely. Ask for a smaller operation. Nothing was run.") }
        let token = epoch
        let allowed = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending.append(review); continuations[review.id] = continuation; changed?()
                timers[review.id] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(120)); if !Task.isCancelled { self?.resolve(review.id, allow: false) }
                }
            }
        } onCancel: { Task { @MainActor in self.resolve(review.id, allow: false) } }
        guard allowed, token == epoch, !Task.isCancelled else { throw AgentError.message("You declined or stopped this tool request. Nothing was run.") }
    }
    public func resolve(_ id: UUID, allow: Bool) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        timers.removeValue(forKey: id)?.cancel()
        pending.removeAll { $0.id == id }; changed?(); continuation.resume(returning: allow)
    }
    public func cancel() { epoch = UUID(); for id in Array(continuations.keys) { resolve(id, allow: false) } }
}
