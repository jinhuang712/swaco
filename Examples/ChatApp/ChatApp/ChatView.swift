import SwiftUI
import SwacoInteraction

struct ChatView: View {
    @Bindable var chat: Chat
    @State private var typing = ""
    @State private var settings = false
    @FocusState private var composing: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversation
                if let waiting = chat.waiting { question(waiting) }
                composer
            }
            .navigationTitle("swaco")
            .toolbar {
                Button("Model", systemImage: "gearshape") { settings = true }
            }
            .sheet(isPresented: $settings) { settingsSheet }
            .safeAreaInset(edge: .top) {
                if let notice = chat.notice {
                    Text(notice)
                        .font(.footnote)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.yellow.opacity(0.25))
                }
            }
        }
    }

    private var conversation: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(chat.turns) { turn in
                    HStack {
                        if turn.who == .agent { bubble(turn); Spacer(minLength: 40) }
                        else { Spacer(minLength: 40); bubble(turn) }
                    }
                }
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
    }

    private func bubble(_ turn: Chat.Turn) -> some View {
        Text(turn.text)
            .padding(10)
            .background(turn.who == .person ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
            .clipShape(.rect(cornerRadius: 14))
    }

    /// The agent has asked something. How that appears is entirely this app's
    /// business; swaco only guarantees the loop is still waiting.
    private func question(_ waiting: PendingRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch waiting.request {
            case .question(let question):
                Text(question.question).font(.headline)
                if let options = question.options, !options.isEmpty {
                    HStack {
                        ForEach(options, id: \.self) { option in
                            Button(option) { Task { await chat.answer(option) } }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            case .confirmation(let confirmation):
                Text(confirmation.action).font(.headline)
                if let detail = confirmation.detail { Text(detail).font(.footnote) }
                HStack {
                    Button("Allow") { Task { await chat.decide(granted: true) } }
                        .buttonStyle(.borderedProminent)
                    Button("Not now") { Task { await chat.decide(granted: false) } }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial)
    }

    private var composer: some View {
        HStack {
            TextField("Say something", text: $typing, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($composing)
                .onSubmit(send)
            Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                .labelStyle(.iconOnly)
                .font(.title2)
                .disabled(chat.running || typing.isEmpty)
        }
        .padding()
        .onAppear { composing = true }
    }

    private func send() {
        let said = typing
        typing = ""
        Task { await chat.send(said) }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Toggle("Use the on-device model", isOn: $chat.useOnDeviceModel)
                Section("Hosted model key") {
                    SecureField("Bearer token", text: $chat.hostedKey)
                    Text("A demo keeps this in user defaults. A real app would use the Keychain, which is the app's decision, not swaco's.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Model")
            .toolbar { Button("Done") { settings = false } }
        }
    }
}
