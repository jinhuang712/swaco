import XCTest

/// The app, driven the way a person drives it: by tapping.
///
/// It runs on a conversation this app once had with a real model and kept, so
/// these are about the app and about swaco rather than about a model's mood,
/// and they need no key and no network.
final class ChatAppUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(freshly: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-recorded"]
        if freshly { app.launchArguments.append("-forget-everything") }
        app.launch()
        return app
    }

    private func say(_ text: String, in app: XCUIApplication) {
        let composer = app.textFields["Say something"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20), "the composer must be there")
        composer.tap()
        composer.typeText(text)
        app.buttons["Send"].tap()
    }

    /// The first option the model offered, which is what the person taps.
    private func firstOption(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Tropical beach'")
        ).firstMatch
    }

    private func text(containing fragment: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", fragment)
        ).firstMatch
    }

    /// A person types, the agent answers, and the agent asks something back.
    func testTheAgentAnswersAndThenAsks() {
        let app = launch()
        say("Book me somewhere warm in February.", in: app)

        XCTAssertTrue(text(containing: "warm getaway preferences", in: app)
            .waitForExistence(timeout: 20), "the agent must have replied")
        XCTAssertTrue(text(containing: "What kind of warm getaway", in: app)
            .waitForExistence(timeout: 20), "the question must be on screen")
        XCTAssertTrue(firstOption(in: app).waitForExistence(timeout: 20),
                      "the options must be there to tap")
    }

    /// Answering carries the conversation on, and the next thing the agent
    /// wants is approval, which is the same mechanism wearing another face.
    func testAnsweringCarriesTheConversationOn() {
        let app = launch()
        say("Book me somewhere warm in February.", in: app)
        XCTAssertTrue(firstOption(in: app).waitForExistence(timeout: 20))
        firstOption(in: app).tap()

        XCTAssertTrue(app.buttons["Allow"].waitForExistence(timeout: 20),
                      "the agent asks to book, and waits for a person again")
        app.buttons["Allow"].tap()
        XCTAssertTrue(text(containing: "booked you", in: app).waitForExistence(timeout: 20),
                      "and then it finishes what it was asked to do")
    }

    /// The exchange the phone makes hard: the agent asked, nobody answered,
    /// the process was killed, and the app came back. The question is still
    /// there, and answering it now reaches the loop that asked, a process ago.
    func testAQuestionSurvivesTheAppBeingKilled() {
        let app = launch()
        say("Book me somewhere warm in February.", in: app)
        XCTAssertTrue(firstOption(in: app).waitForExistence(timeout: 20),
                      "the agent must have asked before we kill it")

        app.terminate()
        XCTAssertEqual(app.state, .notRunning)

        let relaunched = launch(freshly: false)
        XCTAssertTrue(relaunched.staticTexts["Picking up where we left off."]
            .waitForExistence(timeout: 20), "the app must know it was interrupted")
        XCTAssertTrue(text(containing: "What kind of warm getaway", in: relaunched)
            .waitForExistence(timeout: 20),
                      "the question must be waiting where the person left it")

        firstOption(in: relaunched).tap()
        XCTAssertTrue(relaunched.buttons["Allow"].waitForExistence(timeout: 20),
                      "answering must reach the loop that asked, a process ago")
    }

    /// What was said before is still there after a plain relaunch.
    func testTheConversationIsStillThereAfterARelaunch() {
        let app = launch()
        say("Book me somewhere warm in February.", in: app)
        XCTAssertTrue(firstOption(in: app).waitForExistence(timeout: 20))

        app.terminate()
        let relaunched = launch(freshly: false)
        XCTAssertTrue(text(containing: "Book me somewhere warm", in: relaunched)
            .waitForExistence(timeout: 20), "what the person said must still be on screen")
        XCTAssertTrue(text(containing: "warm getaway preferences", in: relaunched)
            .waitForExistence(timeout: 20), "and what the agent said")
    }
}
