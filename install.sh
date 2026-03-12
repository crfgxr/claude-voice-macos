#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClaudeVoice"
APP_BUNDLE="${APP_NAME}.app"
HOOK_SCRIPT="${SCRIPT_DIR}/hooks/claude-voice-stop.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "=== Claude Voice Installer ==="
echo ""

# Step 1: Build
echo "[1/4] Building ${APP_NAME}..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1 | tail -5

EXEC_PATH=$(swift build -c release --show-bin-path)/${APP_NAME}
if [ ! -f "$EXEC_PATH" ]; then
    echo "ERROR: Build failed. Binary not found at $EXEC_PATH"
    exit 1
fi

# Step 2: Create .app bundle
echo "[2/4] Creating app bundle..."
rm -rf "${SCRIPT_DIR}/${APP_BUNDLE}"
mkdir -p "${SCRIPT_DIR}/${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${SCRIPT_DIR}/${APP_BUNDLE}/Contents/Resources"

cp "$EXEC_PATH" "${SCRIPT_DIR}/${APP_BUNDLE}/Contents/MacOS/"
cp "${SCRIPT_DIR}/Resources/Info.plist" "${SCRIPT_DIR}/${APP_BUNDLE}/Contents/"

# Ad-hoc code sign (needed for Accessibility permissions)
codesign --force --sign - "${SCRIPT_DIR}/${APP_BUNDLE}"
echo "   App bundle created: ${SCRIPT_DIR}/${APP_BUNDLE}"

# Step 3: Install hook
echo "[3/4] Installing Claude Code hook..."
chmod +x "$HOOK_SCRIPT"

mkdir -p "$(dirname "$SETTINGS_FILE")"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

python3 << PYEOF
import json, os, sys

settings_file = os.path.expanduser("${SETTINGS_FILE}")
hook_script = "${HOOK_SCRIPT}"

with open(settings_file, 'r') as f:
    settings = json.load(f)

if 'hooks' not in settings:
    settings['hooks'] = {}

if 'Stop' not in settings['hooks']:
    settings['hooks']['Stop'] = []

# Check if hook already exists
already_installed = False
for group in settings['hooks']['Stop']:
    for h in group.get('hooks', []):
        if hook_script in h.get('command', ''):
            already_installed = True
            break

if not already_installed:
    settings['hooks']['Stop'].append({
        "hooks": [{
            "type": "command",
            "command": hook_script,
            "async": True
        }]
    })
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)
    print("   Hook installed in " + settings_file)
else:
    print("   Hook already installed")
PYEOF

# Step 4: Remind about permissions
echo "[4/4] Setup complete!"
echo ""
echo "=== Next steps ==="
echo ""
echo "  1. Run the app:"
echo "     open ${SCRIPT_DIR}/${APP_BUNDLE}"
echo ""
echo "  2. Grant permissions when prompted:"
echo "     - Accessibility (System Settings > Privacy & Security > Accessibility)"
echo "     - Microphone (for 'ok reply' detection)"
echo "     - Speech Recognition (for voice trigger)"
echo ""
echo "  3. Restart Claude Code for the hook to take effect"
echo ""
echo "  4. The app appears as a waveform icon in your menu bar"
echo "     and a floating pill widget on screen."
echo ""
echo "=== How it works ==="
echo ""
echo "  - When Claude finishes responding, the Stop hook fires"
echo "  - Claude Voice reads the response aloud via macOS TTS"
echo "  - After speaking, it activates voice mode (holds Space)"
echo "  - Say 'ok reply' or click the stop button to submit"
echo "  - Claude processes your voice input, and the cycle repeats"
echo ""
