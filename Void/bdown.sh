#!/usr/bin/env sh
# bdown — lower the Intel backlight brightness.

set -eu
export LC_ALL=C
unalias -a 2>/dev/null || true
unset -f cat 2>/dev/null || true

readonly PROGNAME="${0##*/}"
readonly BRIGHTNESS_FILE="/sys/class/backlight/intel_backlight/brightness"
readonly DEFAULT_STEP=50

usage() {
    cat <<EOF
Usage: $PROGNAME [OPTION]... [STEP]
Lower the Intel backlight brightness by STEP (default $DEFAULT_STEP).

Mandatory arguments to long options are mandatory for short options too.

  -h, --help            display this help and exit

Needs write access to $BRIGHTNESS_FILE.
EOF
}

unrecognized_option() {
    printf '%s: unrecognized option %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

invalid_step() {
    printf '%s: invalid step %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

parse_args() {
    STEP="$DEFAULT_STEP"
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
                STEP="$1"
                shift
                break
                ;;
        esac
    done
    if [ "$#" -gt 0 ]; then
        unrecognized_option "$1"
        exit 2
    fi
}

require_sysfs() {
    if [ ! -f "$BRIGHTNESS_FILE" ]; then
        printf '%s: %s not found\n' "$PROGNAME" "$BRIGHTNESS_FILE" >&2
        exit 1
    fi
}

adjust_brightness() {
    case "$STEP" in
        '' | *[!0-9]*)
            invalid_step "$STEP"
            exit 2
            ;;
    esac
    current="$(cat -- "$BRIGHTNESS_FILE")"
    next=$((current - STEP))
    if [ "$next" -lt 0 ]; then
        next=0
    fi
    printf '%s\n' "$next" >"$BRIGHTNESS_FILE"
}

main() {
    parse_args "$@"
    require_sysfs
    adjust_brightness
}

main "$@"
