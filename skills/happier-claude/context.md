# Claude inside happier (byre skill pjlsergeant/happier-claude)

This Claude Code session was launched through **happier** (`happier --yolo ...`),
which mirrors it to the user's happier app (phone or browser) over a relay, so
the user can read along and reply from there. When the user has turned on the
unified terminal runtime in their happier account, the session runs inside
happier's bundled zellij; otherwise happier uses its default Claude runtime.
Treat messages arriving from the app exactly like messages typed at the terminal.

## Where things live

- `~/.happier` (`$HAPPIER_HOME_DIR`) is happier's state: settings, the sign-in
  key, logs. It is a per-project byre state volume, so this box is one happier
  "machine" in the user's account and its sign-in survives rebuilds. Do not
  edit or delete it.
- The happier CLI itself is in `~/.happier-cli` (image, not state); Node is
  `/usr/local/bin/node`. Updates come from rebuilding the image.
- Claude's own state is still `~/.claude` (byre's claude skill).

## Sign-in

On the first launch in a project, happier shows its sign-in screen (a QR code
to scan with the happier phone app, or a URL to open in a browser) before
Claude starts. To sign in again, the user runs `happier auth login --force`
from `byre shell`. Never try to sign in on the user's behalf.

## What this version does not do

- No happier daemon: no remote start of sessions from the app, no background
  service. Sessions exist only while this launch runs.
- Relay is the hosted `api.happier.dev` (web app `cloud.happier.dev`) unless the
  user set `HAPPIER_SERVER_URL` / `HAPPIER_WEBAPP_URL` in the project's `[env]`.
- This iteration assumes no byre firewall skill; with one, the relay hosts are
  declared as egress but a self-hosted relay must be added by the user.
- The unified terminal is an account setting in the happier app
  (Settings -> AI backends -> Claude Code -> Use unified terminal runtime);
  there is no CLI or env switch for it.

## How this context reached you

byre's agent context arrived as an inline `--append-system-prompt` (happier
does not forward `--append-system-prompt-file`). The launcher caps it at about
100 KB: past that it falls back to byre's baked context alone (dropping
per-session additions such as the enforced egress list), and past that again
to no injected context, printing one warning line per step at launch. The text
actually composed is kept at `${TMPDIR:-/tmp}/byre-agent-context.md`.

## Useful in-box commands

`happier auth status`, `happier session list`, `happier doctor`.
