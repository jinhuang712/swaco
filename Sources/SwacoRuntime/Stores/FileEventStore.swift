import Foundation
import Swaco

/// An `EventStore` of one file per group, a JSON object per line, appended and
/// flushed before it returns. Plain enough to read in a bug report, and it
/// lives happily in an App Group container so an app extension and the app
/// share one log.
public actor FileEventStore: EventStore {
    /// Where this store keeps its files.
    public let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var counts: [GroupID: Int] = [:]

    /// - Parameter directory: created if it does not exist. In an App Group
    ///   container, the same directory serves every process that can reach it.
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @discardableResult
    public func append(_ events: [Event], to group: GroupID) async throws -> Int {
        guard !events.isEmpty else { return try count(of: group) - 1 }
        var lines = Data()
        for event in events {
            lines.append(try encoder.encode(event))
            lines.append(0x0A)
        }
        let url = file(for: group)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: lines)
            // Durable when append returns, not when the system feels like it.
            try handle.synchronize()
        } else {
            try lines.write(to: url, options: .atomic)
        }
        let position = try count(of: group) + events.count - 1
        counts[group] = position + 1
        return position
    }

    public func read(_ group: GroupID, after position: Int?) async throws -> [StoredEvent] {
        let url = file(for: group)
        guard let data = try? Data(contentsOf: url) else { return [] }
        var events: [StoredEvent] = []
        var index = 0
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            defer { index += 1 }
            if let position, index <= position { continue }
            do {
                events.append(StoredEvent(position: index, event: try decoder.decode(Event.self, from: line)))
            } catch {
                throw StoreError.unreadable("\(group.rawValue) line \(index + 1)")
            }
        }
        counts[group] = index
        return events
    }

    public func groups() async throws -> [GroupID] {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return contents
            .filter { $0.pathExtension == "log" }
            .map { GroupID(rawValue: $0.deletingPathExtension().lastPathComponent) }
    }

    private func count(of group: GroupID) throws -> Int {
        if let known = counts[group] { return known }
        let data = (try? Data(contentsOf: file(for: group))) ?? Data()
        let count = data.split(separator: 0x0A).filter { !$0.isEmpty }.count
        counts[group] = count
        return count
    }

    private func file(for group: GroupID) -> URL {
        directory.appending(path: "\(group.rawValue).log")
    }
}
