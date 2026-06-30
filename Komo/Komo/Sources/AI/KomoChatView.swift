import SwiftUI

// MARK: - Komo Chat View

/// Full-screen chat interface where the user can talk to their Komo creature.
/// Powered by Apple Foundation Models (iOS 26+) with health data context.
struct KomoChatView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var chatEngine = KomoChatEngine()
    @State private var inputText: String = ""
    @State private var scrollProxy: ScrollViewProxy? = nil
    @EnvironmentObject var engine: HealthAvatarEngine

    // Suggested quick questions
    let quickQuestions = [
        "Pourquoi je suis fatigué ?",
        "Est-ce que j'ai bien dormi ?",
        "Quel est mon niveau de stress ?",
        "Est-ce que je devrais faire du sport ?",
        "Comment va mon cœur ?"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(hex: "0A0E21"), Color(hex: "1A1A2E")],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {

                    // Chat messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {

                                // Welcome bubble if no messages
                                if chatEngine.messages.isEmpty {
                                    WelcomeBubble()
                                        .padding(.top, 20)

                                    // Quick question chips
                                    QuickQuestionsView(questions: quickQuestions) { q in
                                        Task { await chatEngine.send(q) }
                                    }
                                }

                                // Message bubbles
                                ForEach(chatEngine.messages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }

                                // Typing indicator
                                if chatEngine.isTyping && chatEngine.streamingText.isEmpty {
                                    TypingIndicator()
                                        .id("typing")
                                }

                                // Bottom anchor
                                Color.clear.frame(height: 8).id("bottom")
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }
                        .onAppear { scrollProxy = proxy }
                        .onChange(of: chatEngine.messages.count) { _, _ in
                            withAnimation { proxy.scrollTo("bottom") }
                        }
                        .onChange(of: chatEngine.streamingText) { _, _ in
                            proxy.scrollTo("bottom")
                        }
                    }

                    // Input bar
                    ChatInputBar(text: $inputText, isTyping: chatEngine.isTyping) {
                        let msg = inputText.trimmingCharacters(in: .whitespaces)
                        guard !msg.isEmpty else { return }
                        inputText = ""
                        Task { await chatEngine.send(msg) }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text("K")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                        Text("Komo")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Circle()
                            .fill(.green)
                            .frame(width: 7, height: 7)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fermer") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { chatEngine.clearChat() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .accessibilityLabel("Clear conversation")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task {
            // Setup session with current health data
            if let analysis = engine.dayAnalysis {
                await chatEngine.setupSession(with: analysis)
            }
        }
    }
}

// MARK: - Welcome Bubble

private struct WelcomeBubble: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            KomoAvatar()
            VStack(alignment: .leading, spacing: 6) {
                Text("Bonjour ! Je suis Komo 👋")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Je connais tes données de santé d'aujourd'hui. Pose-moi n'importe quelle question — sommeil, stress, activité, récupération.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                    )
            )
            Spacer(minLength: 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Komo says: Bonjour ! Je suis Komo. Je connais tes données de santé d'aujourd'hui.")
    }
}

// MARK: - Quick Questions

private struct QuickQuestionsView: View {
    let questions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(questions, id: \.self) { q in
                    Button(action: { onSelect(q) }) {
                        Text(q)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(Capsule().stroke(Color.purple.opacity(0.4), lineWidth: 1))
                            )
                    }
                    .accessibilityLabel("Quick question: \(q)")
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: KomoChatMessage

    var isKomo: Bool { message.role == .komo }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isKomo {
                KomoAvatar()
                bubbleContent
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                            )
                    )
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubbleContent
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.7), Color.indigo.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isKomo ? "Komo: \(message.text)" : "You: \(message.text)")
    }

    private var bubbleContent: some View {
        Text(message.text.isEmpty ? "..." : message.text)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var dot1 = false
    @State private var dot2 = false
    @State private var dot3 = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            KomoAvatar()
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .scaleEffect(dotScale(i))
                        .animation(
                            .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                            value: dot1
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
            )
            Spacer(minLength: 40)
        }
        .onAppear { dot1 = true }
        .accessibilityLabel("Komo is typing")
    }

    func dotScale(_ index: Int) -> CGFloat {
        index == 0 ? (dot1 ? 1.2 : 0.8) :
        index == 1 ? (dot2 ? 1.2 : 0.8) : (dot3 ? 1.2 : 0.8)
    }
}

// MARK: - Komo Avatar (small)

private struct KomoAvatar: View {
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.purple.opacity(0.8), .indigo.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 28, height: 28)
            .overlay(
                Text("K")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Chat Input Bar

private struct ChatInputBar: View {
    @Binding var text: String
    let isTyping: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Demande à Komo...", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .onSubmit { onSend() }
                .accessibilityLabel("Message to Komo")

            Button(action: onSend) {
                Image(systemName: isTyping ? "ellipsis" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        text.trimmingCharacters(in: .whitespaces).isEmpty || isTyping
                            ? .white.opacity(0.3)
                            : .purple
                    )
                    .animation(.easeInOut(duration: 0.2), value: isTyping)
            }
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isTyping)
            .accessibilityLabel(isTyping ? "Komo is responding" : "Send message")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(hex: "0A0E21")
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }
}

private extension Color {
    init(hex: String) {
        let cleanedHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var rgbValue: UInt64 = 0
        Scanner(string: cleanedHex).scanHexInt64(&rgbValue)

        let red = Double((rgbValue & 0xFF0000) >> 16) / 255
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255
        let blue = Double(rgbValue & 0x0000FF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}

#Preview {
    KomoChatView()
        .environmentObject(HealthAvatarEngine.shared)
}
