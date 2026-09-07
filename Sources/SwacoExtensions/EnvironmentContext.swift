import Foundation
import Swaco

/// Tells the model when and where it is: the time, the time zone, the locale
/// and the device.
///
/// One of the three shipped extensions, and here for the same reason as the
/// others: nearly every app needs it, and no product would answer it
/// differently. What it says is facts about the machine, never a judgement.
public struct EnvironmentContext: Extension {
    public let name = "environment"
    /// Read when the request is made, so a long conversation does not carry a
    /// stale clock. Replaceable, which is what makes it testable.
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let locale: Locale
    private let timeZone: TimeZone
    private let device: String

    public init(
        now: @Sendable @escaping () -> Date = { Date() },
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        device: String = Self.deviceName
    ) {
        self.now = now
        self.locale = locale
        self.timeZone = timeZone
        self.device = device
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        calendar.locale = locale
        self.calendar = calendar
    }

    public func beforeRequest(
        _ request: ModelRequest,
        in context: ExtensionContext
    ) async -> Decision<ModelRequest> {
        // Only ahead of the first turn: the model keeps what it was told.
        guard context.turn == 1 else { return .pass }
        var messages = request.messages
        messages.insert(.system(description), at: 0)
        return .rewrite(ModelRequest(messages: messages, tools: request.tools))
    }

    private var description: String {
        let moment = now().formatted(
            Date.FormatStyle(date: .complete, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
        )
        return """
            The current time is \(moment). The time zone is \(timeZone.identifier). \
            The locale is \(locale.identifier). The device is a \(device).
            """
    }

    #if canImport(UIKit)
    public static let deviceName = "iPhone"
    #else
    public static let deviceName = "Mac"
    #endif
}
