import AVFoundation
import Speech
import AppKit

final class VoiceManager: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceManager()

    private let synthesizer = AVSpeechSynthesizer()
    private var speechCompletion: (() -> Void)?
    private var levelTimer: Timer?

    private var speechRecognizer: SFSpeechRecognizer?
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var transcriptionBuffer: String = ""

    override init() {
        super.init()
        synthesizer.delegate = self
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        requestPermissions()
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            print("[ClaudeVoice] Speech: \(status == .authorized ? "OK" : "status \(status.rawValue)")")
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            print("[ClaudeVoice] Mic: \(granted ? "OK" : "denied")")
        }
    }

    // MARK: - TTS

    func speak(_ text: String, completion: @escaping () -> Void) {
        speechCompletion = completion
        let cleaned = cleanForSpeech(text)
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Allison")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        synthesizer.speak(utterance)
        startLevelSimulation()
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        stopLevelSimulation()
        speechCompletion = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        stopLevelSimulation()
        DispatchQueue.main.async { [weak self] in
            self?.speechCompletion?()
            self?.speechCompletion = nil
        }
    }

    private func startLevelSimulation() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            DispatchQueue.main.async {
                if AppState.shared.state == .speaking {
                    AppState.shared.audioLevel = CGFloat.random(in: 0.3...0.95)
                }
            }
        }
    }

    private func stopLevelSimulation() {
        levelTimer?.invalidate()
        levelTimer = nil
        DispatchQueue.main.async { AppState.shared.audioLevel = 0.0 }
    }

    // MARK: - Direct Recording

    func startDirectRecording() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[ClaudeVoice] Speech recognizer unavailable")
            DispatchQueue.main.async {
                AppState.shared.statusText = "Speech unavailable"
                AppState.shared.state = .idle
            }
            return
        }

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = AVAudioEngine()
        transcriptionBuffer = ""

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateAudioLevel(buffer: buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let error = error {
                print("[ClaudeVoice] Recognition error: \(error.localizedDescription)")
                return
            }
            guard let result = result else { return }
            let text = result.bestTranscription.formattedString
            self?.transcriptionBuffer = text

            DispatchQueue.main.async {
                AppState.shared.liveTranscript = text
            }

            // Auto-stop on "send it"
            let lower = text.lowercased()
            if lower.hasSuffix("send it") || lower.hasSuffix("send it.") {
                DispatchQueue.main.async {
                    AppState.shared.stopListening()
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("[ClaudeVoice] Recording started")
        } catch {
            print("[ClaudeVoice] Mic error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                AppState.shared.statusText = "Mic error"
                AppState.shared.state = .idle
            }
        }
    }

    func stopDirectRecordingAndSubmit() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        var text = transcriptionBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let triggers = ["send it", "send it.", "send it!"]
        let lower = text.lowercased()
        for t in triggers {
            if lower.hasSuffix(t) {
                text = String(text.dropLast(t.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        print("[ClaudeVoice] Final: \"\(text)\"")

        guard !text.isEmpty else {
            print("[ClaudeVoice] Nothing to submit")
            DispatchQueue.main.async {
                AppState.shared.state = .idle
                AppState.shared.statusText = "No speech detected"
            }
            return
        }

        // Paste directly — no need to activate first, AppleScript handles it atomically
        KeySimulator.shared.pasteAndSubmit(text)
    }

    func cancelRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        transcriptionBuffer = ""
    }

    // MARK: - Audio level

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength { sum += abs(channelData[i]) }
        let avg = sum / Float(max(frameLength, 1))
        let mapped = min(CGFloat(avg * 25), 1.0)
        DispatchQueue.main.async {
            AppState.shared.audioLevel = max(mapped, 0.15)
        }
    }

    private func cleanForSpeech(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: " code block omitted ", options: .regularExpression)
        s = s.replacingOccurrences(of: "`[^`]+`", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[*_]{1,3}", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "https?://\\S+", with: "link", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^\\s*[-*+]\\s+", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
