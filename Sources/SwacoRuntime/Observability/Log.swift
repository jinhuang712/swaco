import Foundation
import os
import Swaco

/// What swaco writes to the system log.
///
/// Structure is logged and content is not. That a turn started, that a tool
/// was called, that a call was refused: all of it. What a person said, what
/// the model replied, what a tool returned: none of it. A log a developer can
/// leave on is one that never carries anyone's words.
enum Log {
    static let subsystem = "dev.swaco"
    static let run = Logger(subsystem: subsystem, category: "run")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let signposts = OSSignposter(subsystem: subsystem, category: "run")
}
