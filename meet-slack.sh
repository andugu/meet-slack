#!/bin/bash
# Set a Slack status while a Google Meet tab is open in Chrome. launchd runs this
# every 30s (see the plist); state persists in $STATE_FILE between runs.

set -u

# Keep STATUS_TEXT / STATUS_EMOJI free of " and \ : both are interpolated into JSON
# unescaped, and STATUS_TEXT is matched verbatim to tell if a status is still ours.
STATUS_TEXT="In a meeting"
STATUS_EMOJI=":spiral_calendar_pad:"   # 🗓️  (:date: is 📅, :calendar: is 📆)
KEYCHAIN_SERVICE="meet-slack"
STATE_FILE="$HOME/.config/meet-slack/state"

SLACK_API="https://slack.com/api"
# A meeting URL is meet.google.com/abc-defg-hij; this skips the bare landing page.
MEET_RE='meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}'

in_meet() {
    pgrep -qx "Google Chrome" || return 1   # not running -> not in a meet; don't launch it
    # osascript exits non-zero when it can't control Chrome (usually Automation not
    # granted); log that instead of failing silently.
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
        echo "meet-slack: no token in Keychain; run install.sh" >&2
        return 1
    }
}

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

# Clear the status only if it is still ours, so a status you set mid-meet survives.
# Non-zero on API failure so the caller retries instead of leaving a stale status.
clear_status_if_ours() {
    local token get_resp current resp
    token=$(slack_token) || return 1
    get_resp=$(curl -s --max-time 10 "$SLACK_API/users.profile.get" \
        -H "Authorization: Bearer $token")
    [[ "$get_resp" == *'"ok":true'* ]] || {
        echo "meet-slack: could not read current Slack status: $get_resp" >&2
        return 1
    }
    current=$(sed -n 's/.*"status_text":[ ]*"\([^"]*\)".*/\1/p' <<<"$get_resp")
    [ "$current" = "$STATUS_TEXT" ] || return 0   # not ours -> leave it

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
[ "$prev" = 1 ] || prev=0
if in_meet; then cur=1; else cur=0; fi

# Act only on a transition, and record the new state only if Slack accepted it.
if [ "$cur" != "$prev" ]; then
    if [ "$cur" = 1 ]; then
        set_status           && echo 1 > "$STATE_FILE"
    else
        clear_status_if_ours && echo 0 > "$STATE_FILE"
    fi
fi
