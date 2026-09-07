import Foundation
import os
import Swaco

/// What a module needs from the app around it before it can work.
///
/// An App Group that was never added, a usage string that was never written:
/// these fail at the worst moment, in front of someone, long after the line of
/// code that needed them. A module says what it needs, and an app checks the
/// lot in one call.
public struct Requirement: Sendable, Hashable {
    /// Which module needs it.
    public let module: String
    /// What is needed, in the words the app will look for in its own project.
    public let what: String
    /// Why, so a failure explains itself.
    public let because: String
    /// Whether it is there. Checked now, not described.
    public let isMet: Bool

    public init(module: String, what: String, because: String, isMet: Bool) {
        self.module = module
        self.what = what
        self.because = because
        self.isMet = isMet
    }
}

/// Checking what the app was supposed to provide.
///
/// The check is a call the app makes, not something swaco arranges behind its
/// back: explicit over magic, even when magic would be tidier. One line at
/// launch, and in a debug build an unmet requirement stops the app there with
/// a message that names the module, the thing, and the reason.
public enum Deployment {
    /// How an App Group's container is found. The system, unless a test or an
    /// app says otherwise.
    public typealias Container = @Sendable (String) -> URL?

    /// The system's answer. On iOS a missing entitlement means nil; on macOS
    /// a path comes back either way, which is why this is a parameter rather
    /// than an assumption.
    public static let systemContainer: Container = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
    }

    /// Everything the linked modules need, met or not.
    public static func requirements(
        appGroup: String? = nil,
        container: Container = Deployment.systemContainer
    ) -> [Requirement] {
        var all: [Requirement] = []
        if let appGroup {
            all.append(Requirement(
                module: "SwacoRuntime",
                what: "the App Group \(appGroup)",
                because: "a store in an App Group container is how an app extension and the app share one log",
                isMet: container(appGroup) != nil
            ))
        }
        return all
    }

    /// Fails a debug build at launch when something is missing, and logs it in
    /// a release build rather than taking the app down in front of anyone.
    ///
    /// - Parameter appGroup: the App Group the app means to share a store
    ///   through, if it does.
    public static func check(
        appGroup: String? = nil,
        container: Container = Deployment.systemContainer
    ) {
        let unmet = requirements(appGroup: appGroup, container: container).filter { !$0.isMet }
        guard !unmet.isEmpty else { return }
        let complaint = unmet
            .map { "\($0.module) needs \($0.what), because \($0.because)." }
            .joined(separator: "\n")
        #if DEBUG
        // Early, loud, and with the fix in the message.
        preconditionFailure("swaco: something the app was to provide is missing.\n\(complaint)")
        #else
        Log.run.error("swaco: \(complaint, privacy: .public)")
        #endif
    }
}

public extension FileEventStore {
    /// A store in an App Group container, so an app extension and the app
    /// share one log.
    ///
    /// - Throws: when the App Group is not on this app, with a message that
    ///   says so rather than a file error further down.
    init(
        appGroup: String,
        subdirectory: String = "swaco",
        container: Deployment.Container = Deployment.systemContainer
    ) throws {
        guard let root = container(appGroup) else {
            throw StoreError.unreadable(
                "the App Group \(appGroup) is not on this app, so its container cannot be reached"
            )
        }
        try self.init(directory: root.appending(path: subdirectory))
    }
}
