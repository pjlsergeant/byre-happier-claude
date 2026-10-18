## Shared happier sign-in (pjlsergeant/happier-shared-auth)

This box shares its happier state with every other byre box on this host
that enables `pjlsergeant/happier-shared-auth`. `$HAPPIER_HOME_DIR` is
`~/.byre-identity/happier`, a machine-wide identity volume, set by
`/etc/byre/env.d/50-happier-shared-auth.sh`. The per-project `~/.happier`
volume is still mounted but is NOT used.

What follows from that:

- This box is the SAME happier machine as every other box here. Renaming it
  in the app renames it for all of them, and per-machine settings (such as
  the unified terminal runtime) apply to all boxes.
- Sign-in happens once, in whichever box launches first. `happier auth login
  --force` from any box replaces the shared credential and so re-signs ALL
  boxes.
- Each session's `host` metadata still shows its own container's hostname.
- Do not delete or edit the contents of `~/.byre-identity/happier`; that
  signs every box out.
