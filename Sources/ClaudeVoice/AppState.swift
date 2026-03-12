import Foundation
import Combine
import AppKit

enum VoiceState: String {
    case idle
    case speaking
    case listening
    case processing
}

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var state: VoiceState = .idle
    @Published var audioLevel: CGFloat = 0.0
    @Published var isMuted: Bool = false
    @Published var autoVoiceEnabled: Bool = false
    @Published var currentMessage: String = ""
    @Published var isVisible: Bool = true
    @Published var statusText: String = "Ready"
    @Published var liveTranscript: String = ""

    private init() {}

    func toggleRecording() {
        switch state {
        case .idle:
            startListening()
        case .speaking:
            VoiceManager.shared.stopSpeaking()
            startListening()
        case .listening:
            stopListening()
        case .processing:
            break
        }
    }

    func startListening() {
        // Remember which app is focused RIGHT NOW (before anything changes)
        KeySimulator.shared.rememberFrontmostApp()

        state = .listening
        audioLevel = 0.3
        statusText = "Listening..."
        liveTranscript = ""
        VoiceManager.shared.startDirectRecording()
    }

    func stopListening() {
        state = .processing
        statusText = "Sending..."
        VoiceManager.shared.stopDirectRecordingAndSubmit()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.state == .processing else { return }
            self.state = .idle
            self.audioLevel = 0.0
            self.statusText = "Ready"
            self.liveTranscript = ""
        }
    }

    func handleHookMessage(_ message: String) {
        guard !isMuted, !message.isEmpty else { return }

        if state == .listening {
            VoiceManager.shared.cancelRecording()
        }
        VoiceManager.shared.stopSpeaking()

        currentMessage = message
        state = .speaking
        statusText = "Speaking..."

        VoiceManager.shared.speak(message) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.state == .speaking else { return }
                self.startListening()
            }
        }
    }
}
