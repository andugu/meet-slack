#!/bin/bash
# meet-slack.sh - set a Slack status while a Google Meet tab is open in Chrome.
# Runs once per invocation; launchd (StartInterval) calls it on a schedule.
# No external deps: osascript, curl, security, pgrep are all built-in on macOS.

set -u

# --- config -----------------------------------------------------------------
# Keep STATUS_TEXT / STATUS_EMOJI free of " \ and control chars (newlines/tabs):
# they are interpolated into JSON without escaping, and the text is matched
# verbatim to decide ownership on exit.
STATUS_TEXT="On a meeting"
STATUS_EMOJI=":date:"                   # :date: renders as 📅 (Slack's :calendar: is the tear-off 📆)
KEYCHAIN_SERVICE="meet-slack"          # stored by install.sh via: security add-generic-password -s meet-slack ...
STATE_FILE="$HOME/.config/meet-slack/state"
# ----------------------------------------------------------------------------

SLACK_API="https://slack.com/api"

# A real meeting URL looks like meet.google.com/abc-defg-hij. This excludes the
# plain meet.google.com landing page, so just having Meet open does not count.
MEET_RE='meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}'

in_meet() {
    # If Chrome is not running we are not in a meet (and we must not launch it).
    pgrep -qx "Google Chrome" || return 1
    # Capture stdout+stderr together: a non-zero exit means controlling Chrome
    # failed (most often the Automation permission was never granted). Surface
    # it to the log instead of hiding it, so the tool is never a silent no-op.
    local urls
    if ! urls=$(osascript 2>&1 <<'APPLESCRIPT'
tell application "Google Chrome"
    set out to ""
    repeat with w in windows
        repeat with t in tabs of w
            try
                set out to out & (URL of t) & linefeed
            end try
        end repeat
    end repeat
    return out
end tell
APPLESCRIPT
    ); then
        echo "meet-slack: cannot read Chrome tabs (grant the Automation permission): $urls" >&2
        return 1
    fi
    grep -Eq "$MEET_RE" <<<"$urls"
}

slack_token() {
    security find-generic-password -s "$KEYCHAIN_SERVICE" -a slack -w 2>/dev/null || {
        echo "meet-slack: no token in Keychain (service '$KEYCHAIN_SERVICE'); run install.sh" >&2
        return 1
    }
}

# Set our meet status. Returns success only if Slack acknowledges the change.
set_status() {
    local token payload resp
    token=$(slack_token) || return 1
    payload=$(printf '{"profile":{"status_text":"%s","status_emoji":"%s","status_expiration":0}}' \
        "$STATUS_TEXT" "$STATUS_EMOJI")
    resp=$(curl -s --max-time 10 -X POST "$SLACK_API/users.profile.set" \
        -H "Authorization: Bearer $token" \
        -H "Content-type: application/json; charset=utf-8" \
        --data "$payload")
    [[ "$resp" == *'"ok":true'* ]] && return 0
    echo "meet-slack: Slack rejected the status update: $resp" >&2
    return 1
}

# Clear the status ONLY if it is still the one we set; if you changed it to
# something else during the meet, leave it untouched. Returns success once the
# exit is handled (cleared, or deliberately left alone). Returns non-zero on an
# API failure so the caller retries rather than leaving a stale status.
clear_status_if_ours() {
    local token get_resp current resp
    token=$(slack_token) || return 1
    get_resp=$(curl -s --max-time 10 "$SLACK_API/users.profile.get" \
        -H "Authorization: Bearer $token")
    [[ "$get_resp" == *'"ok":true'* ]] || {
        echo "meet-slack: could not read current Slack status: $get_resp" >&2
        return 1
    }
    # Extract the current status_text (tolerant of an optional space after the colon).
    current=$(sed -n 's/.*"status_text":[ ]*"\([^"]*\)".*/\1/p' <<<"$get_resp")
    [ "$current" = "$STATUS_TEXT" ] || return 0   # not ours -> leave it, exit handled

    resp=$(curl -s --max-time 10 -X POST "$SLACK_API/users.profile.set" \
        -H "Authorization: Bearer $token" \
        -H "Content-type: application/json; charset=utf-8" \
        --data '{"profile":{"status_text":"","status_emoji":""}}')
    [[ "$resp" == *'"ok":true'* ]] && return 0
    echo "meet-slack: Slack rejected clearing the status: $resp" >&2
    return 1
}

mkdir -p "$(dirname "$STATE_FILE")"
prev=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
[ "$prev" = 1 ] || prev=0          # treat a missing or garbled state file as "not in a meet"
if in_meet; then cur=1; else cur=0; fi

# Only touch Slack on a transition, and only record the new state if Slack agreed.
if [ "$cur" != "$prev" ]; then
    if [ "$cur" = 1 ]; then
        set_status           && echo 1 > "$STATE_FILE"
    else
        clear_status_if_ours && echo 0 > "$STATE_FILE"
    fi
fi
