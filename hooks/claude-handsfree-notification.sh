#!/bin/bash
# Claude Code Notification hook — sends permission prompts to Claude Code Handsfree Voice app
# Installed in ~/.claude/settings.json under hooks.Notification

INPUT=$(cat)
MESSAGE=$(echo "$INPUT" | jq -r '.message // empty')

if [ -z "$MESSAGE" ]; then
    exit 0
fi

# Send to Claude Code Handsfree Voice app's local HTTP server
curl -s -X POST "http://localhost:27182/hook/notification" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg msg "$MESSAGE" '{message: $msg}')" \
    --connect-timeout 2 \
    --max-time 5 2>/dev/null &

exit 0
