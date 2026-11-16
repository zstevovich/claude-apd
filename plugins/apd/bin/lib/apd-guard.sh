#!/bin/bash
# apd-guard.sh — finds the compiled guard binary (bin/compiled/apd-guard-<os>-<arch>)
# for this platform. Sourced by the three guards that read shell commands:
# guard-bash-scope, guard-git, guard-spec-blind. The binary is the judge; the
# guard script around it resolves the project, prints the message and writes
# the audit line.
#
# A guard whose judge is missing REFUSES. An absent binary must never read as
# "nothing to object to".

_apd_guard_bin() {
  local os arch
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)
  [ "$arch" = "x86_64" ] && arch="amd64"
  [ "$arch" = "aarch64" ] && arch="arm64"   # Linux ARM's name for what Go calls arm64
  printf '%s' "${APD_PLUGIN_ROOT}/bin/compiled/apd-guard-${os}-${arch}"
}

# _apd_guard_require <guard name> — sets APD_GUARD_BIN or refuses the call.
_apd_guard_require() {
  APD_GUARD_BIN=$(_apd_guard_bin)
  [ -x "$APD_GUARD_BIN" ] && return 0
  echo "BLOCKED: $1 cannot judge this command — its binary is missing." >&2
  echo "  Expected: $APD_GUARD_BIN" >&2
  echo "  APD ships binaries for macOS and Linux on amd64 and arm64. Reinstall or update the" >&2
  echo "  plugin; on another platform build it from guard/ in the APD repository" >&2
  echo "  (go build -o <that path> ./cmd/apd-guard)." >&2
  log_block "guard-binary-missing" "$1"
  exit 2
}

# _apd_guard_failed <guard name> <exit code> <output> — the binary ran and
# answered with something that is neither "allow" nor "block".
_apd_guard_failed() {
  echo "BLOCKED: $1 could not judge this command (the guard binary exited $2)." >&2
  [ -n "$3" ] && echo "  $3" >&2
  log_block "guard-error" "$1 rc=$2"
  exit 2
}
