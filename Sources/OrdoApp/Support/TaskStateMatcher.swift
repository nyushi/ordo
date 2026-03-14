import Foundation

struct TaskStateMatch {
    let range: NSRange
    let state: String
    let index: Int
}

struct TaskStateMatcher {
    private(set) var states: [String]
    private let regex: NSRegularExpression?

    init(states: [String]) {
        self.states = states
        regex = TaskStateMatcher.buildRegex(for: states)
    }

    func match(at characterIndex: Int, in string: NSString) -> TaskStateMatch? {
        let lineRange = string.lineRange(for: NSRange(location: characterIndex, length: 0))
        return match(inLineRange: lineRange, string: string)
    }

    func match(inLineRange lineRange: NSRange, string: NSString) -> TaskStateMatch? {
        guard let regex else { return nil }
        let lineString = string.substring(with: lineRange) as NSString
        let matchRange = NSRange(location: 0, length: lineString.length)
        guard
            let match = regex.firstMatch(in: lineString as String, options: [], range: matchRange)
        else { return nil }

        let keywordRange = match.range(at: 1)
        guard keywordRange.location != NSNotFound else { return nil }
        let globalRange = NSRange(location: lineRange.location + keywordRange.location, length: keywordRange.length)
        let keyword = lineString.substring(with: keywordRange)
        let normalized = keyword.uppercased()
        guard let index = states.firstIndex(where: { $0.uppercased() == normalized }) else { return nil }
        return TaskStateMatch(range: globalRange, state: states[index], index: index)
    }

    private static func buildRegex(for states: [String]) -> NSRegularExpression? {
        let sanitized = states.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !sanitized.isEmpty else { return nil }
        let escaped = sanitized.map { NSRegularExpression.escapedPattern(for: $0) }
        let joined = escaped.joined(separator: "|")
        let pattern = #"^\s*(?:[*-]+\s+)?"# + "(" + joined + ")" + #"(?=\s|$)"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }
}
