#!/bin/bash
# install.sh - store the Slack token in the Keychain, then install and start the
# launchd agent. Safe to re-run (idempotent).
set -euo pipefail

LABEL="com.andugu.meetslack"
SERVICE="meet-slack"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$HOME/Library/LaunchAgents"
DEST="$AGENTS_DIR/$LABEL.plist"
CONFIG_DIR="$HOME/.config/meet-slack"
LOG="$CONFIG_DIR/meet-slack.log"
DOMAIN="gui/$(id -u)"

# 1. Slack token -> Keychain --------------------------------------------------
printf 'Paste your Slack user token (xoxp-...): '
read -rs TOKEN
echo
if [[ "$TOKEN" != xoxp-* ]]; then
    echo "error: token should start with 'xoxp-'. Aborting, nothing changed." >&2
    exit 1
fi
# -U updates the item if it already exists, so re-running does not fail.
# -A lets the headless launchd agent read the token without a GUI prompt it
# cannot answer. Trade-off: any process running as you can then read it, which
# is unavoidable for an unsigned script (see README "Security notes").
security add-generic-password -s "$SERVICE" -a slack -w "$TOKEN" -U -A
echo "Stored token in Keychain (service '$SERVICE')."

# 2. Install the launchd agent, pointed at THIS directory ---------------------
mkdir -p "$AGENTS_DIR" "$CONFIG_DIR"
cp "$SCRIPT_DIR/$LABEL.plist" "$DEST"
# Rewrite the absolute paths so the agent works no matter where this folder lives.
/usr/libexec/PlistBuddy \
    -c "Set :ProgramArguments:0 $SCRIPT_DIR/meet-slack.sh" \
    -c "Set :StandardOutPath $LOG" \
    -c "Set :StandardErrorPath $LOG" \
    "$DEST"
chmod +x "$SCRIPT_DIR/meet-slack.sh"

# 3. (Re)load it with the modern launchctl API (load/unload are legacy) -------
launchctl bootout --wait "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl enable "$DOMAIN/$LABEL"
launchctl bootstrap "$DOMAIN" "$DEST"
echo "Loaded launchd agent '$LABEL' (checks every 30s)."

cat <<EOF

Almost done. macOS will ask permission the FIRST time the agent reads Chrome:
a "wants to control Google Chrome" prompt, attributed to the agent (not this
terminal). Approve it. If you miss it, enable it under:
  System Settings > Privacy & Security > Automation

Then join a test Meet and confirm your Slack status changes.
Errors, if any, are logged to: $LOG
EOF
