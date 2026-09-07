import Foundation

/// One server-sent event: its type, and the data lines joined.
public struct ServerSentEvent: Sendable, Hashable {
    public let type: String?
    public let data: String

    public init(type: String?, data: String) {
        self.type = type
        self.data = data
    }
}

/// Turns a stream of lines into events. Separated from the network so the
/// recorded fixtures exercise exactly the code the wire does.
public struct ServerSentEventParser: Sendable {
    private var type: String?
    private var data: [String] = []

    public init() {}

    /// Feeds one line. Returns an event when the line completes one. A
    /// trailing carriage return is dropped: the wire ends lines with CRLF and
    /// the blank line that separates events arrives as a lone return.
    public mutating func consume(_ rawLine: String) -> ServerSentEvent? {
        var line = rawLine
        if line.hasSuffix("\r") { line.removeLast() }
        if line.isEmpty {
            guard !data.isEmpty || type != nil else { return nil }
            let event = ServerSentEvent(type: type, data: data.joined(separator: "\n"))
            type = nil
            data = []
            return event
        }
        if line.hasPrefix(":") { return nil }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let field = String(line[line.startIndex..<colon])
        var value = String(line[line.index(after: colon)...])
        if value.hasPrefix(" ") { value.removeFirst() }
        switch field {
        case "event": type = value
        case "data": data.append(value)
        default: break
        }
        return nil
    }

    /// Flushes an event left unterminated at the end of a stream.
    public mutating func finish() -> ServerSentEvent? { consume("") }
}

/// Every event of one server-sent-events response, over `URLSession`.
///
/// Lines are split from the bytes here rather than through `AsyncLineSequence`,
/// which drops the empty line that separates one event from the next.
func serverSentEvents(
    for request: URLRequest,
    session: URLSession
) -> AsyncThrowingStream<ServerSentEvent, any Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                let (bytes, response) = try await session.bytes(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    var body: [UInt8] = []
                    for try await byte in bytes { body.append(byte) }
                    throw ProviderError.http(
                        status: http.statusCode,
                        body: String(decoding: body, as: UTF8.self)
                    )
                }
                var parser = ServerSentEventParser()
                var line: [UInt8] = []
                for try await byte in bytes {
                    guard byte == UInt8(ascii: "\n") else {
                        line.append(byte)
                        continue
                    }
                    let text = String(decoding: line, as: UTF8.self)
                    line.removeAll(keepingCapacity: true)
                    if let event = parser.consume(text) { continuation.yield(event) }
                }
                if !line.isEmpty,
                   let event = parser.consume(String(decoding: line, as: UTF8.self)) {
                    continuation.yield(event)
                }
                if let event = parser.finish() { continuation.yield(event) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
