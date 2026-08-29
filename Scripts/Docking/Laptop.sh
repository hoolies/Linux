#!/usr/bin/env sh
# Laptop — enable only the laptop panel and refresh the wallpaper.

set -eu
export LC_ALL=C
unalias -a 2>/dev/null || true
unset -f xrandr pkill nitrogen conky 2>/dev/null || true

readonly PROGNAME="${0##*/}"
readonly CONKY_CONFIG="${HOME}/.config/conky/conky.config"

usage() {
    cat <<EOF
Usage: $PROGNAME [OPTION]...
Turn off dock outputs and use the laptop screen only.

Mandatory arguments to long options are mandatory for short options too.

  -h, --help            display this help and exit

Also restarts nitrogen and conky after the layout change.
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

apply_layout() {
    xrandr \
        --output eDP-1 --primary --mode 1920x1080 --pos 0x0 --rotate normal \
        --output DP-1 --off \
        --output HDMI-1 --off \
        --output DP-2 --off \
        --output HDMI-2 --off \
        --output DP-1-1 --off \
        --output DP-1-2 --off \
        --output DP-1-3 --off
}

restart_desktop() {
    pkill conky 2>/dev/null || true
    pkill nitrogen 2>/dev/null || true
    nitrogen --restore || true
    if [ -f "$CONKY_CONFIG" ]; then
        conky -c "$CONKY_CONFIG" >/dev/null 2>&1 || true
    fi
}

main() {
    parse_args "$@"
    apply_layout
    restart_desktop
}

main "$@"
