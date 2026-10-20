// Frozen pre-latency queue for the authored CLI comparison only. Not linked into ModuleApp.
import ModuleCore
import Foundation

/// Speak stable sentence prefixes as they arrive, without replay on a rewrite.
public struct BaselineSpeechQueue {
    private var revision = ""
    private var pending = ""
    public private(set) var finished = false
    public init() {}
    public mutating func append(_ text: String, final: Bool) throws {
        guard text.utf8.count <= 32000, text.hasPrefix(revision) else { throw AgentError.message("The spoken reply changed; playback stopped to avoid repeating it.") }
        pending += text.dropFirst(revision.count); revision=text;finished=final
    }
    public mutating func next() -> String? {
        guard !pending.isEmpty else{return nil}
        var end:String.Index?
        var wordBoundary: String.Index?
        for i in pending.indices {
            let c=pending[i]
            if c.isWhitespace, i > pending.startIndex { wordBoundary = i }
            if ".!?\n".contains(c) {
                let n=pending.index(after:i)
                // A token delta can stop after the decimal point in "3.14".
                // Only final output proves that end-of-buffer is a boundary.
                let boundary = n == pending.endIndex ? finished : pending[n].isWhitespace
                if boundary && (c != "." || !isAbbreviation(endingAt: i)) { end=n;break }
            }
            if pending.distance(from:pending.startIndex,to:i)>=350{end=wordBoundary ?? i;break}
        }
        if end==nil,finished{end=pending.endIndex}
        guard let end else{return nil};let value=String(pending[..<end]);pending.removeSubrange(..<end)
        let spoken=value.replacingOccurrences(of:"```",with:"").replacingOccurrences(of:"**",with:"").replacingOccurrences(of:"`",with:"").trimmingCharacters(in:.whitespacesAndNewlines)
        return spoken.isEmpty ? next():spoken
    }
    private func isAbbreviation(endingAt index: String.Index) -> Bool {
        let token = pending[..<pending.index(after: index)].split(whereSeparator: \.isWhitespace).last.map(String.init)?.lowercased() ?? ""
        let common: Set<String> = ["mr.","mrs.","ms.","dr.","prof.","sr.","jr.","st.","vs.","etc.","e.g.","i.e.","inc.","ltd.","no.","fig.","a.m.","p.m."]
        if common.contains(token) { return true }
        let initials = token.split(separator: ".")
        return !initials.isEmpty && initials.allSatisfy { $0.count == 1 && $0.first?.isLetter == true }
    }
    public var drained: Bool { finished && pending.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }
}
