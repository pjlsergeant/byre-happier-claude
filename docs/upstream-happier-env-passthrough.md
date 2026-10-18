# Draft proposal for happier-dev/happier: a supported way to pass the caller's environment to Claude

Status: draft, not yet filed. References are to `apps/cli` at commit `cb5f427183`
(2026-10-16).

## Problem

When happier starts Claude Code through the Agent SDK or the unified terminal
runtime, it builds the child environment from an allowlist:
`src/backends/claude/spawn/buildClaudeSubprocessEnv.ts` keeps exact names
(`PATH`, `HOME`, `USER`, `SHELL`, `TERM`, `LANG`, `TMPDIR`, `SSH_AUTH_SOCK`,
proxy and certificate variables, ...) and prefixes (`CLAUDE_`, `ANTHROPIC_`,
`XDG_`, `TERM_`, ...), and drops everything else (lines ~34-96). The unified
path calls it from `src/backends/claude/unifiedTerminal/buildClaudeUnifiedTerminalSpawn.ts:304`.
(The local runtime, `src/backends/claude/claudeLocal.ts:428`, uses
`prepareClaudeSubprocessEnv`, which does not allowlist.)

That is a sensible default for a desktop, but it breaks setups where the
environment happier was started in is deliberately the agent's environment.
Our case is [byre](https://github.com/pjlsergeant/byre), which runs coding
agents in per-project containers: the container's environment carries the
project's configuration and credentials (API keys for tools the agent is
meant to use, a relay URL, the happier state home itself). Under happier,
Claude loses all of it. Even `HAPPIER_HOME_DIR` is dropped, so `happier`
commands the agent runs inside its own session resolve a different state home.

## What works today, and why it is fragile

`buildClaudeSubprocessEnv` also admits any name listed in
`HAPPIER_SPAWN_EXPLICIT_ENV_KEYS_JSON`, a JSON array read from happier's own
environment (`src/daemon/spawn/spawnExplicitEnvKeysMarker.ts`; names are
validated with `isValidEnvVarKey` and the marker is deleted from the child
env). Our launcher sets it to every variable name it holds, which restores
parity.

But the marker is an internal daemon mechanism: undocumented, with no
compatibility promise. And it composes badly with the unified terminal's
launch spec: `splitTerminalLaunchSpecEnv` (`buildClaudeUnifiedTerminalSpawn.ts:362-381`)
writes every variable to a 0600 file (`src/terminal/runtime/terminalLaunchSpec.ts:52`,
`mkdtemp(tmpdir(), 'happier-terminal-launch-')`, removed by
`scripts/terminal_launch_spec_runner.cjs` after reading), except names matching

```
/(^ANTHROPIC_|^CLAUDE_CODE_|(^|_)(TOKEN|SECRET|PASSWORD|PRIVATE_KEY|API_KEY|AUTHORIZATION|BEARER|CREDENTIAL)(_|$))/i
```

which are passed live. A credential called `PROK_AUTHTOKEN` or
`FOO_DEVELOPER_KEY` does not match, so it sits on disk for the seconds between
spawn and the runner reading the file. The caller often knows exactly which
variables are secrets; the name regex can only guess.

## Proposal

1. **A documented, user-facing passthrough setting** for the Claude child
   environment, rather than the daemon marker. For example an env var such as
   `HAPPIER_CLAUDE_ENV_PASSTHROUGH` taking a JSON array of names or `"*"` (all
   of happier's own environment, minus happier's internal variables), and/or a
   CLI flag (`--env-passthrough <names|*>`). Same semantics on the local, SDK
   and unified paths.
2. **Caller-declared secret keys.** A sibling list (e.g.
   `HAPPIER_CLAUDE_ENV_SECRET_KEYS`, JSON array) whose names the unified
   launch spec always treats as passthrough-live, in addition to the existing
   regex, so known credentials never reach the launch-spec file whatever their
   names.
3. Keep today's allowlist as the default when neither is set, so nothing
   changes for existing users.

We are happy to send a PR implementing (1) and (2), including tests next to
the existing ones for `buildClaudeSubprocessEnv` and `splitTerminalLaunchSpecEnv`.
