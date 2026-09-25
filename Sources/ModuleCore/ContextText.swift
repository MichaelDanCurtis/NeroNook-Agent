import Foundation

public enum ContextText {
    /// Preserve valid Unicode and explicitly mark omissions within the context byte budget.
    public static func bounded(_ text: String) -> String {
        guard text.utf8.count > 8192 else { return text }
        let suffix = "\n[Preview truncated to the context limit.]"
        var result = "", bytes = 0
        for character in text {
            let size = String(character).utf8.count
            guard bytes + size + suffix.utf8.count <= 8192 else { break }
            result.append(character); bytes += size
        }
        return result + suffix
    }
}
