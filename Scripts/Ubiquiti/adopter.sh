#!/usr/bin/env sh
# adopter — find factory Ubiquiti devices and point them at a UniFi controller.

set -eu
export LC_ALL=C
unalias -a 2>/dev/null || true
unset -f rm mv cp grep awk sed cat ip nmap ssh sshpass sort tee 2>/dev/null || true

readonly PROGNAME="${0##*/}"
readonly DEFAULT_USER="ubnt"
readonly DEFAULT_PASS="ubnt"
readonly INFORM_PORT="8080"

TEMP_FILES=""

cleanup_temps() {
    printf '%s' "$TEMP_FILES" | while IFS= read -r _f; do
        [ -n "$_f" ] || continue
        rm -f -- "$_f"
    done
}
trap cleanup_temps EXIT

register_temp() {
    TEMP_FILES="${TEMP_FILES}${1}
"
}

make_temp() {
    _t=$(mktemp) || return 1
    register_temp "$_t"
    printf '%s\n' "$_t"
}

usage() {
    cat <<EOF
Usage: $PROGNAME [OPTION]... [CONTROLLER]
Scan the LAN for Ubiquiti devices and adopt them to a UniFi controller.

Mandatory arguments to long options are mandatory for short options too.

  -h, --help            display this help and exit

If CONTROLLER is omitted, the script prompts for the controller IP.
Devices are adopted with the factory ubnt/ubnt account via sshpass.
Needs nmap, ssh, and sshpass.  Run as root or with sudo for nmap.
EOF
}

unrecognized_option() {
    printf '%s: unrecognized option %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

parse_args() {
    CONTROLLER=""
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
                if [ -n "$CONTROLLER" ]; then
                    unrecognized_option "$1"
                    exit 2
                fi
                CONTROLLER="$1"
                shift
                ;;
        esac
    done
    if [ "$#" -gt 0 ]; then
        if [ -n "$CONTROLLER" ]; then
            unrecognized_option "$1"
            exit 2
        fi
        CONTROLLER="$1"
    fi
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        printf '%s: %s not found\n' "$PROGNAME" "$1" >&2
        exit 1
    }
}

list_local_prefixes() {
    ip -o -4 addr show | awk '
        {
            for (i = 1; i <= NF; i++) {
                if ($i == "inet") {
                    split($(i + 1), a, "/")
                    n = split(a[1], o, ".")
                    if (n == 4 && (o[1] == "10" || o[1] == "172" || o[1] == "192")) {
                        print o[1] "." o[2] "." o[3]
                    }
                }
            }
        }
    ' | sort -u
}

run_priv() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

scan_prefix() {
    prefix="$1"
    out="$2"
    printf '%s: scanning %s.0/24 for Ubiquiti devices\n' "$PROGNAME" "$prefix" >&2
    run_priv nmap -sn "${prefix}.0/24" 2>/dev/null | awk '
        /Nmap scan report/ { ip = $NF; gsub(/[()]/, "", ip) }
        /Ubiquiti/ { if (ip != "") print ip }
    ' >>"$out" || true
}

read_controller() {
    if [ -n "$CONTROLLER" ]; then
        return 0
    fi
    if [ ! -t 0 ]; then
        printf '%s: missing controller IP\n' "$PROGNAME" >&2
        printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
        exit 2
    fi
    printf 'Enter the IP of the controller: ' >&2
    IFS= read -r CONTROLLER
    if [ -z "$CONTROLLER" ]; then
        printf '%s: missing controller IP\n' "$PROGNAME" >&2
        exit 2
    fi
}

adopt_device() {
    ip="$1"
    inform="http://${CONTROLLER}:${INFORM_PORT}/inform"
    printf '%s: adopting %s\n' "$PROGNAME" "$ip" >&2
    sshpass -p "$DEFAULT_PASS" ssh -o StrictHostKeyChecking=no \
        "${DEFAULT_USER}@${ip}" set-inform "$inform" ||
        printf '%s: failed to adopt %s\n' "$PROGNAME" "$ip" >&2
}

main() {
    parse_args "$@"
    need_cmd ip
    need_cmd nmap
    need_cmd ssh
    need_cmd sshpass
    need_cmd awk
    devices="$(make_temp)"
    prefixes="$(list_local_prefixes)"
    if [ -z "$prefixes" ]; then
        printf '%s: no private IPv4 prefixes found\n' "$PROGNAME" >&2
        exit 1
    fi
    for prefix in $prefixes; do
        scan_prefix "$prefix" "$devices"
    done
    if [ ! -s "$devices" ]; then
        printf '%s: no Ubiquiti devices found\n' "$PROGNAME" >&2
        exit 1
    fi
    printf '%s: devices found:\n' "$PROGNAME" >&2
    sort -u -- "$devices" >&2
    read_controller
    printf '%s: controller %s\n' "$PROGNAME" "$CONTROLLER" >&2
    sort -u -- "$devices" | while IFS= read -r ip; do
        [ -n "$ip" ] || continue
        adopt_device "$ip"
    done
}

main "$@"
