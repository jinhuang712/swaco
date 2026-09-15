import Foundation
import Testing
import SwacoCore
import SwacoEnvironment

@Suite struct TheSourceVocabulary {
    /// The well-known sources write the same names the old closed list did,
    /// so logs written before the opening still read.
    @Test func wellKnownSourcesKeepTheirWireNames() throws {
        for source in [EventSource.person, .shortcut, .notification, .url,
                       .share, .system, .schedule, .sensor] as [EventSource] {
            let event = Event.arrived(source.inbound("hi"))
            let back = try JSONDecoder().decode(Event.self, from: try JSONEncoder().encode(event))
            #expect(back == event)
        }
        #expect(EventSource.person.identifier == "person")
        #expect(EventSource.share.identifier == "share")
    }

    /// An app's own source travels the same road: log, read back, unchanged.
    @Test func anAppDefinesItsOwnSources() throws {
        let selection: EventSource = "selection"
        let event = Event.arrived(selection.inbound("this"))
        let back = try JSONDecoder().decode(Event.self, from: try JSONEncoder().encode(event))
        #expect(back == event)
        guard case .arrived(let inbound) = back else {
            Issue.record("a log begins with what arrived")
            return
        }
        #expect(inbound.source == "selection")
    }
}
