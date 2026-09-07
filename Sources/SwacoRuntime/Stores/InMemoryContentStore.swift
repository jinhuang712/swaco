import Foundation
import Swaco

/// A `ContentStore` that keeps bytes for as long as the process lives.
public actor InMemoryContentStore: ContentStore {
    private var bytes: [String: Data] = [:]

    public init() {}

    public func store(_ data: Data, type: String) async throws -> ContentReference {
        let reference = ContentReference(identifier: UUID().uuidString, type: type)
        bytes[reference.identifier] = data
        return reference
    }

    public func load(_ reference: ContentReference) async throws -> Data {
        guard let data = bytes[reference.identifier] else {
            throw StoreError.noSuchContent(reference)
        }
        return data
    }

    public func remove(_ reference: ContentReference) async throws {
        bytes[reference.identifier] = nil
    }
}

/// A `ContentStore` of one file per reference.
public actor FileContentStore: ContentStore {
    /// Where this store keeps its files.
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func store(_ data: Data, type: String) async throws -> ContentReference {
        let reference = ContentReference(identifier: UUID().uuidString, type: type)
        try data.write(to: file(for: reference), options: .atomic)
        return reference
    }

    public func load(_ reference: ContentReference) async throws -> Data {
        guard let data = try? Data(contentsOf: file(for: reference)) else {
            throw StoreError.noSuchContent(reference)
        }
        return data
    }

    public func remove(_ reference: ContentReference) async throws {
        try? FileManager.default.removeItem(at: file(for: reference))
    }

    private func file(for reference: ContentReference) -> URL {
        directory.appending(path: reference.identifier)
    }
}
