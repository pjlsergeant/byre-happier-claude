#!/bin/sh
# happier-shared-auth launch env hook -- PURE under byre's ADR 0028: the
# environment it leaves behind is its only effect. env.d hooks are SOURCED
# (by the launcher before the agent, and by every login shell via
# /etc/profile.d/byre-env.sh), after the image ENV is in place, so this
# export overrides the HAPPIER_HOME_DIR that pjlsergeant/happier-claude sets
# in [runtime].env. No output, no prompts, no file writes, nothing that ends
# or reconfigures the sourcing shell (`exit`, `exec`, `set`, traps).
#
# The target is this skill's machine-scoped identity volume, so every byre
# box on the host that enables the skill shares ONE happier state home: one
# sign-in, one happier machine. The directory is the volume's mount point,
# so it always exists in a box that enabled the skill; the guard is for
# login shells on odd setups. A directory that is missing, or is a symlink
# (it would point the home outside the identity volume), exports nothing,
# and happier keeps using the per-project ~/.happier. BYRE_IDENTITY_BASE is
# a test seam (claude-shared-auth's precedent).
_byre_happier_home=${BYRE_IDENTITY_BASE:-/home/dev/.byre-identity}/happier
if [ -d "$_byre_happier_home" ] && [ ! -L "$_byre_happier_home" ]; then
  HAPPIER_HOME_DIR=$_byre_happier_home
  export HAPPIER_HOME_DIR
fi
unset _byre_happier_home
