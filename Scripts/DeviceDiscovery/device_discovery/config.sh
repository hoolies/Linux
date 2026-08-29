# Global configuration and CLI parsing (sourced, not executed).
# shellcheck disable=SC2034  # globals used across sourced modules

SCRIPT_VERSION=2.0.0

OUTPUT_JSON=0
PHYSICAL_ONLY=0
FULL_DUMP=0
FORCE_POSIX=0
PCI_ALL=0
VERBOSITY=0
NONINTERACTIVE=0

DEVICES_FILE=""
HUMAN_LIST_FILE=""
PATH_CACHE_FILE=""
DRIVER_CACHE_FILE=""
BUS_COUNTS_FILE=""
DEVICE_COUNT=0
WIRELESS_IFACES=""

usage() {
    cat <<EOF
Usage: ${PROGNAME:-device_discovery.sh} [OPTION]...
Scan Linux hardware and print a device inventory.

Mandatory arguments to long options are mandatory for short options too.

      --json            print a single JSON document
  -v                    summary plus device names
  -vv                   full diagnostics, then summary and device table
      --physical-only   omit virtual devices
      --full            with -vv, also dump /dev and /sys (implies -vv)
      --pci-all         include PCI bridges and root complexes
      --posix           strict POSIX: verify tools in PATH; no readlink
      --no-prompt       never prompt for sudo
      --version         print version and exit
  -h, --help            display this help and exit
EOF
}

unrecognized_option() {
    printf '%s: unrecognized option %s\n' "${PROGNAME:-device_discovery.sh}" "$1" >&2
    printf "Try '%s --help' for more information.\n" "${PROGNAME:-device_discovery.sh}" >&2
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --json) OUTPUT_JSON=1 ;;
            -vv) VERBOSITY=2 ;;
            -v)
                VERBOSITY=$((VERBOSITY + 1))
                [ "$VERBOSITY" -gt 2 ] && VERBOSITY=2
                ;;
            --physical-only) PHYSICAL_ONLY=1 ;;
            --full)
                FULL_DUMP=1
                VERBOSITY=2
                ;;
            --posix) FORCE_POSIX=1 ;;
            --pci-all) PCI_ALL=1 ;;
            --no-prompt) NONINTERACTIVE=1 ;;
            --version)
                printf '%s %s\n' "${PROGNAME:-device_discovery.sh}" "$SCRIPT_VERSION"
                exit 0
                ;;
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
        shift
    done
    if [ "$#" -gt 0 ]; then
        unrecognized_option "$1"
        exit 2
    fi
}
