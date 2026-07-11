#!/bin/bash
# uninstall.sh - stop and remove the launchd agent and delete the Keychain token.
# No `set -e`: this is best-effort cleanup, keep going even if a piece is gone.
set -uo pipefail

LABEL="com.andugu.meetslack"
SERVICE="meet-slack"
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
CONFIG_DIR="$HOME/.config/meet-slack"
DOMAIN="gui/$(id -u)"

# Clear any status we may have set, BEFORE we delete the token, so uninstalling
# mid-meet does not leave you stuck showing "On a Meet call".
TOKEN=$(security find-generic-password -s "$SERVICE" -a slack -w 2>/dev/null || true)
if [ -n "$TOKEN" ]; then
    curl -s --max-time 10 -X POST https://slack.com/api/users.profile.set \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-type: application/json; charset=utf-8" \
        --data '{"profile":{"status_text":"","status_emoji":""}}' >/dev/null || true
fi

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
rm -f "$DEST"
echo "Removed launchd agent."

if security find-generic-password -s "$SERVICE" -a slack >/dev/null 2>&1; then
    security delete-generic-password -s "$SERVICE" -a slack >/dev/null
    echo "Deleted token from Keychain."
else
    echo "No Keychain token found."
fi

rm -f "$CONFIG_DIR/state"
echo "Done. (Log at $CONFIG_DIR/meet-slack.log left in place; delete it if you like.)"
