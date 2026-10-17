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

if [ "$have" -eq 1 ] && [ -n "$text" ]; then
  exec happier --append-system-prompt "$text" "$@"
fi
exec happier "$@"
