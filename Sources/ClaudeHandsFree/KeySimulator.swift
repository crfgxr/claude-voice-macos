import AppKit
import ApplicationServices

final class KeySimulator {
    static let shared = KeySimulator()

    /// Remember which app was frontmost so we can return to it
    private(set) var lastFrontmostApp: NSRunningApplication?

    func rememberFrontmostApp() {
        lastFrontmostApp = NSWorkspace.shared.frontmostApplication
        print("[HandsFree] Remembered frontmost: \(lastFrontmostApp?.localizedName ?? "none")")
    }

    // MARK: - Paste text into iTerm2 via AppleScript

    // MARK: - Focus a specific iTerm2 split pane

    func focusSession(_ index: Int) {
        print("[HandsFree] Focusing iTerm2 session \(index)")

        let script = """
        tell application "iTerm2"
            tell current tab of current window
                select session \(index)
            end tell
        end tell
        """

        runOsascript(script) { success in
            if success {
                print("[HandsFree] Focused session \(index)")
            }
        }
    }

    // MARK: - Send Escape key to iTerm2

    func sendEscape() {
        print("[HandsFree] Sending Escape to iTerm2")
        let script = """
        tell application "iTerm2"
            tell current session of current window
                write text (ASCII character 27)
            end tell
        end tell
        """
        runOsascript(script) { success in
            if success { print("[HandsFree] Escape sent") }
        }
    }

    // MARK: - Paste text into iTerm2

    func pasteAndSubmit(_ text: String) {
        print("[HandsFree] Sending to iTerm2: \(text.prefix(80))...")

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

        runOsascript(script) { success in
            if success {
                print("[HandsFree] iTerm2 write text succeeded")
            }
        }
    }

    // MARK: - Helper

    private func runOsascript(_ script: String, completion: ((Bool) -> Void)? = nil) {
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
                    completion?(true)
                } else {
                    let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? "unknown"
                    print("[HandsFree] AppleScript error: \(errStr)")
                    completion?(false)
                }
            } catch {
                print("[HandsFree] osascript launch error: \(error)")
                completion?(false)
            }
        }
    }
}
