#!/bin/bash
# byre launch adapter for Claude Code inside happier (pjlsergeant/happier-claude).
#
# Same context merge as byre's bundled byre-claude-launch (ADR 0046): the BAKED
# /etc/byre/agent-context.md plus the launcher's per-session additions
# ($BYRE_SESSION_CONTEXT) become ONE system-prompt addition. The difference is
# the delivery: happier only understands the INLINE form. Its SDK and unified
# terminal runtimes parse `--append-system-prompt <text>` out of the forwarded
# Claude args and re-merge it with happier's own prompt, but silently drop
# `--append-system-prompt-file`. So the merged text goes on argv as one string.
#
# An argv string meets Linux's per-argument exec limit (MAX_ARG_STRLEN,
# 128 KiB), and happier re-passes the text to claude again, so this wrapper
# keeps a margin: above 100000 bytes it degrades to the baked context alone,
# then to no injection at all, warning once per step on stderr. Context is
# informational, so a failure composing it never blocks the launch.
#
# The merged file is still written (launch-owned, fixed path in TMPDIR) so the
# exact text the session got stays readable in-box. Fixed name + mktemp +
# atomic rename, with the directory probes before and after the mv, for the
# reasons spelled out in byre's claude-launch.sh: exec replaces this shell so
# nothing cleans up afterwards (a fixed name doesn't accumulate copies), a
# plain `>` would follow a symlink planted at the fixed path (rename replaces
# it), and a planted directory would swallow the mv while reporting success.
# NOT `if ! { ...; } > file`: bash treats a failed redirect as success there;
# the || form takes the failure branch.
#
# byre writes NOTHING into ~/.claude or ~/.happier: the happier state home is
# the per-project state volume and happier owns it.
set -eu

CTX=${BYRE_AGENT_CONTEXT:-/etc/byre/agent-context.md}
LIMIT=100000

merged="${TMPDIR:-/tmp}/byre-agent-context.md"
tmp=""
if tmp=$(mktemp "$merged.XXXXXXXX" 2>/dev/null); then
  # shellcheck disable=SC2015 # intended: the || arm cleans up after ANY failed step
  { [ -r "$CTX" ] && cat "$CTX"; printf '%s' "${BYRE_SESSION_CONTEXT:-}"; } > "$tmp" 2>/dev/null &&
    [ ! -d "$merged" ] &&
    mv -f "$tmp" "$merged" 2>/dev/null &&
    [ -f "$merged" ] ||
    { rm -f "$tmp" 2>/dev/null || true; merged=""; }
else
  merged=""
fi

# Byte length of a readable regular file, or empty on any failure.
size_of() {
  [ -f "$1" ] && [ -r "$1" ] || return 1
  wc -c < "$1" 2>/dev/null | tr -d ' '
}

text=""
have=0
if [ -n "$merged" ] && n=$(size_of "$merged") && [ -n "$n" ]; then
  if [ "$n" -le "$LIMIT" ]; then
    text=$(cat "$merged") && have=1 || have=0
  else
    echo "byre-happier-claude-launch: merged agent context is $n bytes (> $LIMIT); using the baked context alone" >&2
  fi
fi
if [ "$have" -eq 0 ] && n=$(size_of "$CTX") && [ -n "$n" ]; then
  if [ "$n" -le "$LIMIT" ]; then
    text=$(cat "$CTX") && have=1 || have=0
  else
    echo "byre-happier-claude-launch: baked agent context is $n bytes (> $LIMIT); launching without injected context" >&2
  fi
fi

# happier's own flag parser (apps/cli/src/backends/claude/remote/
# sdkFlagOverrides.ts, nextValue) refuses a flag VALUE that starts with '-',
# and the unified builder then drops `--append-system-prompt` together with
# its value anyway, so a context opening with a markdown bullet or rule would
# vanish silently. Only the first character is checked; a leading newline
# defeats it and is harmless whitespace at the top of a system prompt.
case "$text" in -*) text=$'\n'"$text" ;; esac

# Environment parity. byre's contract is that the box environment IS the
# agent's environment, but happier filters the Claude child: its
# buildClaudeSubprocessEnv (apps/cli/src/backends/claude/spawn/) keeps an
# allowlist (PATH, HOME, TERM, CLAUDE_*, ANTHROPIC_*, XDG_*, ...) and drops
# everything else -- BYRE_*, HAPPIER_HOME_DIR, project credentials, env.d
# exports. It also admits any name listed in HAPPIER_SPAWN_EXPLICIT_ENV_KEYS_JSON
# (a JSON array of names read from happier's OWN environment, parsed by
# src/daemon/spawn/spawnExplicitEnvKeysMarker.ts, deleted from the child env).
# That marker is a happier-internal daemon mechanism, not a documented
# interface; our wrapper tests pin the behaviour. So list every exported name
# except the shell's own bookkeeping (_, SHLVL, PWD, OLDPWD) and the marker.
# Names outside [A-Za-z_][A-Za-z0-9_]* are skipped (happier would drop them
# too), which also makes plain quoting a valid JSON encoding.
#
# Caveats, documented in README and context.md:
# - Unified terminal: happier writes the child env to a 0600 launch spec
#   (mkdtemp under $TMPDIR, happier-terminal-launch-*/launch.json) that the
#   in-pane runner deletes right after reading. Only names matching
#   /(^ANTHROPIC_|^CLAUDE_CODE_|(^|_)(TOKEN|SECRET|PASSWORD|PRIVATE_KEY|API_KEY|
#   AUTHORIZATION|BEARER|CREDENTIAL)(_|$))/i stay off disk (passed live), so a
#   forwarded credential with any other name sits on disk for those seconds.
# - A Claude "connected service" selected in happier makes happier strip
#   Claude's auth env (isolateClaudeRuntimeAuthEnv) whatever this list says.
keys=""
for k in $(compgen -e); do
  case "$k" in
    _ | SHLVL | PWD | OLDPWD | HAPPIER_SPAWN_EXPLICIT_ENV_KEYS_JSON) continue ;;
  esac
  [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
  keys="$keys${keys:+,}\"$k\""
done
unset HAPPIER_SPAWN_EXPLICIT_ENV_KEYS_JSON
if [ "${#keys}" -le "$LIMIT" ]; then
  export HAPPIER_SPAWN_EXPLICIT_ENV_KEYS_JSON="[$keys]"
else
  echo "byre-happier-claude-launch: env name list is ${#keys} bytes (> $LIMIT); not forwarding the box environment to Claude" >&2
fi

if [ "$have" -eq 1 ] && [ -n "$text" ]; then
  exec happier --append-system-prompt "$text" "$@"
fi
exec happier "$@"
