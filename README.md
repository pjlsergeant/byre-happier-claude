# byre-happier-claude

A [byre](https://github.com/pjlsergeant/byre) agent skill,
`pjlsergeant/happier-claude`, that runs Claude Code inside
[happier](https://happier.dev), so a box's Claude session is mirrored to the
happier app on your phone or in a browser and you can follow and answer it
from there.

It is a layer on byre's bundled `claude` skill, the way `pjlsergeant/zai`
layers on `codex`. The `claude` skill still supplies the Claude binary, its
`.claude` state volume and its login; this skill adds:

- Node LTS (v24.22.0, sha256-pinned), baked into the image, for happier's
  Claude runtime.
- The happier CLI (stable channel, official signed installer), baked into the
  image under `~/.happier-cli`. Its bundled zellij and Claude Agent SDK come
  with it.
- A per-project `.happier` state volume at `~/.happier` (happier's settings
  and sign-in key). Each project's box is its own happier "machine".
- A launch wrapper, `byre-happier-claude-launch`, that starts
  `happier --yolo ...` instead of `claude --dangerously-skip-permissions ...`,
  with byre's MCP config, Claude Skills directory and agent context forwarded
  to Claude.

## Install

```
byre skill install https://raw.githubusercontent.com/pjlsergeant/byre-happier-claude/<tag>/skills/happier-claude/skill.toml --digest sha256:<digest>
```

(The tag and digest are filled in at release time. `byre skill pack` prints
the digest. To try it from a checkout, run
`byre skill install skills/happier-claude/skill.toml`.)

Then in the project's `byre.config`:

```toml
agent  = "pjlsergeant/happier-claude"
skills = ["claude"]            # add claude-shared-auth if you use it
```

`skills = ["claude"]` is required: this skill brings no Claude of its own.

## First launch: sign in

On the first `byre develop` in a project, happier shows its sign-in screen
before Claude starts:

```
Connect this computer
› 1. Mobile app (recommended)    Scan a QR code with Happier on your phone.
  2. Web browser                 Open one copyable link in any browser.
```

Pick one and approve it from the app or browser. The sign-in lives in the
project's `.happier` volume, so it survives rebuilds. Claude itself still
needs its own login (byre's `claude` skill) as usual.

To sign in again (another account, or a revoked machine), from `byre shell`:

```
happier auth login --force
```

`happier auth status` shows whether the box is signed in.

## Unified terminal runtime

happier can run Claude inside its bundled zellij (the "unified terminal"),
which mirrors the real Claude TUI. That is an account setting, not something
this skill can switch on: in the happier app, Settings -> AI backends ->
Claude Code -> Use unified terminal runtime. The skill also works with
happier's default runtime.

## Assumptions and limits in this version

- **No firewall skill.** The relay hosts (`api.happier.dev`,
  `cloud.happier.dev`) are declared as egress, but this iteration has only
  been tried with an open network.
- **Hosted relay by default.** Set `HAPPIER_SERVER_URL` (and
  `HAPPIER_WEBAPP_URL` for sign-in links) in the project's `[env]` to use a
  self-hosted relay.
- **No daemon, so no remote start.** Sessions exist only while
  `byre develop` runs; you cannot start a new session from the app.
- **Updates come from rebuilds.** happier's own update check is off; the
  image installs the current stable release when it is built.
- **Context size.** happier only accepts byre's agent context inline (as
  `--append-system-prompt`, not as a file). Above about 100 KB the wrapper
  drops the per-session additions, and then the whole context, printing a
  warning line each time.
