#!/usr/bin/env sh
# shellcheck shell=sh
# Device Discovery — Linux hardware inventory (modular, default).
#
# Single-file edition: device_discovery.monolithic.sh (same features, self-contained).
# Implementation lives in device_discovery/ (lib + collectors per bus).
# Usage: device_discovery.sh [OPTIONS]
#        device_discovery.sh --help

set -u

DD_DIR=$(
    CDPATH=
    cd -- "$(dirname "$0")" && pwd
)
DD_ROOT=$DD_DIR/device_discovery
# Used by lib/privileges.sh for sudo re-exec
# shellcheck disable=SC2034
DD_ENTRY=$DD_DIR/device_discovery.sh

# shellcheck disable=SC1090
. "$DD_ROOT/load.sh"

main "$@"
