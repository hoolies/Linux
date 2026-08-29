#!/usr/bin/env bash
# party — cycle the terminal text cursor through a generated hue wheel.

set -euo pipefail
export LC_ALL=C
unalias -a 2>/dev/null || true
unset -f sleep cat 2>/dev/null || true

readonly PROGNAME="${0##*/}"
readonly TTY=/dev/tty
readonly RGB_MAX=4095
readonly STEPS=150
readonly DEFAULT_DELAY=0.03

usage() {
    cat <<EOF
Usage: $PROGNAME [OPTION]...
Cycle the terminal text cursor through a generated hue wheel.

Mandatory arguments to long options are mandatory for short options too.

  -d, --delay=SECONDS   wait SECONDS between color steps (default $DEFAULT_DELAY)
  -h, --help            display this help and exit
EOF
}

unrecognized_option() {
    printf '%s: unrecognized option %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

option_requires_argument() {
    printf '%s: option requires an argument -- %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

extra_operand() {
    printf '%s: extra operand %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

invalid_delay() {
    printf '%s: invalid delay %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

parse_args() {
    DELAY="$DEFAULT_DELAY"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            -d)
                if [ "$#" -lt 2 ]; then
                    option_requires_argument "$1"
                    exit 2
                fi
                DELAY="$2"
                shift 2
                ;;
            --delay)
                if [ "$#" -lt 2 ]; then
                    option_requires_argument "$1"
                    exit 2
                fi
                DELAY="$2"
                shift 2
                ;;
            --delay=*)
                DELAY="${1#--delay=}"
                shift
                ;;
            -d*)
                DELAY="${1#-d}"
                shift
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
                extra_operand "$1"
                exit 2
                ;;
        esac
    done
    if [ "$#" -gt 0 ]; then
        extra_operand "$1"
        exit 2
    fi
}

validate_delay() {
    case "$DELAY" in
        '' | . | *[!0-9.]* | *.*.*)
            invalid_delay "$DELAY"
            exit 2
            ;;
    esac
    case "$DELAY" in
        *[0-9]*) ;;
        *)
            invalid_delay "$DELAY"
            exit 2
            ;;
    esac
}

require_tty() {
    if ! { printf '' >"$TTY"; } 2>/dev/null; then
        printf '%s: no controlling terminal\n' "$PROGNAME" >&2
        exit 1
    fi
}

honor_no_color() {
    if [ -n "${NO_COLOR:-}" ]; then
        printf '%s: NO_COLOR is set; not changing the cursor\n' "$PROGNAME" >&2
        exit 0
    fi
}

# Hue 0-359, full saturation and value, 12-bit RGB on stdout.
hsv_to_rgb() {
    local h="$1"
    local c x rem dist sector r g b
    c="$RGB_MAX"
    rem=$((h % 60))
    dist=$((rem - 30))
    if [ "$dist" -lt 0 ]; then
        dist=$((-dist))
    fi
    x=$((c * (30 - dist) / 30))
    sector=$((h / 60))
    case "$sector" in
        0)
            r=$c
            g=$x
            b=0
            ;;
        1)
            r=$x
            g=$c
            b=0
            ;;
        2)
            r=0
            g=$c
            b=$x
            ;;
        3)
            r=0
            g=$x
            b=$c
            ;;
        4)
            r=$x
            g=0
            b=$c
            ;;
        *)
            r=$c
            g=0
            b=$x
            ;;
    esac
    printf '%s %s %s' "$r" "$g" "$b"
}

set_cursor_rgb() {
    printf '\033]12;rgb:%03x/%03x/%03x\a' "$1" "$2" "$3" >"$TTY"
}

reset_cursor() {
    printf '\033]112\a' >"$TTY" || true
}

cycle_colors() {
    local i h r g b
    while true; do
        i=0
        while [ "$i" -lt "$STEPS" ]; do
            h=$((i * 360 / STEPS))
            read -r r g b <<<"$(hsv_to_rgb "$h")"
            set_cursor_rgb "$r" "$g" "$b"
            sleep "$DELAY"
            i=$((i + 1))
        done
    done
}

main() {
    parse_args "$@"
    validate_delay
    honor_no_color
    require_tty
    trap reset_cursor EXIT
    trap 'exit 0' INT TERM HUP
    cycle_colors
}

main "$@"
