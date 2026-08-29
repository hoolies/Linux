#!/usr/bin/env sh
# brightmod — set the Intel backlight brightness to a value.

set -eu
export LC_ALL=C
unalias -a 2>/dev/null || true
unset -f cat 2>/dev/null || true

readonly PROGNAME="${0##*/}"
readonly BRIGHTNESS_FILE="/sys/class/backlight/intel_backlight/brightness"
readonly MAX_FILE="/sys/class/backlight/intel_backlight/max_brightness"

usage() {
    cat <<EOF
Usage: $PROGNAME [OPTION]... VALUE
Set the Intel backlight brightness to VALUE.

Mandatory arguments to long options are mandatory for short options too.

  -h, --help            display this help and exit

VALUE is written to $BRIGHTNESS_FILE.
Needs write access to that sysfs file (usually root).
EOF
}

unrecognized_option() {
    printf '%s: unrecognized option %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

missing_operand() {
    printf '%s: missing operand\n' "$PROGNAME" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

extra_operand() {
    printf '%s: extra operand %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

invalid_value() {
    printf '%s: invalid brightness %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

parse_args() {
    VALUE=""
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
                break
                ;;
        esac
    done
    if [ "$#" -lt 1 ]; then
        missing_operand
        exit 2
    fi
    if [ "$#" -gt 1 ]; then
        extra_operand "$2"
        exit 2
    fi
    VALUE="$1"
}

require_sysfs() {
    if [ ! -f "$BRIGHTNESS_FILE" ]; then
        printf '%s: %s not found\n' "$PROGNAME" "$BRIGHTNESS_FILE" >&2
        exit 1
    fi
}

clamp_value() {
    case "$VALUE" in
        '' | *[!0-9]*)
            invalid_value "$VALUE"
            exit 2
            ;;
    esac
    if [ -f "$MAX_FILE" ]; then
        max="$(cat -- "$MAX_FILE")"
        if [ "$VALUE" -gt "$max" ]; then
            VALUE="$max"
        fi
    fi
}

set_brightness() {
    printf '%s\n' "$VALUE" >"$BRIGHTNESS_FILE"
}

main() {
    parse_args "$@"
    require_sysfs
    clamp_value
    set_brightness
}

main "$@"
