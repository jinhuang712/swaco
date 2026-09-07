import Foundation

/// Where bytes actually are. A part may carry them, point at them, or name a
/// place to fetch them from.
///
/// Pointing is what keeps a long history cheap: a conversation with fifty
/// photographs in it holds fifty references, and the bytes are read when a
/// request is built and let go when it is sent.
public enum ContentSource: Sendable, Hashable, Codable {
    /// The bytes themselves, with their kind as a MIME type.
    case bytes(Data, type: String)
    /// A reference into a `ContentStore`, resolved when a request is built.
    case reference(ContentReference)
    /// Somewhere the vendor can reach on its own.
    case url(URL, type: String)

    public var type: String {
        switch self {
        case .bytes(_, let type): type
        case .reference(let reference): reference.type
        case .url(_, let type): type
        }
    }
}

/// Where a claim in a reply came from, when a model says.
public struct Citation: Sendable, Hashable, Codable {
    public let title: String?
    public let url: URL?
    /// The part of the reply this citation is for, as a range of characters.
    public let range: Range<Int>?

    public init(title: String? = nil, url: URL? = nil, range: Range<Int>? = nil) {
        self.title = title
        self.url = url
        self.range = range
    }
}

/// One piece of what a message is made of.
///
/// Everything a model can be given or can produce is one of these. New kinds
/// arrive by addition, and a part a model has not declared it can take is
/// recorded as a mismatch rather than dropped or trimmed.
public enum ContentPart: Sendable, Hashable, Codable {
    case text(String)
    case image(ContentSource)
    /// What the model thought on the way, where the vendor gives it to us.
    case reasoning(String)
    /// A tool the vendor ran itself, such as its own web search.
    case providerTool(name: String, input: JSONValue)
    case providerToolResult(name: String, output: JSONValue)
    case citation(Citation)

    /// The words in this part, if it has any.
    public var text: String? {
        if case .text(let text) = self { return text }
        return nil
    }

    /// What this part needs the model to be able to take.
    public var needs: Capability? {
        switch self {
        case .image: .vision
        case .reasoning: .reasoning
        case .text, .citation, .providerTool, .providerToolResult: nil
        }
    }
}

public extension Array where Element == ContentPart {
    /// The words, joined. What most readers want and every log line shows.
    var text: String {
        compactMap(\.text).joined()
    }

    /// Adjacent runs of words become one part, and empty ones go.
    ///
    /// Parts are assembled from several places at once: what arrived, what
    /// says where it came from, what a model streamed in pieces. Without this
    /// two messages that say the same thing would not be the same message.
    var normalised: [ContentPart] {
        reduce(into: []) { parts, part in
            if case .text(let text) = part {
                guard !text.isEmpty else { return }
                if case .text(let sofar) = parts.last {
                    parts[parts.count - 1] = .text(sofar + text)
                } else {
                    parts.append(part)
                }
            } else {
                parts.append(part)
            }
        }
    }
}
