import Foundation
import Combine
import AppKit

enum VoiceState: String {
    case idle
    case speaking
    case listening
    case processing
}

enum ResponseMode: String {
    case full
    case summary
    case notify
}

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var state: VoiceState = .idle
    @Published var audioLevel: CGFloat = 0.0
    @Published var isMuted: Bool = false
    @Published var autoVoiceEnabled: Bool = false
    @Published var selectedVoiceId: String = UserDefaults.standard.string(forKey: "selectedVoiceId")
        ?? "com.apple.voice.enhanced.en-US.Allison"
    @Published var responseMode: ResponseMode = {
        if let raw = UserDefaults.standard.string(forKey: "responseMode"),
           let mode = ResponseMode(rawValue: raw) {
            return mode
        }
        return .full
    }()
    @Published var currentMessage: String = ""
    @Published var isVisible: Bool = true
    @Published var statusText: String = "Ready"
    @Published var liveTranscript: String = ""
    var pendingMessage: String?

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

    func cancelListening() {
        VoiceManager.shared.cancelRecording()
        state = .idle
        audioLevel = 0.0
        statusText = "Ready"
        liveTranscript = ""
    }

    func startListening() {
        // Auto-unmute when user explicitly starts listening
        isMuted = false

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

        // After sending, switch back to listening mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            // If Claude already started speaking, don't interrupt
            guard self.state == .processing else { return }

            if let pending = self.pendingMessage {
                self.pendingMessage = nil
                self.handleHookMessage(pending)
            } else {
                self.liveTranscript = ""
                self.startListening()
            }
        }
    }

    func handleHookMessage(_ message: String) {
        guard !isMuted, !message.isEmpty else { return }

        // Cancel any active recording — hook means Claude has responded
        if state == .listening {
            VoiceManager.shared.cancelRecording()
        }

        VoiceManager.shared.stopSpeaking()

        currentMessage = message

        let textToSpeak: String
        switch responseMode {
        case .full:
            textToSpeak = message
        case .summary:
            // First + last sentence
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let sentences = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if sentences.count <= 2 {
                textToSpeak = trimmed
            } else {
                let first = sentences[0]
                let last = sentences[sentences.count - 1]
                textToSpeak = first + ". " + last + "."
            }
        case .notify:
            textToSpeak = "Hey, I'm done. Check it out."
        }

        state = .speaking
        statusText = "Speaking..."

        VoiceManager.shared.speak(textToSpeak) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.state == .speaking else { return }
                self.startListening()
            }
        }
    }

    func setResponseMode(_ mode: ResponseMode) {
        responseMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "responseMode")
    }

    func setVoice(_ identifier: String) {
        selectedVoiceId = identifier
        UserDefaults.standard.set(identifier, forKey: "selectedVoiceId")
    }
}
