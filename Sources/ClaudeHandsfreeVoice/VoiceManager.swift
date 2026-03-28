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
    private var isRecording = false
    private var engineRunning = false
    private var bargeInFrames = 0

    override init() {
        super.init()
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        requestPermissions()
        startPersistentEngine()
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            print("[HandsFree] Speech: \(status == .authorized ? "OK" : "status \(status.rawValue)")")
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            print("[HandsFree] Mic: \(granted ? "OK" : "denied")")
        }
    }

    // MARK: - TTS via `say` (pre-render to file, then play for smooth audio)

    private var audioPlayer: AVAudioPlayer?
    private let ttsFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("claudevoice_tts.aiff")

    // MARK: - Persistent Audio Engine (avoids hardware reconfiguration clicks)

    private func startPersistentEngine() {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Tap always installed — forward to recognizer when recording, detect barge-in when speaking
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            if self.isRecording {
                self.recognitionRequest?.append(buffer)
                self.updateAudioLevel(buffer: buffer)
            } else if AppState.shared.state == .speaking {
                // Barge-in: detect voice, silently stop TTS and start listening
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameLength = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameLength { sum += abs(channelData[i]) }
                let avg = sum / Float(max(frameLength, 1))

                if avg > 0.02 {
                    self.bargeInFrames += 1
                } else {
                    self.bargeInFrames = 0
                }

                if self.bargeInFrames >= 1 {
                    self.bargeInFrames = 0
                    DispatchQueue.main.async {
                        guard AppState.shared.state == .speaking else { return }
                        VoiceManager.shared.stopSpeaking()
                        AppState.shared.startListening()
                    }
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            engineRunning = true
            print("[HandsFree] Persistent audio engine started")
        } catch {
            print("[HandsFree] Engine start error: \(error)")
        }
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        stopRecognitionTask()

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
                print("[HandsFree] say render error: \(error)")
                DispatchQueue.main.async {
                    self.speechCompletion?()
                    self.speechCompletion = nil
                }
            }
        }

        startLevelSimulation()
        print("[HandsFree] TTS rendering with voice: \(voiceName ?? "default")")
    }

    private func playRenderedSpeech() {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: ttsFileURL)
            audioPlayer?.delegate = self
            audioPlayer?.play()
        } catch {
            print("[HandsFree] Playback error: \(error)")
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

    private func stopRecognitionTask() {
        isRecording = false
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
            print("[HandsFree] Speech recognizer unavailable")
            DispatchQueue.main.async {
                AppState.shared.statusText = "Speech unavailable"
                AppState.shared.state = .idle
            }
            return
        }

        // Restart engine if it died
        if !engineRunning {
            startPersistentEngine()
        }

        stopRecognitionTask()
        transcriptionBuffer = ""

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let error = error {
                print("[HandsFree] Recognition error: \(error.localizedDescription)")
                return
            }
            guard let result = result else { return }
            let text = result.bestTranscription.formattedString
            self?.transcriptionBuffer = text

            DispatchQueue.main.async {
                AppState.shared.liveTranscript = text
            }

            let lower = text.lowercased()

            // Quick response mode: auto-submit when user says a number
            if AppState.shared.awaitingQuickResponse {
                let numberMap = [
                    "one": "1", "two": "2", "three": "3", "four": "4",
                    "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
                    "1": "1", "2": "2", "3": "3", "4": "4",
                    "5": "5", "6": "6", "7": "7", "8": "8", "9": "9",
                    "yes": "1", "yeah": "1", "yep": "1", "ok": "1", "okay": "1", "allow": "1",
                    "no": "2", "nope": "2", "deny": "2", "reject": "2",
                    "always": "3", "always allow": "3",
                ]
                // Check last word(s) for a number match
                let words = lower.split(separator: " ")
                let lastTwo = words.suffix(2).joined(separator: " ")
                let lastOne = words.last.map(String.init) ?? ""

                if let num = numberMap[lastTwo] ?? numberMap[lastOne] {
                    DispatchQueue.main.async {
                        AppState.shared.submitQuickResponse(num)
                    }
                    return
                }
            }

            // "focus window N" — switch to iTerm2 split pane N
            let focusPatterns = ["focus window 1", "focus window 2", "focus window 3", "focus window 4",
                                 "focus window one", "focus window two", "focus window three", "focus window four"]
            let wordToNum = ["one": 1, "two": 2, "three": 3, "four": 4,
                             "1": 1, "2": 2, "3": 3, "4": 4]
            for pattern in focusPatterns {
                if lower.hasSuffix(pattern) {
                    let word = pattern.replacingOccurrences(of: "focus window ", with: "")
                    if let num = wordToNum[word] {
                        DispatchQueue.main.async {
                            NSSound(named: .init("Pop"))?.play()
                            KeySimulator.shared.focusSession(num)
                            AppState.shared.cancelListening()
                            AppState.shared.startListening()
                        }
                        return
                    }
                }
            }

            // "stop" — send Escape key to iTerm2
            if lower.hasSuffix("stop") || lower.hasSuffix("stop.") || lower.hasSuffix("stop!") {
                DispatchQueue.main.async {
                    print("[HandsFree] Stop triggered — sending Escape")
                    NSSound(named: .init("Funk"))?.play()
                    KeySimulator.shared.sendEscape()
                    AppState.shared.cancelListening()
                    AppState.shared.startListening()
                }
                return
            }

            // "delete message" — clear transcript and restart listening
            if lower.hasSuffix("delete message") || lower.hasSuffix("delete message.") {
                DispatchQueue.main.async {
                    print("[HandsFree] Delete message triggered — restarting")
                    NSSound(named: .init("Purr"))?.play()
                    AppState.shared.cancelListening()
                    AppState.shared.startListening()
                }
                return
            }

            // "command/cmd X" — replace transcript with /X, wait for "send it"
            let cmdRange = lower.range(of: "command ") ?? lower.range(of: "cmd ")
            if let range = cmdRange {
                let afterCommand = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Check if it ends with "send it" — send the command immediately
                let afterLower = afterCommand.lowercased()
                if afterLower.hasSuffix("send it") || afterLower.hasSuffix("send it.") {
                    var cmd = afterCommand
                    for t in ["send it", "send it.", "send it!"] {
                        if cmd.lowercased().hasSuffix(t) {
                            cmd = String(cmd.dropLast(t.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                            break
                        }
                    }
                    if !cmd.isEmpty {
                        self?.transcriptionBuffer = "/\(cmd)"
                        DispatchQueue.main.async {
                            AppState.shared.stopListening()
                        }
                        return
                    }
                }
                // Otherwise just show /X as the live transcript
                if !afterCommand.isEmpty {
                    self?.transcriptionBuffer = "/\(afterCommand)"
                    DispatchQueue.main.async {
                        AppState.shared.liveTranscript = "/\(afterCommand)"
                    }
                    return
                }
            }

            // "send it" — submit transcript
            if lower.hasSuffix("send it") || lower.hasSuffix("send it.") {
                DispatchQueue.main.async {
                    AppState.shared.stopListening()
                }
            }
        }

        isRecording = true
        print("[HandsFree] Recording started (engine persistent)")
    }

    func stopDirectRecordingAndSubmit() {
        stopRecognitionTask()

        var text = transcriptionBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let triggers = ["send it", "send it.", "send it!"]
        let lower = text.lowercased()
        for t in triggers {
            if lower.hasSuffix(t) {
                text = String(text.dropLast(t.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        print("[HandsFree] Final: \"\(text)\"")

        guard !text.isEmpty else {
            print("[HandsFree] Nothing to submit")
            DispatchQueue.main.async {
                AppState.shared.liveTranscript = ""
                AppState.shared.startListening()
            }
            return
        }

        // Play send sound feedback
        NSSound(named: .init("Tink"))?.play()

        KeySimulator.shared.pasteAndSubmit(text)
    }

    func cancelRecording() {
        stopRecognitionTask()
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
            print("[HandsFree] Could not read system voice")
            return nil
        }

        print("[HandsFree] System voice ID: \(voiceId)")

        if let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            return voice.name
        }

        // Extract name from ID (e.g. "gryphon-neural_aaron_en-US_premium" → "aaron")
        let parts = voiceId.lowercased().components(separatedBy: "_")
        let allVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }

        for voice in allVoices {
            if parts.contains(voice.name.lowercased()) {
                print("[HandsFree] Matched system voice: \(voice.name)")
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
