import Foundation
import Swaco

/// Records what a real model said, so nothing has to ask it again.
///
/// Run once against a vendor, keep the exchange, replay it from then on.
/// Development, previews and tests then need no key and no network, and a
/// test that would have been flaky is a file instead.
///
/// One JSON object per line: the turn it belongs to, and the event. Plain
/// enough to read, and to trim by hand when a recording is longer than the
/// point it makes.
public struct Recording: Provider {
    private let wrapped: any Provider
    private let file: URL
    private let turns = Turns()

    /// - Parameters:
    ///   - provider: the real one, asked once.
    ///   - file: where the exchange is kept. Its directory is created.
    public init(_ provider: any Provider, to file: URL) {
        self.wrapped = provider
        self.file = file
    }

    public var capabilities: ModelCapabilities { wrapped.capabilities }
    public var availability: ModelAvailability { wrapped.availability }

    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<StreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // The number is taken when the first event arrives, not when
                // the request goes out, so an attempt a vendor turned away
                // leaves no empty turn in the recording.
                var turn: Int?
                do {
                    for try await event in wrapped.stream(request) {
                        let number: Int
                        if let already = turn {
                            number = already
                        } else {
                            number = await turns.next()
                            turn = number
                        }
                        try await write(event, turn: number)
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func write(_ event: StreamEvent, turn: Int) async throws {
        let line = try JSONEncoder().encode(Line(turn: turn, event: event))
        try await turns.append(line + Data([0x0A]), to: file)
    }

    struct Line: Codable {
        let turn: Int
        let event: StreamEvent
    }

    private actor Turns {
        private var count = 0
        private var started = false

        func next() -> Int {
            count += 1
            return count
        }

        func append(_ data: Data, to file: URL) throws {
            if !started {
                try FileManager.default.createDirectory(
                    at: file.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try Data().write(to: file)
                started = true
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        }
    }
}

public extension ScriptedProvider {
    /// A provider that plays back what was recorded, turn by turn.
    ///
    /// The same replayable mock every test uses, fed from a file instead of a
    /// literal. A bug report that carries a recording is a bug anyone can
    /// reproduce without an account.
    static func replaying(_ file: URL) throws -> ScriptedProvider {
        let text = try String(contentsOf: file, encoding: .utf8)
        let decoder = JSONDecoder()
        var byTurn: [Int: [StreamEvent]] = [:]
        for line in text.split(separator: "\n") where !line.isEmpty {
            let recorded = try decoder.decode(Recording.Line.self, from: Data(line.utf8))
            byTurn[recorded.turn, default: []].append(recorded.event)
        }
        return ScriptedProvider(turns: byTurn.keys.sorted().map { byTurn[$0] ?? [] })
    }
}
