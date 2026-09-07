import Foundation
import Swaco
#if canImport(UIKit)
import UIKit
#endif

/// Reads from the system what an extension is told about where it is running.
///
/// The type is the core's, because an extension must be able to read it
/// without knowing a platform. Filling it in is the runtime's, because only
/// something that knows the platform can answer: is this the app or a share
/// sheet, is anyone looking, how long has this process got.
///
/// Every answer here is a fact, and none of it decides anything. A budget that
/// stops early and a handover that gives time back are both the app's rules
/// written over these facts.
public enum WhereWeAreRunning {
    /// What the system says now.
    ///
    /// - Parameter remainingTime: how long this process expects to keep
    ///   running. The system tells an app extension and a background task in
    ///   ways only they can ask, so whoever knows passes it in; nil means
    ///   nobody said, which is not the same as plenty.
    public static func now(remainingTime: TimeInterval? = nil) -> ExecutionContext {
        ExecutionContext(
            placement: placement,
            remainingTime: remainingTime ?? backgroundTimeRemaining,
            personIsPresent: personIsPresent
        )
    }

    /// Whether this process is the app, and whether anyone is looking at it.
    public static var placement: ExecutionContext.Placement {
        guard !isAppExtension else { return .appExtension }
        #if canImport(UIKit)
        return MainActor.assumeIsolated {
            switch UIApplication.shared.applicationState {
            case .active, .inactive: .foreground
            case .background: .background
            @unknown default: .foreground
            }
        }
        #else
        return .foreground
        #endif
    }

    /// A share sheet, a widget, an intent: a separate process with its own,
    /// much shorter, life. Told by where the bundle sits, which is the only
    /// answer that works before anything else has been set up.
    public static var isAppExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    /// Whether anyone is there to answer. A run woken by a schedule has
    /// nobody, and a tool that asks a question should be told so rather than
    /// wait for someone who is not coming.
    public static var personIsPresent: Bool {
        guard !isAppExtension else { return true }
        #if canImport(UIKit)
        return MainActor.assumeIsolated {
            UIApplication.shared.applicationState == .active
        }
        #else
        return true
        #endif
    }

    /// What the system says is left, where it says anything.
    private static var backgroundTimeRemaining: TimeInterval? {
        #if canImport(UIKit)
        return MainActor.assumeIsolated {
            let left = UIApplication.shared.backgroundTimeRemaining
            // The system says "as long as you like" with a number no clock
            // means, so it is reported as nothing said.
            return left == .greatestFiniteMagnitude || left > 60 * 60 ? nil : left
        }
        #else
        return nil
        #endif
    }
}

public extension Agent {
    /// The same agent, told where it is running by the system rather than by
    /// a guess. What an app calls when it starts a run.
    ///
    /// - Parameter remainingTime: what only the caller can know, such as the
    ///   time an app extension or a background task was given.
    @MainActor
    func runningHere(remainingTime: TimeInterval? = nil) -> Agent {
        running(in: WhereWeAreRunning.now(remainingTime: remainingTime))
    }
}
