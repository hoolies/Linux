#!/usr/bin/env bash
# crws — sample iotop and keep the top disk read/write rates.

set -euo pipefail
export LC_ALL=C
unalias -a 2>/dev/null || true
unset -f rm mv cp grep awk sed cat mkdir tar date iotop 2>/dev/null || true

readonly PROGNAME="${0##*/}"
readonly DIRR="/var/log/IORead"
readonly DIRW="/var/log/IOWrite"
readonly IOTOP_LOG="/var/log/iotop"
readonly SAMPLES=590
readonly DELAY="0.1"

usage() {
    cat <<EOF
Usage: $PROGNAME [OPTION]...
Sample iotop and store the top disk read and write rates.

Mandatory arguments to long options are mandatory for short options too.

  -h, --help            display this help and exit

Writes into $DIRR and $DIRW.  Needs iotop and write access to /var/log.
At midnight the directories are archived and $IOTOP_LOG is truncated.
EOF
}

unrecognized_option() {
    printf '%s: unrecognized option %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                unrecognized_option "$1"
                exit 2
                ;;
            *)
                unrecognized_option "$1"
                exit 2
                ;;
        esac
    done
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        printf '%s: %s not found\n' "$PROGNAME" "$1" >&2
        exit 1
    }
}

ensure_dirs() {
    mkdir -p -- "$DIRR" "$DIRW"
}

sample_iotop() {
    iotop -boqqk -n "$SAMPLES" -d "$DELAY" | grep -i Current | grep -iv grep >>"$IOTOP_LOG" || true
}

split_rates() {
    stamp="$(date +%H:%M)"
    tr -s ' ' <"$IOTOP_LOG" | cut -d ' ' -f 4 | sort -ur | head -n 10 |
        grep '[0-9][0-9][0-9][0-9]\.' >"${DIRR}/${stamp}" || true
    tr -s ' ' <"$IOTOP_LOG" | cut -d ' ' -f 10 | sort -ur | head -n 10 |
        grep '[0-9][0-9][0-9][0-9]\.' >"${DIRW}/${stamp}" || true
}

rotate_if_midnight() {
    if [ "$(date +%H%M)" != "0000" ]; then
        return 0
    fi
    archive="$(date +%D%M).tar.gz"
    tar -zcvf "$archive" -- "$DIRR"
    tar -zcvf "$archive" -- "$DIRW"
    : >"$IOTOP_LOG"
}

main() {
    parse_args "$@"
    need_cmd iotop
    need_cmd tar
    ensure_dirs
    sample_iotop
    split_rates
    rotate_if_midnight
}

main "$@"
