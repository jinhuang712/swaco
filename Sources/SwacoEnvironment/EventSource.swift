import Foundation
import SwacoCore

/// Where an inbound event came from: an open vocabulary, not a closed list.
///
/// A person typing is one source among many, and none is assumed. The core
/// carries only the identifier string; this layer owns the words. Platform
/// layers provide the well-known ones, and an app defines its own for
/// whatever wakes its agent: a document change, a selection, a controller.
///
/// ```swift
/// InboundEvent(source: EventSource.share.identifier, content: parts)
/// // or, through the builder below:
/// EventSource.share.inbound("a photo")
/// ```
public struct EventSource: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    /// The identifier the core carries and the log records. Stable on the
    /// wire: a log written with one of these reads back with it.
    public let identifier: String

    public init(_ identifier: String) {
        self.identifier = identifier
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// What a person typed. The one source with a helper on `InboundEvent` too.
    public static let person = EventSource("person")
    public static let shortcut = EventSource("shortcut")
    public static let notification = EventSource("notification")
    public static let url = EventSource("url")
    public static let share = EventSource("share")
    public static let system = EventSource("system")
    public static let schedule = EventSource("schedule")
    public static let sensor = EventSource("sensor")

    /// Builds the arrival this source brings, from words.
    public func inbound(_ text: String) -> InboundEvent {
        InboundEvent(source: identifier, text: text)
    }

    /// Builds the arrival this source brings, from parts.
    public func inbound(_ content: [ContentPart]) -> InboundEvent {
        InboundEvent(source: identifier, content: content)
    }
}
