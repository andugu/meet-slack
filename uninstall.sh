#!/bin/bash
# Remove the launchd agent, installed copy, and Keychain token. Best-effort, so no set -e.
set -uo pipefail

LABEL="com.andugu.meetslack"
SERVICE="meet-slack"
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
CONFIG_DIR="$HOME/.config/meet-slack"
INSTALL_DIR="$HOME/Library/Application Support/meet-slack"
DOMAIN="gui/$(id -u)"

# Clear the status before deleting the token, so uninstalling mid-meet doesn't pin it.
TOKEN=$(security find-generic-password -s "$SERVICE" -a slack -w 2>/dev/null || true)
if [ -n "$TOKEN" ]; then
    curl -s --max-time 10 -X POST https://slack.com/api/users.profile.set \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-type: application/json; charset=utf-8" \
        --data '{"profile":{"status_text":"","status_emoji":""}}' >/dev/null || true
fi

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
rm -f "$DEST"
rm -rf "$INSTALL_DIR"
security delete-generic-password -s "$SERVICE" -a slack >/dev/null 2>&1 || true
rm -f "$CONFIG_DIR/state"
echo "Uninstalled meet-slack (log left at $CONFIG_DIR/meet-slack.log)."
