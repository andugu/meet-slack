# meet-slack

Sets your Slack status to 🗓️ "In a meeting" while a Google Meet is open in Chrome,
and clears it when you leave. Local-only, no dependencies, plain shell.

## How it works

A launchd agent runs `meet-slack.sh` every 30s. It reads Chrome's tabs for a Meet
URL (`meet.google.com/abc-defg-hij`) and, on entering or leaving, sets or clears
your status via the Slack API. The token lives in the Keychain; a state file in
`~/.config/meet-slack` means Slack is called only on a change. On exit it clears
the status only if it's still the one it set, so a status you picked mid-meet stays.

## Setup

1. Create a Slack app at https://api.slack.com/apps (**From scratch**), add the
   **User Token Scopes** `users.profile:read` and `users.profile:write`, install it,
   and copy the `xoxp-` token. (Your workspace may need an admin to approve.)
2. Run `./install.sh` and paste the token.
3. On your first Meet, approve the macOS "control Google Chrome" prompt (or enable it
   under System Settings → Privacy & Security → Automation). Errors log to
   `~/.config/meet-slack/meet-slack.log`.

## Uninstall

`./uninstall.sh` — clears the status, removes the agent and installed copy, deletes the token.

## Config

Edit `STATUS_TEXT` / `STATUS_EMOJI` at the top of `meet-slack.sh` (keep them free of
`"` and `\`), then re-run `./install.sh`.

## Notes

- The agent runs a copy from `~/Library/Application Support/meet-slack`, so this repo
  can live anywhere and move freely.
- The pre-join screen counts as "in a meeting" (telling it apart would need a browser
  extension). Only the main Google Chrome app is checked.
- The token carries only profile scopes, so a leak can at most change your status.
