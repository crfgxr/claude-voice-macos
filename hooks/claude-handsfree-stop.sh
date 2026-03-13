#!/bin/bash
# Claude Code Stop hook — sends last_assistant_message to Claude Code Hands-Free app
# Installed in ~/.claude/settings.json under hooks.Stop

INPUT=$(cat)
MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // empty')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // "false"')

# Don't trigger if already in a stop hook loop
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

if [ -z "$MESSAGE" ]; then
    exit 0
fi

# Send to Claude Code Hands-Free app's local HTTP server
curl -s -X POST "http://localhost:27182/hook/stop" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg msg "$MESSAGE" '{message: $msg}')" \
    --connect-timeout 2 \
    --max-time 5 2>/dev/null &

exit 0
