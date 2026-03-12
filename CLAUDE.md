# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Every code change requires the full cycle:
```bash
pkill -f "ClaudeVoice" 2>/dev/null
rm -rf ClaudeVoice.app
swift build -c release
BUILD_DIR=$(swift build -c release --show-bin-path)
mkdir -p ClaudeVoice.app/Contents/{MacOS,Resources}
cp "$BUILD_DIR/ClaudeVoice" ClaudeVoice.app/Contents/MacOS/
cp Resources/Info.plist ClaudeVoice.app/Contents/
codesign --force --sign - ClaudeVoice.app
open ClaudeVoice.app
```

**Always verify the floating panel is visible after launch.** The panel uses `canBecomeKey: false` so it must use `orderFrontRegardless()`, never `makeKeyAndOrderFront()`. Ad-hoc codesign changes identity each rebuild which can invalidate macOS permissions.

## Goal

Voice-driven hands-free interaction with Claude Code CLI:
1. **Output (WORKS):** Claude Code `Stop` hook → HTTP POST to localhost:27182 → app reads response aloud via `AVSpeechSynthesizer`
2. **Input (WORKS with iTerm2):** App records mic via `SFSpeechRecognizer` → transcribes → sends to iTerm2 via AppleScript `write text`

After TTS finishes, the app automatically starts listening. User says "send it" to submit, creating a fully hands-free loop.

## Architecture

```
Claude Code [Stop hook] → hook script → curl POST localhost:27182
                                              ↓
                                    HookServer receives message
                                              ↓
                                    VoiceManager speaks via TTS
                                              ↓
                                    Auto-starts listening (or user clicks Speak Now)
                                              ↓
                                    SFSpeechRecognizer records + transcribes
                                              ↓
                                    User says "send it" or taps button
                                              ↓
                                    KeySimulator sends to iTerm2 via AppleScript
```

### Components

- **main.swift** — NSApplication entry point, `setActivationPolicy(.accessory)` (no dock icon)
- **AppDelegate.swift** — Menu bar icon + floating panel setup + hook server start
- **AppState.swift** — `@Published` state: idle/speaking/listening/processing. Coordinates all managers.
- **FloatingPanel.swift** — `NSPanel` with `.nonactivatingPanel`, `canBecomeKey: false`, `canBecomeMain: false`. Uses `ClickThroughHostingView` (overrides `acceptsFirstMouse`) so buttons work without stealing focus.
- **ContentView.swift** — Layout: waveform on top, controls on bottom (status text, mute, Speak Now / "Say 'Send It'" button). No close button — quit from menu bar only.
- **WaveformView.swift** — 40-bar animated equalizer. Purple=speaking, blue=listening.
- **VoiceManager.swift** — `AVSpeechSynthesizer` for TTS. `SFSpeechRecognizer` + `AVAudioEngine` for recording. Strips markdown before speaking. Detects "send it" trigger phrase.
- **HookServer.swift** — `NWListener` TCP server on port 27182. Parses HTTP POST or raw JSON with `{"message": "..."}`.
- **KeySimulator.swift** — Sends transcribed text to iTerm2 via AppleScript `write text`. Currently iTerm2 only.

### Hook Integration

- Hook script: `hooks/claude-voice-stop.sh` — reads `last_assistant_message` from stdin JSON, POSTs to app
- Installed in `~/.claude/settings.json` under `hooks.Stop` (async)
- The hook correctly fires and delivers messages to the app

### Terminal Support

- **iTerm2** — WORKS via AppleScript `write text` (current implementation)
- **Ghostty** — NOT supported (no AppleScript dictionary; CGEvent and System Events approaches failed)
- **Terminal.app** — Could work via AppleScript `do script` (not implemented)
