import AppKit
import ApplicationServices

final class KeySimulator {
    static let shared = KeySimulator()

    /// Remember which app was frontmost so we can return to it
    private(set) var lastFrontmostApp: NSRunningApplication?

    func rememberFrontmostApp() {
        lastFrontmostApp = NSWorkspace.shared.frontmostApplication
        print("[ClaudeVoice] Remembered frontmost: \(lastFrontmostApp?.localizedName ?? "none")")
    }

    // MARK: - Paste text into iTerm2 via AppleScript

    func pasteAndSubmit(_ text: String) {
        print("[ClaudeVoice] Sending to iTerm2: \(text.prefix(80))...")

        // Escape text for AppleScript string (backslashes first, then quotes)
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "iTerm2"
            tell current session of current window
                write text "\(escaped)"
            end tell
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            let pipe = Pipe()
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    print("[ClaudeVoice] iTerm2 write text succeeded")
                } else {
                    let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "unknown"
                    print("[ClaudeVoice] iTerm2 AppleScript error: \(errStr)")
                }
            } catch {
                print("[ClaudeVoice] osascript launch error: \(error)")
            }
        }
    }
}
