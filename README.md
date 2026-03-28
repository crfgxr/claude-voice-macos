# Claude Code Handsfree Voice macOS

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
git clone https://github.com/crfgxr/claude-code-handsfree.git
cd claude-code-handsfree
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
        "command": "/path/to/claude-code-handsfree/hooks/claude-handsfree-stop.sh",
        "async": true
      }
    ]
  }
}
```

## Usage

1. Launch **Claude Code Handsfree Voice** — a floating panel and menu bar icon appear
2. Run Claude Code in iTerm2
3. When Claude responds, the app reads it aloud
4. After speaking, it automatically starts listening
5. Speak your reply, then say **"send it"** to submit
6. Repeat — fully hands-free loop

### Voice Commands

| Command | Action |
|---------|--------|
| **"send it"** | Submit your message to Claude Code |
| **"stop"** | Send Escape key to iTerm2 (interrupts Claude Code) |
| **"delete message"** | Clear transcript and start over |
| **"command X"** / **"cmd X"** | Type `/X` as a slash command (e.g., "cmd clear" → `/clear`) |
| **"focus window 1-4"** | Switch to iTerm2 split pane 1-4 |

### Barge-in

Start speaking while Claude is talking — TTS stops immediately and switches to listening mode. No button press needed.

### Panel Controls

| Control | Action |
|---------|--------|
| **Speak Now** button | Start listening (auto-unmutes if muted) |
| **Say "Send It"** button | Tap or say "send it" to submit |
| **Reset** button (↺) | Clears transcript, restarts listening (visible while listening) |
| **Mute** button | Stops TTS, cancels recording, mutes app |
| **Settings** gear (⚙) | Opens macOS Spoken Content settings |

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

### Audio

- Music keeps playing during recording — no audio ducking
- TTS pre-rendered to file for smooth playback under CPU load
- Persistent audio engine — no clicks from hardware reconfiguration
- Sound feedback: Tink on send, Pop on focus switch, Purr on delete, Funk on stop

## Use Cases

### Hands-Free Coding Sessions
Sit back, talk through your ideas, and let Claude Code build it. No typing needed — just describe what you want, say "send it", hear the result, and keep iterating.

### Accessibility
Use Claude Code without a keyboard. Navigate split panes with "focus window", send slash commands with "cmd clear", and interrupt with "stop" — all by voice.

### Multitasking While Coding
Walk around, stretch, or grab coffee while Claude works. The app reads responses aloud through your AirPods and listens for your next instruction. Music keeps playing in the background.

### Code Reviews & Debugging
Describe bugs verbally: "There's a null pointer exception in the user service when the email field is empty, fix it, send it." Claude hears you, works on it, and reads back what it did.

### Rapid Prototyping
Voice is faster than typing for brainstorming. Speak your architecture ideas, UI changes, or feature requests naturally. Say "delete message" to start over if you misspeak.

### Pair Programming with Claude
Use multiple iTerm2 split panes — one for Claude Code, others for logs or servers. Switch between them with "focus window 2" and talk to Claude in whichever pane you need.

## Tech Stack

- **Swift** + **SwiftUI** for the native macOS app
- **`say` command** for text-to-speech (pre-rendered to file, played via AVAudioPlayer — no audio conflicts)
- **SFSpeechRecognizer** + persistent **AVAudioEngine** for speech-to-text (no hardware reconfiguration clicks)
- **NWListener** TCP server for receiving Claude Code hook messages
- **AppleScript** for sending text and commands to iTerm2

## Terminal Support

| Terminal | Status |
|----------|--------|
| iTerm2 | Supported (AppleScript `write text`) |
| Terminal.app | Not yet implemented |
| Ghostty | Not supported (no AppleScript API) |

## License

MIT
