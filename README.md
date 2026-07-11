# meet-slack

Set a Slack status (📅 "On a meeting") automatically while you are in a Google
Meet, including unplanned meets that never hit your calendar. Local-only, zero
third-party services, plain shell.

## How it works

```
Chrome tabs --osascript--> meet-slack.sh --curl--> Slack users.profile.set
   (poll)                     | token from macOS Keychain
launchd (every 30s) ----------| state file: only calls Slack on a transition
                                in-meet   -> set   status
                                left-meet -> clear status
```

- **Signal**: a Chrome tab whose URL matches a Meet meeting code
  (`meet.google.com/abc-defg-hij`). The plain `meet.google.com` landing page is
  excluded, so idly having Meet open does not trip it.
- **On-change only**: a state file (`~/.config/meet-slack/state`) means Slack is
  called once on entry and once on exit, not every tick.
- **Non-destructive exit**: on leaving a meet it clears the status only if it is
  still the one we set; a status you changed mid-meet is left alone.
- **Safe**: if Chrome is not running, `pgrep` returns early and never launches it.

## Setup

### 1. Create a Slack user token (one-time, manual)

1. https://api.slack.com/apps -> **Create New App** -> *From scratch*, pick the
   Abacum workspace.
2. **OAuth & Permissions** -> *User Token Scopes* -> add `users.profile:read`
   **and** `users.profile:write` (read is needed to check the status is still
   ours before clearing it on exit).
3. **Install to Workspace** and authorize. (Our workspace may require an admin to
   approve the app install first.)
4. Copy the **User OAuth Token** (starts with `xoxp-`).

### 2. Run the installer

```sh
./install.sh
```

It prompts for the token (paste it, input is hidden), stores it in the Keychain,
installs the launchd agent, and starts it. Safe to re-run.

### 3. Approve the Automation prompt (macOS forces this)

The first time the agent reads Chrome, macOS shows a **"wants to control Google
Chrome"** prompt, attributed to the agent (not your terminal). Approve it. If you
miss it, enable it under **System Settings > Privacy & Security > Automation**.

Then join a test Meet and confirm your Slack status changes. Errors, if any, are
logged to `~/.config/meet-slack/meet-slack.log`.

> Approving that prompt during a plain `./meet-slack.sh` run in Terminal does NOT
> cover the background agent: macOS scopes Automation grants per calling process,
> so the agent needs its own approval, which is the prompt above.

## Uninstall

```sh
./uninstall.sh
```

Clears any status we set, removes the launchd agent, and deletes the token from
the Keychain.

## Config

Edit the block at the top of `meet-slack.sh`: `STATUS_TEXT`, `STATUS_EMOJI`
(use `:google-meet:` if that custom emoji exists in the workspace). Keep both
free of `"` and `\` (they go into JSON unescaped).

## Security notes

- The token is stored in the login Keychain with `-A`, so the headless agent can
  read it without a prompt it cannot answer. The flip side: any process running
  as you can read it too. That is unavoidable for an unsigned shell script (there
  is no stable app identity to scope the Keychain ACL to). The real mitigation is
  scope: the token only carries `users.profile:write`, so a leak can only change
  your status, nothing else.
- The token briefly appears on the argument list of `security` / `curl`, visible
  to other processes running as you via `ps`. Since the Keychain item is already
  readable by any such process, this adds no meaningful exposure on a single-user
  Mac (and macOS hides other users' argv from non-root).

## Manual install (if you prefer not to use install.sh)

```sh
security add-generic-password -s meet-slack -a slack -w 'xoxp-YOUR-TOKEN' -U -A
cp com.andugu.meetslack.plist ~/Library/LaunchAgents/
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.andugu.meetslack.plist
```

## Known limitations

- **Waiting room / pre-join counts as busy.** The pre-join screen shares the
  meeting-code URL; distinguishing it from an active call needs DOM access
  (a browser extension), which this tool deliberately avoids.
- **Chrome PWA windows are not seen.** If you install Meet as a standalone app
  window, AppleScript tab enumeration may miss it. Use a normal tab.
- **Chrome only.** The `tell application "Google Chrome"` block is Chrome-specific.
- **Latency up to 30s.** `StartInterval` in the plist trades freshness for fewer
  wakeups; lower it if you want faster updates.
- **Log is not rotated.** It stays tiny in the happy path (success is silent); if
  the agent keeps failing it accumulates error lines, so clear it if it grows.
