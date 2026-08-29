#!/usr/bin/env sh
# console — open an interactive serial console on a device.

set -eu
export LC_ALL=C
unalias -a 2>/dev/null || true
unset -f stty cat kill printf 2>/dev/null || true

readonly PROGNAME="${0##*/}"

usage() {
    cat <<EOF
Usage: $PROGNAME [OPTION]... DEVICE SPEED STOPBITS PARITY
Open an interactive serial console on DEVICE.

Mandatory arguments to long options are mandatory for short options too.

  -h, --help            display this help and exit

STOPBITS is 1 or 2.  PARITY is even or odd.
Type exit on a line by itself to close the console.
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

invalid_stopbits() {
    printf '%s: invalid stop bits %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

invalid_parity() {
    printf '%s: invalid parity %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

parse_args() {
    DEVICE=""
    SPEED=""
    STOPBITS=""
    PARITY=""
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
    if [ "$#" -lt 4 ]; then
        missing_operand
        exit 2
    fi
    if [ "$#" -gt 4 ]; then
        extra_operand "$5"
        exit 2
    fi
    DEVICE="$1"
    SPEED="$2"
    STOPBITS="$3"
    PARITY="$4"
}

validate_serial_args() {
    case "$STOPBITS" in
        1 | 2) ;;
        *)
            invalid_stopbits "$STOPBITS"
            exit 2
            ;;
    esac
    case "$PARITY" in
        even | odd) ;;
        *)
            invalid_parity "$PARITY"
            exit 2
            ;;
    esac
}

stopbits_flag() {
    case "$1" in
        1) printf '%s' "-cstopb" ;;
        2) printf '%s' "cstopb" ;;
    esac
}

parity_flag() {
    case "$1" in
        even) printf '%s' "-parodd" ;;
        odd) printf '%s' "parodd" ;;
    esac
}

configure_device() {
    stopb="$1"
    par="$2"
    printf 'stty -F %s %s %s %s\n' "$DEVICE" "$SPEED" "$stopb" "$par"
    if ! stty -F "$DEVICE" "$SPEED" "$stopb" "$par" -icrnl; then
        printf '%s: stty failed on %s\n' "$PROGNAME" "$DEVICE" >&2
        exit 1
    fi
}

stop_reader() {
    if [ -n "${BG_PID:-}" ]; then
        kill "$BG_PID" 2>/dev/null || true
        BG_PID=""
    fi
}

run_console() {
    cat -v -- "$DEVICE" &
    BG_PID="$!"
    trap stop_reader EXIT INT TERM HUP
    cmd=""
    while [ "$cmd" != "exit" ]; do
        if ! IFS= read -r cmd; then
            break
        fi
        if [ "$cmd" = "exit" ]; then
            break
        fi
        printf '\010%s\015' "$cmd" >"$DEVICE"
    done
    stop_reader
    trap - EXIT INT TERM HUP
}

main() {
    parse_args "$@"
    validate_serial_args
    stopb="$(stopbits_flag "$STOPBITS")"
    par="$(parity_flag "$PARITY")"
    configure_device "$stopb" "$par"
    run_console
}

main "$@"
