import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentHint = HintProvider.random()
    @State private var hintOpacity: Double = 0

    private let hintTimer = Timer.publish(every: 12, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Hint bar — always visible, centered
            Text(currentHint)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(Color(hex: "A78BFA").opacity(0.8))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 2)
                .opacity(hintOpacity)
                .onReceive(hintTimer) { _ in
                    withAnimation(.easeOut(duration: 0.4)) { hintOpacity = 0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        currentHint = HintProvider.random()
                        withAnimation(.easeIn(duration: 0.5)) { hintOpacity = 1 }
                    }
                }
                .onAppear {
                    withAnimation(.easeIn(duration: 0.6).delay(0.5)) { hintOpacity = 1 }
                }

            // Top: waveform with settings button
            ZStack(alignment: .topTrailing) {
                WaveformView(
                    state: appState.state,
                    level: appState.audioLevel
                )
                .frame(height: 32)
                .frame(maxWidth: .infinity)

                HStack(spacing: 3) {
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .font(.system(size: 7))
                        .foregroundColor(Color(hex: "6B6680").opacity(0.6))

                    Button(action: {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent")!)
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 8))
                            .foregroundColor(Color(hex: "6B6680"))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                }
                .offset(x: -2, y: 2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Bottom: controls row
            HStack(spacing: 8) {
                // Status text / live transcript
                Group {
                    if appState.state == .listening {
                        Text(appState.liveTranscript.isEmpty ? "Listening..." : lastWords(appState.liveTranscript, count: 5))
                            .foregroundColor(.white.opacity(0.6))
                    } else if appState.state == .speaking {
                        Text("Claude Speaking...")
                            .foregroundColor(Color(hex: "A78BFA"))
                    } else if appState.state == .processing {
                        Text("Sending...")
                            .foregroundColor(Color(hex: "F59E0B"))
                    } else {
                        Text(appState.statusText)
                            .foregroundColor(Color(hex: "6B6680"))
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Reset button — clears transcript (only visible when listening)
                if appState.state == .listening {
                    Button(action: {
                        appState.cancelListening()
                        appState.startListening()
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: "6B6680"))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                }

                // Mute button — stops speaking and cancels listening
                Button(action: {
                    if appState.isMuted {
                        appState.isMuted = false
                        appState.startListening()
                    } else {
                        if appState.state == .speaking {
                            VoiceManager.shared.stopSpeaking()
                            appState.state = .idle
                            appState.audioLevel = 0.0
                            appState.statusText = "Ready"
                        }
                        if appState.state == .listening {
                            appState.cancelListening()
                        }
                        appState.isMuted = true
                    }
                }) {
                    Image(systemName: appState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10))
                        .foregroundColor(
                            appState.isMuted ? Color(hex: "EF4444") : Color(hex: "6B6680")
                        )
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)

                // Speak / Listening button
                Button(action: { appState.toggleRecording() }) {
                    Text(buttonLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(buttonTextColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(buttonBgColor)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .padding(.top, 4)
        }
        .frame(width: 300, height: 88)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(hex: "1C1A2E"))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var buttonLabel: String {
        switch appState.state {
        case .idle: return "Speak Now"
        case .listening: return "Say 'Send It'"
        case .speaking: return "Stop"
        case .processing: return "Sending"
        }
    }

    private func lastWords(_ text: String, count: Int) -> String {
        let words = text.split(separator: " ")
        if words.count <= count { return text }
        return words.suffix(count).joined(separator: " ")
    }

    private var buttonTextColor: Color {
        switch appState.state {
        case .listening: return .white
        case .speaking: return .white
        default: return .white
        }
    }

    private var buttonBgColor: Color {
        switch appState.state {
        case .idle: return Color(hex: "7C5BF6")
        case .listening: return Color(hex: "EF4444")
        case .speaking: return Color(hex: "6B6680")
        case .processing: return Color(hex: "F59E0B").opacity(0.7)
        }
    }
}

enum HintProvider {
    private static let hints = [
        "Say \"send it\" to submit your message",
        "Say \"stop\" to interrupt Claude (sends Escape)",
        "Say \"delete message\" to clear and start over",
        "Say \"cmd clear\" to type /clear as a slash command",
        "Say \"focus window 2\" to switch iTerm2 pane",
        "Start talking while Claude speaks to barge in",
        "Change response mode in the menu bar",
        "Use \"command\" + any word for slash commands",
        "Mute icon stops TTS and cancels recording",
        "Unmute to jump straight into listening mode",
        "Claude reads responses aloud, then listens for you",
        "Say \"focus window 1-4\" to switch split panes",
    ]

    static func random() -> String {
        hints.randomElement() ?? hints[0]
    }
}
