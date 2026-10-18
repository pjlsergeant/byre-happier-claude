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
byre skill install https://raw.githubusercontent.com/pjlsergeant/byre-happier-claude/v0.3.0/skills/happier-claude/skill.toml --digest sha256:fb5c54e5d34fd0089de869404aa9d5a7ef7403b3b866c7f6be8e4ce816503a19
```

To try it from a checkout instead, run
`byre skill install skills/happier-claude/skill.toml`.

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

## Shared sign-in across projects

happier stores some settings per machine, the Claude runtime choice (unified
terminal) among them, and without help every byre project's box registers as
a separate, hex-named machine. The companion skill
`pjlsergeant/happier-shared-auth` makes every box on the host one happier
machine instead: one sign-in, renamed once in the app, per-machine settings
applied once.

```toml
agent  = "pjlsergeant/happier-claude"
skills = ["claude", "pjlsergeant/happier-shared-auth"]
```

byre offers it during onboarding when you pick `pjlsergeant/happier-claude`.
It points `HAPPIER_HOME_DIR` at a machine-scoped identity volume
(`~/.byre-identity/happier`). Sign in once, in whichever box launches first;
later boxes are already signed in. `happier auth login --force` from any box
then re-signs all of them. Each session still reports its own container
hostname. The per-project `.happier` volume stays mounted but is unused while
the companion is on.

Install it with:

```
byre skill install https://raw.githubusercontent.com/pjlsergeant/byre-happier-claude/v0.3.0/skills/happier-shared-auth/skill.toml --digest sha256:e7bcc17ec69486adc2ed0420d8039af8d0fdd5404e30cf0552c4dd7073e3d9e5
```

## Unified terminal runtime

happier can run Claude inside its bundled zellij (the "unified terminal"),
which mirrors the real Claude TUI. That is a per-machine setting in the
happier app, not something this skill can switch on: Settings -> AI backends
-> Claude Code -> Use unified terminal runtime. It is set once per happier
machine; without the shared-auth companion each project's box is its own
machine, and with it the setting applies once for every box on the host.
The setting is gated by a server feature flag (fail-closed), so the toggle
may be absent on some relays. The skill also works with happier's default
runtime.

zellij is only the transport here: a config shipped with the skill turns off
its tab and status bars, pane frames, startup tips and all its keybindings, so
Claude's TUI fills the terminal and gets every key. It is installed as
`/etc/zellij/config.kdl` (with `layouts/plain.kdl`) and linked from
`~/.config/zellij/config.kdl`, because happier starts zellij with a minimal
environment, so a `ZELLIJ_CONFIG_FILE` set in `[env]` would never reach it.
To get zellij's UI back, replace that link in the box with your own config.

**Shift-Enter.** The config also turns off zellij's kitty keyboard protocol
support. With it on, zellij re-encodes every key for a pane that enabled the
protocol, which Claude does, and that turns iTerm2's Shift-Enter (a line feed)
and tmux's default extended-keys form into a plain Enter, so Claude submits
instead of inserting a newline. With it off, zellij passes key bytes through
unchanged, and Shift-Enter behaves exactly as it does with plain Claude in the
same terminal chain. The one cost: a kitty-native terminal (kitty, Ghostty,
WezTerm) used directly, without tmux in between, no longer gets the kitty
protocol pushed to it, so its Shift-Enter arrives as plain Enter; bind the key
in the terminal to send a newline, or replace the `~/.config/zellij/config.kdl`
link with a config that leaves the option on. Ctrl-J inserts a newline in
every setup.

## Environment: what Claude sees

byre's contract is that the box's environment is the agent's environment:
`BYRE_*` variables, the project's `[env]` and credentials, and anything the
skills' env hooks export. happier, though, filters the environment of the
Claude process it starts down to an allowlist (`PATH`, `HOME`, `TERM`,
`CLAUDE_*`, `ANTHROPIC_*`, `XDG_*` and a few more). Without help, Claude
under happier would lose everything else, including `HAPPIER_HOME_DIR`, so
`happier` commands run inside the session would use the wrong state home.

The launch wrapper restores parity: before starting happier it lists the name
of every variable it holds (except `_`, `SHLVL`, `PWD`, `OLDPWD`) in
`HAPPIER_SPAWN_EXPLICIT_ENV_KEYS_JSON`, the list of names happier lets through
to Claude. Caveats:

- **Under the unified terminal, values briefly touch disk.** happier writes
  the Claude process's environment to a `0600` temp file
  (`$TMPDIR/happier-terminal-launch-*/launch.json`) for the seconds between
  starting the terminal pane and the pane reading and deleting it. Only names
  that look secret are kept out of the file and passed directly:

  ```
  /(^ANTHROPIC_|^CLAUDE_CODE_|(^|_)(TOKEN|SECRET|PASSWORD|PRIVATE_KEY|API_KEY|AUTHORIZATION|BEARER|CREDENTIAL)(_|$))/i
  ```

  To keep a credential off disk, give it a name with a `_TOKEN`, `_SECRET`,
  `_API_KEY`, `_PASSWORD` or `_CREDENTIAL` segment. `PROK_AUTHTOKEN` and
  `SOMETHING_DEVELOPER_KEY`, for example, do not match.
- **Don't link a Claude "connected service" in happier for this machine.**
  With one selected, happier strips Claude's auth environment (such as
  `CLAUDE_CODE_OAUTH_TOKEN`) whatever this list says.
- **The variable is a happier internal**, not a documented interface. This
  repo's tests pin its behaviour; a happier release could change it. See
  [docs/upstream-happier-env-passthrough.md](docs/upstream-happier-env-passthrough.md)
  for the change proposed to happier.

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
