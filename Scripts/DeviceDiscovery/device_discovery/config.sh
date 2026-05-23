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

print_help() {
    cat <<'EOF'
Device Discovery — Linux hardware and connection inventory

Modular scan under device_discovery/collectors/ (one module per bus/type).
Single-file edition: device_discovery.monolithic.sh (same behavior).
Scans sysfs, /dev, and optional system tools. Results go to stdout.

USAGE
  device_discovery.sh [OPTIONS]

OPTIONS
  -h, --help       Show this help and exit.
  --version        Print version and exit.
  --no-prompt      Never prompt for sudo (CI, pipes, --json).
  --json           Single JSON document (meta, devices, summary).
  -v               Summary plus device names.
  -vv              Full diagnostics, then summary and device table.
  --physical-only  Omit virtual devices (docker, loopback, vcan, etc.).
  --full           With -vv: deep /dev and /sys listings (implies -vv).
  --pci-all        Include PCI bridges and root complexes (default skips them).
  --posix          Strict POSIX: verify tools in PATH; no readlink.

STABLE IDs
  Each device id is derived from bus + sysfs path (or name), so ids are stable
  across runs on the same machine (e.g. pci__bus_pci_devices_0000_00_14_0).

EXAMPLES
  device_discovery.sh
  device_discovery.sh -v
  device_discovery.sh --json --no-prompt > devices.json
  device_discovery.sh --pci-all -vv
  sudo device_discovery.sh -vv --full

EXIT STATUS
  0 success  1 usage error  127 missing required binary in PATH
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) OUTPUT_JSON=1 ;;
            -vv) VERBOSITY=2 ;;
            -v)
                VERBOSITY=$((VERBOSITY + 1))
                [ "$VERBOSITY" -gt 2 ] && VERBOSITY=2
                ;;
            --physical-only) PHYSICAL_ONLY=1 ;;
            --full) FULL_DUMP=1; VERBOSITY=2 ;;
            --posix) FORCE_POSIX=1 ;;
            --pci-all) PCI_ALL=1 ;;
            --no-prompt) NONINTERACTIVE=1 ;;
            --version)
                echo "device_discovery.sh ${SCRIPT_VERSION}"
                exit 0
                ;;
            -h|--help)
                print_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Try: device_discovery.sh --help" >&2
                exit 1
                ;;
        esac
        shift
    done
}
