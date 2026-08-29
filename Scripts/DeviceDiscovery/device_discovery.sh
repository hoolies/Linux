#!/usr/bin/env sh
# device_discovery — Linux hardware inventory (modular).
# Single-file edition: device_discovery.monolithic.sh.

set -eu
export LC_ALL=C
unalias -a 2>/dev/null || true
unset -f rm mv cp grep awk sed tr wc cat basename dirname date hostname uname whoami id timeout 2>/dev/null || true

DD_DIR=$(
    CDPATH=''
    cd -- "$(dirname -- "$0")" && pwd
)
DD_ROOT=$DD_DIR/device_discovery
# PROGNAME is read by sourced usage(); DD_ENTRY by privileges.sh
# shellcheck disable=SC2034
readonly PROGNAME="${0##*/}"
# shellcheck disable=SC2034
DD_ENTRY=$DD_DIR/device_discovery.sh

# shellcheck disable=SC1090,SC1091
. "$DD_ROOT/load.sh"

main "$@"
