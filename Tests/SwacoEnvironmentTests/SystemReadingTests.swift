import Foundation
import Testing
import SwacoCore
import SwacoEnvironment

@Suite struct ReadingTheSystem {
    /// The system is asked, and whatever it says is a usable answer. What it
    /// says differs between a Mac, a simulator and a phone, so the check is
    /// that an answer comes back rather than which one.
    @Test @MainActor func thesystemIsAskedAndAnswers() {
        let context = WhereWeAreRunning.now()
        switch context.placement {
        case .foreground, .background, .appExtension: break
        }
        // Nothing said is not the same as plenty, so nil stays nil.
        if let remaining = context.remainingTime {
            #expect(remaining >= 0)
        }
    }

    /// What only the caller can know is passed in, and it wins.
    @Test @MainActor func whatOnlyTheCallerKnowsIsTaken() {
        let context = WhereWeAreRunning.now(remainingTime: 7)
        #expect(context.remainingTime == 7)
    }
}
