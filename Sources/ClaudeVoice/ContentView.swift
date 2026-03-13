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

    var body: some View {
        VStack(spacing: 0) {
            // Top: waveform
            WaveformView(
                state: appState.state,
                level: appState.audioLevel
            )
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Bottom: controls row
            HStack(spacing: 8) {
                // Status text / live transcript
                Group {
                    if appState.state == .listening {
                        Text(appState.liveTranscript.isEmpty ? "Listening..." : String(appState.liveTranscript.suffix(50)))
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

                // Mute button — stops speaking and cancels listening
                Button(action: {
                    if appState.state == .speaking {
                        VoiceManager.shared.stopSpeaking()
                        appState.state = .idle
                        appState.audioLevel = 0.0
                        appState.statusText = "Ready"
                    }
                    if appState.state == .listening {
                        appState.cancelListening()
                    }
                    appState.isMuted.toggle()
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
        .frame(width: 300, height: 76)
        .background(Color(hex: "1C1A2E"))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
    }

    private var buttonLabel: String {
        switch appState.state {
        case .idle: return "Speak Now"
        case .listening: return "Say 'Send It'"
        case .speaking: return "Stop"
        case .processing: return "Sending"
        }
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
