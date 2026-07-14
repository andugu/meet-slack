#!/bin/bash
# Store the Slack token in the Keychain and (re)install the launchd agent. Safe to re-run.
set -euo pipefail

LABEL="com.andugu.meetslack"
SERVICE="meet-slack"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
CONFIG_DIR="$HOME/.config/meet-slack"
LOG="$CONFIG_DIR/meet-slack.log"
DOMAIN="gui/$(id -u)"
# The agent runs a copy from here (non-TCC-protected), so the repo can live anywhere.
INSTALL_DIR="$HOME/Library/Application Support/meet-slack"
INSTALL_BIN="$INSTALL_DIR/meet-slack.sh"

printf 'Paste your Slack user token (xoxp-...): '
read -rs TOKEN
echo
if [[ "$TOKEN" != xoxp-* ]]; then
    echo "error: token should start with 'xoxp-'. Aborting." >&2
    exit 1
fi
# -U updates in place on re-run; -A lets the headless agent read the token without
# a GUI prompt (any process running as you can then read it too).
security add-generic-password -s "$SERVICE" -a slack -w "$TOKEN" -U -A

mkdir -p "$(dirname "$DEST")" "$CONFIG_DIR" "$INSTALL_DIR"
cp "$SCRIPT_DIR/meet-slack.sh" "$INSTALL_BIN"
chmod +x "$INSTALL_BIN"
cp "$SCRIPT_DIR/$LABEL.plist" "$DEST"
/usr/libexec/PlistBuddy \
    -c "Set :ProgramArguments:0 $INSTALL_BIN" \
    -c "Set :StandardOutPath $LOG" \
    -c "Set :StandardErrorPath $LOG" \
    "$DEST"

launchctl bootout --wait "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl enable "$DOMAIN/$LABEL"
launchctl bootstrap "$DOMAIN" "$DEST"

cat <<EOF
Installed (runs every 30s). On your first Meet, approve the "control Google Chrome"
prompt, or enable it under System Settings > Privacy & Security > Automation.
Errors log to $LOG. Edited the script? Re-run ./install.sh to update the copy.
EOF
