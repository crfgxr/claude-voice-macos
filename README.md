# Claude Voice macOS

A native macOS menu bar app for hands-free voice interaction with [Claude Code](https://claude.ai/code) CLI.

Claude speaks its responses aloud, then automatically listens for your reply. Say **"send it"** to submit — no keyboard needed.

## How It Works

```
Claude Code responds → Hook sends message to app → App speaks it via TTS
                                                          ↓
                                                  Auto-starts listening
                                                          ↓
                                              You speak your reply
                                                          ↓
                                          Say "send it" (or tap button)
                                                          ↓
                                        Text sent to iTerm2 → Claude Code
```

## Requirements

- macOS 14.0+
- [iTerm2](https://iterm2.com/) (for voice input to terminal)
- [Claude Code CLI](https://claude.ai/code)
- Xcode Command Line Tools (`xcode-select --install`)
- Microphone & Speech Recognition permissions

## Install

```bash
git clone https://github.com/crfgxr/claude-voice-macos.git
cd claude-voice-macos
make run
```

This builds the app, installs it to `/Applications`, and launches it.

### Hook Setup

Add the stop hook to your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "Stop": [
      {
        "type": "command",
        "command": "/path/to/claude-voice-macos/hooks/claude-voice-stop.sh",
        "async": true
      }
    ]
  }
}
```

## Usage

1. Launch **ClaudeVoice** — a floating panel and menu bar icon appear
2. Run Claude Code in iTerm2
3. When Claude responds, the app reads it aloud
4. After speaking, it automatically starts listening
5. Speak your reply, then say **"send it"** to submit
6. Repeat — fully hands-free loop

### Controls

| Control | Action |
|---------|--------|
| **Speak Now** button | Start listening (auto-unmutes if muted) |
| **Say "Send It"** button | Tap or say "send it" to submit |
| **Mute** button | Stops TTS, cancels recording, mutes app |
| **Menu bar icon** | Settings, show/hide panel, quit app |

### Menu Bar Settings

- **Show/Hide Panel** — toggle the floating panel
- **Response Mode** — how Claude's responses are read:
  - **Full Response** — reads the entire response
  - **Summary** — reads first + last sentence
  - **Notify Only** — just says "Hey, I'm done. Check it out."
- **Voice** — select TTS voice:
  - **System Default** — follows System Settings > Spoken Content
  - Enhanced voices (e.g., Allison Enhanced)
  - Siri voices (e.g., Aaron, Nicky)
- **Voice Settings...** — opens macOS Spoken Content settings to download new voices
- **Test TTS** — test the current voice and response mode

All settings persist across app restarts.

## Tech Stack

- **Swift** + **SwiftUI** for the native macOS app
- **AVSpeechSynthesizer** for text-to-speech (configurable voice)
- **SFSpeechRecognizer** + **AVAudioEngine** for speech-to-text
- **CoreAudio** for preventing audio ducking during recording
- **NWListener** TCP server for receiving Claude Code hook messages
- **AppleScript** for sending text to iTerm2

## Terminal Support

| Terminal | Status |
|----------|--------|
| iTerm2 | Supported (AppleScript `write text`) |
| Terminal.app | Not yet implemented |
| Ghostty | Not supported (no AppleScript API) |

## License

MIT
