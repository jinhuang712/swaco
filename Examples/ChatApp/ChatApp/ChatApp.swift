import SwiftUI

/// The sample app: a chatbot on a phone, built on swaco.
///
/// It exists to show one-step adoption and to be the app that drives what
/// swaco builds next. Everything here is the app's own judgement: the screens,
/// the model it talks to, where it keeps its key, what it says. Swaco makes
/// none of these decisions.
@main
struct ChatApp: App {
    @State private var chat = Chat()

    var body: some Scene {
        WindowGroup {
            ChatView(chat: chat)
                .task { await chat.begin() }
        }
    }
}
