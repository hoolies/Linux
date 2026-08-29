#!/usr/bin/env bash
# ip_dns_check — ping IPs and show reverse DNS.

set -euo pipefail
export LC_ALL=C
unalias -a 2>/dev/null || true
unset -f ping dig printf 2>/dev/null || true

readonly PROGNAME="${0##*/}"

usage() {
    cat <<EOF
Usage: $PROGNAME [OPTION]... [IP]...
Ping each IP and print its reverse DNS name.

Mandatory arguments to long options are mandatory for short options too.

  -h, --help            display this help and exit

With no IP operands, read addresses from stdin (one per line) until
a line containing only stop.
EOF
}

unrecognized_option() {
    printf '%s: unrecognized option %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

parse_args() {
    IPS=()
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            --)
                shift
                while [ "$#" -gt 0 ]; do
                    IPS+=("$1")
                    shift
                done
                return 0
                ;;
            -*)
                unrecognized_option "$1"
                exit 2
                ;;
            *)
                IPS+=("$1")
                shift
                ;;
        esac
    done
}

check_ip() {
    local ip="$1"
    local octet0 octet1 octet2 octet3 rest

    case "$ip" in
        *[!0-9.]* | '' | .* | *. | *..*)
            return 1
            ;;
    esac
    octet0="${ip%%.*}"
    rest="${ip#*.}"
    octet1="${rest%%.*}"
    rest="${rest#*.}"
    octet2="${rest%%.*}"
    octet3="${rest#*.}"
    case "$octet3" in
        *.*)
            return 1
            ;;
    esac
    [ -n "$octet0" ] && [ -n "$octet1" ] && [ -n "$octet2" ] && [ -n "$octet3" ] || return 1
    [ "$octet0" -le 255 ] && [ "$octet1" -le 255 ] && [ "$octet2" -le 255 ] && [ "$octet3" -le 255 ]
}

read_ip_addresses() {
    local line
    while IFS= read -r line; do
        if [ "$line" = "stop" ]; then
            break
        fi
        if [ -z "$line" ]; then
            continue
        fi
        if check_ip "$line"; then
            printf '%s\n' "$line"
        fi
    done
}

report_ip() {
    local ip="$1"
    local pong dns
    if ping -c 2 -W 2 "$ip" >/dev/null 2>&1; then
        pong="$ip UP"
    else
        pong="$ip DOWN"
    fi
    dns="$(dig -x "$ip" +short 2>/dev/null || true)"
    if [ -z "$dns" ]; then
        dns="No DNS record found"
    fi
    printf 'IP: %s DNS: %s\n' "$pong" "$dns"
}

main() {
    local ip
    parse_args "$@"
    if [ "${#IPS[@]}" -eq 0 ]; then
        if [ -t 0 ]; then
            printf 'Enter IP addresses (one per line, type stop to finish):\n' >&2
        fi
        while IFS= read -r ip; do
            report_ip "$ip"
        done < <(read_ip_addresses)
        return 0
    fi
    for ip in "${IPS[@]}"; do
        if ! check_ip "$ip"; then
            printf '%s: invalid IP address %s\n' "$PROGNAME" "$ip" >&2
            exit 2
        fi
        report_ip "$ip"
    done
}

main "$@"
