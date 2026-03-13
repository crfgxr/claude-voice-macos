import AVFoundation
import Speech
import AppKit

final class VoiceManager: NSObject, AVAudioPlayerDelegate {
    static let shared = VoiceManager()

    private var sayProcess: Process?
    private var speechCompletion: (() -> Void)?
    private var levelTimer: Timer?

    private var speechRecognizer: SFSpeechRecognizer?
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var transcriptionBuffer: String = ""

    override init() {
        super.init()
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

    // MARK: - TTS via `say` (pre-render to file, then play for smooth audio)

    private var audioPlayer: AVAudioPlayer?
    private let ttsFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("claudevoice_tts.aiff")

    func speak(_ text: String, completion: @escaping () -> Void) {
        ensureRecordingStopped()

        speechCompletion = completion
        let cleaned = cleanForSpeech(text)

        guard !cleaned.isEmpty else {
            DispatchQueue.main.async { completion() }
            return
        }

        let voiceName = resolveVoiceName()

        // Step 1: Pre-render speech to file (background thread)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")

            var args = [String]()
            if let voice = voiceName {
                args += ["-v", voice]
            }
            args += ["-o", self.ttsFileURL.path, "-f", "-"]
            process.arguments = args

            let pipe = Pipe()
            process.standardInput = pipe

            do {
                try process.run()
                let data = cleaned.data(using: .utf8) ?? Data()
                pipe.fileHandleForWriting.write(data)
                pipe.fileHandleForWriting.closeFile()
                process.waitUntilExit()

                // Step 2: Play the rendered file on main thread
                DispatchQueue.main.async {
                    self.playRenderedSpeech()
                }
            } catch {
                print("[ClaudeVoice] say render error: \(error)")
                DispatchQueue.main.async {
                    self.speechCompletion?()
                    self.speechCompletion = nil
                }
            }
        }

        startLevelSimulation()
        print("[ClaudeVoice] TTS rendering with voice: \(voiceName ?? "default")")
    }

    private func playRenderedSpeech() {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: ttsFileURL)
            audioPlayer?.delegate = self
            audioPlayer?.play()
        } catch {
            print("[ClaudeVoice] Playback error: \(error)")
            stopLevelSimulation()
            speechCompletion?()
            speechCompletion = nil
        }
    }

    func stopSpeaking() {
        // Kill any in-progress render
        if let process = sayProcess, process.isRunning {
            process.terminate()
        }
        sayProcess = nil
        // Stop playback
        audioPlayer?.stop()
        audioPlayer = nil
        stopLevelSimulation()
        speechCompletion = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.stopLevelSimulation()
            self?.audioPlayer = nil
            self?.speechCompletion?()
            self?.speechCompletion = nil
        }
    }

    private func ensureRecordingStopped() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func startLevelSimulation() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
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

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

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
        ensureRecordingStopped()

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

        KeySimulator.shared.pasteAndSubmit(text)
    }

    func cancelRecording() {
        ensureRecordingStopped()
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

    // MARK: - Voice resolution

    private func resolveVoiceName() -> String? {
        let selectedId = AppState.shared.selectedVoiceId
        if selectedId == "system" {
            return resolveSystemVoiceName()
        }
        // Get voice name from AVSpeechSynthesisVoice identifier
        if let voice = AVSpeechSynthesisVoice(identifier: selectedId) {
            return voice.name
        }
        // Fallback: extract last component from identifier
        if let last = selectedId.components(separatedBy: ".").last, !last.isEmpty {
            return last
        }
        return nil
    }

    private func resolveSystemVoiceName() -> String? {
        guard let selections = UserDefaults(suiteName: "com.apple.Accessibility")?
            .array(forKey: "SpokenContentDefaultVoiceSelectionsByLanguage"),
              selections.count >= 2,
              let dict = selections[1] as? [String: Any],
              let voiceId = dict["voiceId"] as? String else {
            print("[ClaudeVoice] Could not read system voice")
            return nil
        }

        print("[ClaudeVoice] System voice ID: \(voiceId)")

        if let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            return voice.name
        }

        // Extract name from ID (e.g. "gryphon-neural_aaron_en-US_premium" → "aaron")
        let parts = voiceId.lowercased().components(separatedBy: "_")
        let allVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }

        for voice in allVoices {
            if parts.contains(voice.name.lowercased()) {
                print("[ClaudeVoice] Matched system voice: \(voice.name)")
                return voice.name
            }
        }

        return nil
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
