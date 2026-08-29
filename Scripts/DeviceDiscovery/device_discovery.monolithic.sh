#!/usr/bin/env sh
# Device Discovery — monolithic single-file (generated from device_discovery/)
# Regenerate: device_discovery/tools/build-monolithic.sh

set -eu
export LC_ALL=C
unalias -a 2>/dev/null || true
SCRIPT_VERSION=2.0.0-monolithic
PROGNAME=${0##*/}
DD_ENTRY=${0:-device_discovery.monolithic.sh}

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

# Return 0 if any glob expands to at least one directory.
glob_has_dirs() {
    for _glob in "$@"; do
        for _entry in $_glob; do
            if [ -d "$_entry" ]; then
                return 0
            fi
        done
    done
    return 1
}

sanitize_field() {
    printf '%s' "$1" | tr '\t\n\r' '   '
}

print_section() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0
    [ "$VERBOSITY" -lt 2 ] && return 0
    printf '\n'
    printf '%s\n' "-------------------------------------"
    printf '%s\n' "$1"
    printf '%s\n' "-------------------------------------"
    return 0
}

print_note() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0
    [ "$VERBOSITY" -lt 2 ] && return 0
    printf '%s\n' "$1"
    return 0
}

print_block() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0
    [ "$VERBOSITY" -lt 2 ] && return 0
    printf '%s\n' "$1"
    return 0
}

utc_timestamp() {
    _saved_tz=${TZ-}
    TZ=UTC
    export TZ
    date '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date
    if [ -n "$_saved_tz" ]; then
        TZ=$_saved_tz
        export TZ
    else
        unset TZ
    fi
}

json_bool() {
    if [ "$1" -eq 1 ]; then
        printf 'true'
    else
        printf 'false'
    fi
}

_json_esc_one() {
    printf '%s' "$1" | sed '
        s/\\/\\\\/g
        s/"/\\"/g
        s/	/\\t/g
        s/\r/\\r/g
        s/\n/\\n/g
    '
}

json_object() {
    _out=""
    _sep=""
    while [ $# -ge 2 ]; do
        _key=$1
        _val=$2
        shift 2
        _jk=$(_json_esc_one "$_key")
        _jv=$(_json_esc_one "$_val")
        _out="${_out}${_sep}\"${_jk}\":\"${_jv}\""
        _sep=","
    done
    printf '{%s}' "$_out"
}

_path_probe() {
    _name=$1
    (
        IFS=:
        # shellcheck disable=SC2248
        for _dir in ${PATH:-/usr/bin:/bin}; do
            [ -n "$_dir" ] || continue
            if [ -x "$_dir/$_name" ]; then
                exit 0
            fi
        done
        exit 1
    )
}

init_path_cache() {
    : >"$PATH_CACHE_FILE" || exit 1
    for _bin in \
        mktemp lsusb udevadm readlink iw iwconfig dmesg bluetoothctl mmcli setserial iscsiadm sudo \
        hciconfig rfkill nmcli ip ifconfig bridge lspci resolvectl lsblk \
        boltctl xrandr aplay mtp-detect lsmod cut \
        head grep tail find ls sh bash cat nc timeout \
        awk sed tr wc basename date hostname uname whoami id; do
        if _path_probe "$_bin"; then
            printf '%s=1\n' "$_bin" >>"$PATH_CACHE_FILE"
        else
            printf '%s=0\n' "$_bin" >>"$PATH_CACHE_FILE"
        fi
    done
}

path_has_binary() {
    _name=$1
    if [ -f "$PATH_CACHE_FILE" ]; then
        _hit=$(awk -F= -v k="$_name" '$1 == k { print $2; exit }' "$PATH_CACHE_FILE" 2>/dev/null)
        case "$_hit" in
            1) return 0 ;;
            0) return 1 ;;
        esac
    fi
    if _path_probe "$_name"; then
        if [ -f "$PATH_CACHE_FILE" ]; then
            printf '%s=1\n' "$_name" >>"$PATH_CACHE_FILE"
        fi
        return 0
    fi
    if [ -f "$PATH_CACHE_FILE" ]; then
        printf '%s=0\n' "$_name" >>"$PATH_CACHE_FILE"
    fi
    return 1
}

require_binary() {
    if path_has_binary "$1"; then
        return 0
    fi
    printf '%s\n' "Error: required binary is not installed in PATH: $1" >&2
    exit 127
}

require_binary_one_of() {
    for _candidate in "$@"; do
        if path_has_binary "$_candidate"; then
            return 0
        fi
    done
    _needed=""
    for _candidate in "$@"; do
        _needed="${_needed}${_needed:+ }${_candidate}"
    done
    printf '%s\n' "Error: required binary is not installed in PATH (need one of): ${_needed}" >&2
    exit 127
}

diagnostics_enabled() {
    [ "$VERBOSITY" -ge 2 ]
}

run_diagnostic() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0
    diagnostics_enabled || return 0
    "$@" 2>/dev/null
}

run_cmd() {
    _bin=$1
    shift
    diagnostics_enabled || return 0
    require_binary "$_bin"
    run_diagnostic "$_bin" "$@"
}

run_sh_checked() {
    _script=$1
    shift
    diagnostics_enabled || return 0
    require_binary sh
    while [ $# -gt 0 ]; do
        require_binary "$1"
        shift
    done
    run_diagnostic sh -c "$_script"
}

require_core_utilities() {
    for _tool in awk sed find cat tr wc basename date hostname uname whoami id tail cut; do
        require_binary "$_tool"
    done
}

enforce_posix_mode() {
    for _tool in ls head grep tail; do
        require_binary "$_tool"
    done
    require_binary lsusb
    require_binary ip
    require_binary_one_of iw iwconfig
    if [ "$OUTPUT_JSON" -eq 0 ] && [ "$VERBOSITY" -ge 2 ]; then
        require_binary udevadm
    fi
}

sysfs_read() {
    f=$1
    if [ -f "$f" ]; then
        cat "$f" 2>/dev/null | tr -d '\n'
    fi
}

read_symlink_target() {
    _path=$1
    if [ "$FORCE_POSIX" -eq 0 ] && path_has_binary readlink; then
        _target=$(readlink "$_path" 2>/dev/null)
        if [ -n "$_target" ]; then
            printf '%s' "$_target"
            return 0
        fi
    fi
    if ! path_has_binary ls; then
        return 0
    fi
    _line=$(ls -ld "$_path" 2>/dev/null) || return 0
    case "$_line" in
        *" -> "*) printf '%s' "${_line#* -> }" ;;
    esac
}

driver_name_for_sysfs() {
    _devpath=$1
    [ -n "$_devpath" ] || return 0
    if [ -f "$DRIVER_CACHE_FILE" ]; then
        _driver=$(awk -F '\t' -v p="$_devpath" '$1 == p { print $2; exit }' "$DRIVER_CACHE_FILE" 2>/dev/null)
        if [ -n "$_driver" ]; then
            printf '%s' "$_driver"
            return 0
        fi
    fi
    _driver=""
    _driver_link=${_devpath}/driver
    if [ -L "$_driver_link" ]; then
        _target=$(read_symlink_target "$_driver_link")
        _driver=${_target##*/}
    fi
    printf '%s\t%s\n' "$_devpath" "$_driver" >>"$DRIVER_CACHE_FILE"
    printf '%s' "$_driver"
}

# Stable id: bus + slug from sysfs path or name.
stable_device_id() {
    _bus=$1
    _path=$2
    _name=$3
    if [ -n "$_path" ]; then
        _slug=$(printf '%s' "$_path" | sed 's|^/sys/||; s|/|_|g; s|\.|_|g; s|_|_|g')
    else
        _slug=$(printf '%s' "$_name" | sed 's|/|_|g; s|\.|_|g')
    fi
    printf '%s__%s' "$_bus" "$_slug"
}

pci_is_bridge_class() {
    _class=$1
    case "$_class" in
        0x0604* | 0x060000 | 0x060100) return 0 ;;
    esac
    return 1
}

should_skip_pci_device() {
    _class=$1
    if [ "$PCI_ALL" -eq 1 ]; then
        return 1
    fi
    if pci_is_bridge_class "$_class"; then
        return 0
    fi
    return 1
}

# Return 0 if $1 looks like a safe host literal for connect probes.
tcp_probe_valid_host() {
    _host=$1
    [ -n "$_host" ] || return 1
    case "$_host" in
        *[!a-zA-Z0-9.:\[\]-]*) return 1 ;;
    esac
    return 0
}

# Return 0 if $1 is a decimal TCP port in range.
tcp_probe_valid_port() {
    _port=$1
    case "$_port" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ "$_port" -ge 1 ] 2>/dev/null && [ "$_port" -le 65535 ]
}

# Print probe backend: nc, bash, or nothing.
tcp_port_probe_backend() {
    if path_has_binary nc; then
        printf '%s' nc
        return 0
    fi
    if path_has_binary bash; then
        printf '%s' bash
        return 0
    fi
    return 1
}

# Bash /dev/tcp connect probe; host and port must already be validated.
_tcp_port_open_bash() {
    _host=$1
    _port=$2
    _timeout=$3
    DD_TCP_HOST=$_host DD_TCP_PORT=$_port
    export DD_TCP_HOST DD_TCP_PORT
    if path_has_binary timeout; then
        # shellcheck disable=SC2016
        timeout "$_timeout" bash -c 'true >"/dev/tcp/${DD_TCP_HOST}/${DD_TCP_PORT}"' \
            >/dev/null 2>&1
        return $?
    fi
    # shellcheck disable=SC2016
    bash -c 'true >"/dev/tcp/${DD_TCP_HOST}/${DD_TCP_PORT}"' >/dev/null 2>&1
}

# Return 0 if host:port accepts TCP, 1 if not, 2 if args invalid, 127 if no backend.
tcp_port_open() {
    _host=$1
    _port=$2
    _timeout=${3:-2}

    tcp_probe_valid_host "$_host" || return 2
    tcp_probe_valid_port "$_port" || return 2

    if path_has_binary nc; then
        if path_has_binary timeout; then
            timeout "$_timeout" nc -z "$_host" "$_port" >/dev/null 2>&1
        else
            nc -z -w "$_timeout" "$_host" "$_port" >/dev/null 2>&1
        fi
        return $?
    fi

    if path_has_binary bash; then
        _tcp_port_open_bash "$_host" "$_port" "$_timeout"
        return $?
    fi

    return 127
}

build_wireless_iface_cache() {
    WIRELESS_IFACES=""
    if [ ! -d /sys/class/ieee80211 ]; then
        return 0
    fi
    for phy in /sys/class/ieee80211/*; do
        [ -d "$phy" ] || continue
        for _net in "$phy"/device/net/*; do
            [ -d "$_net" ] || continue
            _iface=$(basename "$_net")
            case " ${WIRELESS_IFACES} " in
                *" ${_iface} "*) ;;
                *) WIRELESS_IFACES="${WIRELESS_IFACES} ${_iface}" ;;
            esac
        done
    done
    for _net in /sys/class/net/*; do
        [ -L "${_net}/phy80211" ] || continue
        _iface=$(basename "$_net")
        case " ${WIRELESS_IFACES} " in
            *" ${_iface} "*) ;;
            *) WIRELESS_IFACES="${WIRELESS_IFACES} ${_iface}" ;;
        esac
    done
}

iface_is_wireless() {
    _iface=$1
    case " ${WIRELESS_IFACES} " in
        *" ${_iface} "*) return 0 ;;
    esac
    return 1
}

net_iface_kind() {
    iface=$1
    netpath="/sys/class/net/${iface}"

    case "$iface" in
        lo)
            printf '%s' virtual
            return
            ;;
        docker* | veth* | virbr* | kube-* | flannel* | cali* | cni* | podman*)
            printf '%s' virtual
            return
            ;;
        tun* | tap* | wg* | tailscale* | ts* | nordlynx* | ppp*)
            printf '%s' tunnel
            return
            ;;
    esac

    if [ -d "${netpath}/bridge" ] || [ -f "${netpath}/bridge_id" ]; then
        printf '%s' bridge
        return
    fi

    if [ -d "/proc/net/bonding/${iface}" ] 2>/dev/null; then
        printf '%s' bond
        return
    fi

    case "$iface" in
        bond*)
            printf '%s' bond
            return
            ;;
        br-*)
            printf '%s' bridge
            return
            ;;
        *@* | *.vlan* | vlan*)
            printf '%s' vlan
            return
            ;;
        can* | vcan*)
            printf '%s' physical
            return
            ;;
    esac

    if iface_is_wireless "$iface"; then
        printf '%s' wireless
        return
    fi

    if diagnostics_enabled && path_has_binary iw; then
        if iw dev "$iface" info >/dev/null 2>&1; then
            printf '%s' wireless
            return
        fi
    fi

    if [ -L "${netpath}/device" ]; then
        printf '%s' physical
        return
    fi

    printf '%s' virtual
}

should_include_kind() {
    kind=$1
    if [ "$PHYSICAL_ONLY" -eq 0 ]; then
        return 0
    fi
    case "$kind" in
        physical | wireless) return 0 ;;
        *) return 1 ;;
    esac
}

# Return 0 if this stable id was already recorded.
seen_device_id() {
    _id=$1
    [ -f "$SEEN_IDS_FILE" ] || return 1
    grep -Fxq "$_id" "$SEEN_IDS_FILE" 2>/dev/null
}

remember_device_id() {
    printf '%s\n' "$1" >>"$SEEN_IDS_FILE"
}

add_device() {
    bus=$1
    kind=$2
    name=$3
    path=${4:-}
    driver=${5:-}
    vendor=${6:-}
    product=${7:-}
    serial=${8:-}
    state=${9:-}
    details='{}'
    if [ $# -gt 9 ]; then
        shift 9
        details=$1
    fi
    case $details in
        \{*) ;;
        *) details='{}' ;;
    esac

    if ! should_include_kind "$kind"; then
        return 0
    fi

    id=$(stable_device_id "$bus" "$path" "$name")
    if seen_device_id "$id"; then
        return 0
    fi
    remember_device_id "$id"

    DEVICE_COUNT=$((DEVICE_COUNT + 1))

    printf '    {"id":"%s","bus":"%s","kind":"%s","name":"%s","path":"%s","driver":"%s","vendor":"%s","product":"%s","serial":"%s","state":"%s","details":%s}\n' \
        "$(_json_esc_one "$id")" \
        "$(_json_esc_one "$bus")" \
        "$(_json_esc_one "$kind")" \
        "$(_json_esc_one "$name")" \
        "$(_json_esc_one "$path")" \
        "$(_json_esc_one "$driver")" \
        "$(_json_esc_one "$vendor")" \
        "$(_json_esc_one "$product")" \
        "$(_json_esc_one "$serial")" \
        "$(_json_esc_one "$state")" \
        "$details" >>"$DEVICES_FILE"

    if [ -n "$BUS_COUNTS_FILE" ]; then
        printf '%s\n' "$bus" >>"$BUS_COUNTS_FILE"
    fi

    if [ "$OUTPUT_JSON" -eq 0 ] && [ -n "$HUMAN_LIST_FILE" ]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$(sanitize_field "$bus")" \
            "$(sanitize_field "$kind")" \
            "$(sanitize_field "$name")" \
            "$(sanitize_field "$path")" \
            "$(sanitize_field "$driver")" \
            "$(sanitize_field "$vendor")" \
            "$(sanitize_field "$product")" \
            "$(sanitize_field "$serial")" \
            "$(sanitize_field "$state")" >>"$HUMAN_LIST_FILE"
    fi
}

print_nonroot_notice() {
    _fd=$1
    {
        printf '%s\n' "NOTICE: Not running as root — some checks may be incomplete."
        printf '\n'
        if path_has_binary dmesg; then
            printf '%s\n' "  - dmesg              kernel ring buffer"
        fi
        if path_has_binary bluetoothctl; then
            printf '%s\n' "  - bluetoothctl       paired devices"
        fi
        if path_has_binary mmcli; then
            printf '%s\n' "  - mmcli              cellular modems"
        fi
        if path_has_binary udevadm; then
            printf '%s\n' "  - udevadm            restricted device attributes"
        fi
        if path_has_binary iscsiadm; then
            printf '%s\n' "  - iscsiadm           iSCSI sessions"
        fi
        printf '\n'
    } >&"$_fd"
}

check_privileges() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi

    if [ "$OUTPUT_JSON" -eq 1 ]; then
        print_nonroot_notice 2
    else
        print_nonroot_notice 1
    fi

    if [ "$NONINTERACTIVE" -eq 1 ] || [ ! -t 0 ] || [ ! -t 1 ]; then
        if [ "$OUTPUT_JSON" -eq 1 ]; then
            printf '%s\n' "Continuing without sudo (non-interactive)." >&2
        else
            printf '%s\n' "Continuing without sudo (non-interactive)."
        fi
        return 0
    fi

    if [ "$OUTPUT_JSON" -eq 1 ]; then
        printf "Re-run with sudo for full output? (y/n): " >&2
    else
        printf "Re-run with sudo for full output? (y/n): "
    fi
    IFS= read -r _response
    printf '\n'
    case "$_response" in
        [Yy]*)
            require_binary sudo
            exec sudo "$DD_ENTRY" "$@"
            ;;
        *)
            if [ "$OUTPUT_JSON" -eq 1 ]; then
                printf '%s\n' "Continuing without sudo." >&2
            else
                printf '%s\n' "Continuing without sudo."
            fi
            ;;
    esac
}

count_dir_entries() {
    _dir=$1
    _count=0
    if [ ! -d "$_dir" ]; then
        printf '0'
        return 0
    fi
    for _entry in "$_dir"/*; do
        if [ -e "$_entry" ] || [ -L "$_entry" ]; then
            _count=$((_count + 1))
        fi
    done
    printf '%s' "$_count"
}

list_dir_long() {
    _dir=$1
    _max=$2
    require_binary find
    require_binary ls
    [ -d "$_dir" ] || return 0
    if [ -n "$_max" ] && [ "$_max" -gt 0 ]; then
        require_binary head
        find "$_dir" -mindepth 1 -maxdepth 1 -exec ls -ld {} + 2>/dev/null | head -n "$_max"
    else
        find "$_dir" -mindepth 1 -maxdepth 1 -exec ls -ld {} + 2>/dev/null
    fi
}

list_dir_names() {
    _dir=$1
    require_binary find
    require_binary basename
    [ -d "$_dir" ] || return 0
    find "$_dir" -mindepth 1 -maxdepth 1 2>/dev/null | while IFS= read -r _path; do
        print_block "  $(basename "$_path")"
    done
}

SEEN_IDS_FILE=""

make_temp_file() {
    _prefix=$1
    _file=""
    if path_has_binary mktemp; then
        _file=$(mktemp "${TMPDIR:-/tmp}/${_prefix}.XXXXXX" 2>/dev/null) || _file=""
    fi
    if [ -z "$_file" ]; then
        _file="${TMPDIR:-/tmp}/${_prefix}.$$"
    fi
    printf '%s' "$_file"
}

init_scan_temp_files() {
    DEVICES_FILE=$(make_temp_file device_discovery)
    BUS_COUNTS_FILE=$(make_temp_file device_discovery_bus)
    DRIVER_CACHE_FILE=$(make_temp_file device_discovery_drv)
    PATH_CACHE_FILE=$(make_temp_file device_discovery_path)
    SEEN_IDS_FILE=$(make_temp_file device_discovery_seen)

    [ -n "$DEVICES_FILE" ] || exit 1
    : >"$DEVICES_FILE" || exit 1
    : >"$BUS_COUNTS_FILE" || exit 1
    : >"$DRIVER_CACHE_FILE" || exit 1
    : >"$SEEN_IDS_FILE" || exit 1

    if [ "$OUTPUT_JSON" -eq 0 ]; then
        HUMAN_LIST_FILE=$(make_temp_file device_discovery_list)
        : >"$HUMAN_LIST_FILE" || exit 1
    else
        HUMAN_LIST_FILE=""
    fi
}

_cleanup_temp_files() {
    rm -f "$DEVICES_FILE" "$PATH_CACHE_FILE" "$BUS_COUNTS_FILE" \
        "$DRIVER_CACHE_FILE" "$SEEN_IDS_FILE"
    if [ -n "$HUMAN_LIST_FILE" ]; then
        rm -f "$HUMAN_LIST_FILE"
    fi
}

collect_audio() {
    glob_has_dirs /sys/class/sound/card* || return 0
    print_section "AUDIO"
    for snd in /sys/class/sound/card*; do
        [ -d "$snd" ] || continue
        card=$(basename "$snd")
        id=$(sysfs_read "$snd/id")
        add_device audio physical "$card" "$snd" "" "" "$id" "" "" "{}"
    done
    if path_has_binary aplay; then
        run_cmd aplay -l
    fi
    run_sh_checked 'ls -l /dev/snd/* 2>/dev/null | head -15' ls head
    print_block ""
}

collect_bluetooth() {
    print_section "BLUETOOTH DEVICES"

    if path_has_binary hciconfig; then
        run_cmd hciconfig -a
        print_block ""
    fi

    if path_has_binary bluetoothctl; then
        run_sh_checked "printf 'devices\n' | bluetoothctl" bluetoothctl
        print_block ""
    fi

    for bt in /sys/class/bluetooth/*; do
        [ -d "$bt" ] || continue
        name=$(basename "$bt")
        address=$(sysfs_read "$bt/address")
        btname=$(sysfs_read "$bt/name")
        driver=$(driver_name_for_sysfs "$bt")
        details=$(json_object address "$address")
        add_device bluetooth physical "$name" "$bt" "$driver" "" "$btname" "" "" "$details"
    done

    if path_has_binary rfkill; then
        run_cmd rfkill list
    fi
    run_sh_checked 'ls -l /dev/rfcomm* 2>/dev/null' ls
    print_block ""
}

collect_camera() {
    glob_has_dirs /sys/class/video4linux/* || return 0
    print_section "CAMERAS (V4L)"
    for video in /sys/class/video4linux/*; do
        [ -d "$video" ] || continue
        name=$(basename "$video")
        vname=$(sysfs_read "$video/name")
        add_device camera physical "$name" "$video" "" "" "$vname" "" "" "{}"
        print_block "  $name: $vname"
    done
    print_block ""
}

collect_can() {
    glob_has_dirs /sys/class/net/can* /sys/class/net/vcan* || return 0

    print_section "CAN BUS"
    if path_has_binary ip; then
        run_sh_checked 'ip -d link show type can 2>/dev/null || true' ip
    fi
    for can in /sys/class/net/can* /sys/class/net/vcan*; do
        [ -d "$can" ] || continue
        name=$(basename "$can")
        operstate=$(sysfs_read "$can/operstate")
        _kind=physical
        case "$name" in
            vcan*) _kind=virtual ;;
        esac
        if ! should_include_kind "$_kind"; then
            continue
        fi
        add_device can "$_kind" "$name" "$can" "" "" "" "" "$operstate" "{}"
        print_block "  $name state=$operstate"
    done
    print_block ""
}

collect_display() {
    glob_has_dirs /sys/class/drm/card*-* || return 0
    print_section "DISPLAY (DRM)"
    for conn in /sys/class/drm/card*-*; do
        [ -f "$conn/status" ] || continue
        name=$(basename "$conn")
        status=$(sysfs_read "$conn/status")
        add_device display physical "$name" "$conn" "" "" "" "" "$status" "{}"
        print_block "  $name: $status"
    done
    if path_has_binary xrandr; then
        run_sh_checked 'xrandr --query 2>/dev/null | head -30' xrandr head
    fi
    print_block ""
}

collect_fibre_channel() {
    glob_has_dirs /sys/class/fc_host/* || return 0
    print_section "FIBRE CHANNEL"
    for fc in /sys/class/fc_host/*; do
        [ -d "$fc" ] || continue
        _fcname=$(basename "$fc")
        _fcport=$(sysfs_read "$fc/port_name")
        _fcnode=$(sysfs_read "$fc/node_name")
        _fcstate=$(sysfs_read "$fc/port_state")
        add_device fibre_channel physical "$_fcname" "$fc" "" "" "$_fcnode" "" "$_fcstate" \
            "$(json_object port_name "$_fcport" node_name "$_fcnode")"
    done
    print_block ""
}

collect_firewire() {
    glob_has_dirs /sys/bus/firewire/devices/* || return 0
    print_section "FIREWIRE"
    for _fw in /sys/bus/firewire/devices/*; do
        [ -e "$_fw" ] || [ -L "$_fw" ] || continue
        _fwname=$(basename "$_fw")
        add_device firewire physical "$_fwname" "$_fw" "" "" "" "" "" "{}"
    done
    print_block ""
}

collect_full_dev() {
    print_section "/DEV DIRECTORY - ALL DEVICE NODES"
    require_binary find
    require_binary ls
    require_binary awk
    find /dev -mindepth 1 -maxdepth 1 -exec ls -ld {} + 2>/dev/null | awk '
BEGIN { char = 0; block = 0; link = 0; other = 0 }
/^c/ { char++ }
/^b/ { block++ }
/^l/ { link++ }
/^[^cbl-]/ { other++ }
END {
    print "  Character:", char, " Block:", block, " Links:", link, " Other:", other
}'
    print_block ""
    list_dir_long /dev/bus/usb 25
    run_sh_checked 'ls -l /dev/ttyS* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null' ls
    list_dir_long /dev/net 0
    run_sh_checked 'ls -l /dev/sd* /dev/nvme* 2>/dev/null | head -n 20' ls head
    list_dir_long /dev/input 30
    list_dir_long /dev/snd 15
    run_sh_checked 'ls -l /dev/video* 2>/dev/null' ls
    list_dir_long /dev/dri 0
    print_block "Total /dev entries: $(count_dir_entries /dev)"
    print_block ""
}

collect_full_sys() {
    print_section "/SYS DIRECTORY - KERNEL DEVICE TREE"
    list_dir_names /sys/bus
    print_block ""
    list_dir_names /sys/class
    print_block ""
    print_block "USB device count: $(count_dir_entries /sys/bus/usb/devices)"
    print_block "PCI device count: $(count_dir_entries /sys/bus/pci/devices)"
    print_block ""
}

collect_i2c() {
    glob_has_dirs /sys/bus/i2c/devices/* || return 0
    print_section "I2C DEVICES"
    for i2c in /sys/bus/i2c/devices/*; do
        [ -e "$i2c" ] || [ -L "$i2c" ] || continue
        name=$(basename "$i2c")
        driver=$(driver_name_for_sysfs "$i2c")
        iname=$(sysfs_read "$i2c/name")
        modalias=$(sysfs_read "$i2c/modalias")
        add_device i2c physical "$name" "$i2c" "$driver" "" "$iname" "" "" \
            "$(json_object modalias "$modalias")"
        print_block "  $name: $iname"
    done
    print_block ""
}

collect_infiniband() {
    glob_has_dirs /sys/class/infiniband/* || return 0
    print_section "INFINIBAND"
    for ib in /sys/class/infiniband/*; do
        [ -d "$ib" ] || continue
        _ibname=$(basename "$ib")
        _ibboard=$(sysfs_read "$ib/board_id")
        add_device infiniband physical "$_ibname" "$ib" "" "" "" "" "" \
            "$(json_object board_id "$_ibboard")"
    done
    print_block ""
}

collect_input() {
    print_section "INPUT / HID DEVICES"

    if [ -f /proc/bus/input/devices ]; then
        require_binary cat
        run_diagnostic cat /proc/bus/input/devices
        print_block ""
    fi

    for input in /sys/class/input/input*; do
        [ -d "$input" ] || continue
        dev=$(basename "$input")
        name=$(sysfs_read "$input/name")
        phys=$(sysfs_read "$input/phys")
        details=$(json_object phys "$phys")
        add_device input physical "$dev" "$input" "" "" "$name" "" "" "$details"
    done

    run_sh_checked 'ls -l /dev/hidraw* /dev/js* 2>/dev/null' ls
    print_block ""
}

collect_iscsi() {
    _has_sessions=0
    if path_has_binary iscsiadm && iscsiadm -m session 2>/dev/null | grep -q .; then
        _has_sessions=1
    fi
    if [ -d /sys/class/iscsi_session ]; then
        for _p in /sys/class/iscsi_session/*; do
            [ -d "$_p" ] || continue
            _has_sessions=1
            break
        done
    fi
    [ "$_has_sessions" -eq 1 ] || return 0

    print_section "ISCSI"

    if path_has_binary iscsiadm; then
        run_cmd iscsiadm -m session
        print_block ""
        _iscsi_tmp=$(make_temp_file device_discovery_iscsi)
        iscsiadm -m session 2>/dev/null >"$_iscsi_tmp" || :
        while IFS= read -r _line; do
            [ -z "$_line" ] && continue
            _portal=$(printf '%s' "$_line" | awk '{print $3}')
            _iqn=$(printf '%s' "$_line" | awk '{print $4}')
            [ -n "$_iqn" ] || continue
            _name=$(printf '%s' "$_iqn" | sed 's/^iqn[.]//; s/[:.]/_/g;s/[^a-zA-Z0-9_-]//g' | cut -c1-64)
            add_device iscsi physical "$_name" "" "" "$_portal" "$_iqn" "" "" \
                "$(json_object portal "$_portal" iqn "$_iqn")"
        done <"$_iscsi_tmp"
        rm -f "$_iscsi_tmp"
    elif [ -d /sys/class/iscsi_session ]; then
        for _sess in /sys/class/iscsi_session/*; do
            [ -d "$_sess" ] || continue
            _sname=$(basename "$_sess")
            add_device iscsi physical "$_sname" "$_sess" "" "" "" "" "" "{}"
        done
    fi
    print_block ""
}

collect_kernel_context() {
    print_section "KERNEL MODULES (device-related)"
    if path_has_binary lsmod; then
        run_sh_checked "lsmod 2>/dev/null | grep -iE 'usb|serial|bluetooth|btusb|eth|net|wifi|cfg80211|thunderbolt|can|nfc|drm|snd|i2c|spi|nvme|iscsi' | head -40" lsmod grep head
        print_block ""
    fi

    print_section "UDEV RUNTIME"
    if [ -d /run/udev/data ]; then
        run_sh_checked 'ls -lh /run/udev/data/ 2>/dev/null | head -15' ls head
        print_block ""
    fi

    print_section "RECENT KERNEL MESSAGES"
    if path_has_binary dmesg; then
        run_sh_checked "dmesg 2>/dev/null | grep -iE 'usb|serial|bluetooth|eth|network|tty|wifi|wlan|thunderbolt|can|nfc|iscsi|i2c' | tail -30" dmesg grep tail
        print_block ""
    fi
}

collect_mtp() {
    diagnostics_enabled || return 0
    print_section "MTP / GVFS MOUNTS"
    run_sh_checked 'ls -d /run/user/*/gvfs/* 2>/dev/null | head -10' ls head
    if path_has_binary mtp-detect; then
        run_sh_checked 'mtp-detect 2>/dev/null | head -20' mtp-detect head
    fi
    print_block ""
}

collect_network() {
    print_section "ETHERNET / NETWORK INTERFACES"

    if path_has_binary ip; then
        run_cmd ip -d link show
        run_cmd ip addr show
        run_sh_checked 'ip route show 2>/dev/null | head -30' ip head
        print_block ""
    fi

    if path_has_binary ifconfig; then
        run_cmd ifconfig -a
        print_block ""
    fi

    if path_has_binary bridge; then
        run_cmd bridge link show
        print_block ""
    fi

    for bond in /proc/net/bonding/*; do
        [ -f "$bond" ] || continue
        run_diagnostic head -15 "$bond"
    done

    for net in /sys/class/net/*; do
        [ -d "$net" ] || continue
        iface=$(basename "$net")
        case "$iface" in
            can* | vcan*) continue ;;
        esac
        kind=$(net_iface_kind "$iface")
        if ! should_include_kind "$kind"; then
            continue
        fi
        mac=$(sysfs_read "$net/address")
        operstate=$(sysfs_read "$net/operstate")
        driver=$(driver_name_for_sysfs "$net/device")
        speed=$(sysfs_read "$net/speed")
        mtu=$(sysfs_read "$net/mtu")

        print_block "  $iface  kind=$kind  state=$operstate"

        if [ "$kind" != "wireless" ]; then
            details=$(json_object mtu "$mtu" speed_mbps "$speed" mac "$mac")
            add_device network "$kind" "$iface" "$net" "$driver" "" "" "" "$operstate" "$details"
        fi
    done
    print_block ""

    if path_has_binary resolvectl; then
        run_sh_checked 'resolvectl status 2>/dev/null | head -25' resolvectl head
    elif [ -f /etc/resolv.conf ]; then
        run_sh_checked "grep -v '^#' /etc/resolv.conf 2>/dev/null | head -10" grep head
    fi
    run_sh_checked 'cat /proc/net/dev 2>/dev/null | head -20' cat head
    print_block ""
}

collect_nfc() {
    glob_has_dirs /sys/class/nfc/* || return 0
    print_section "NFC"
    for nfc in /sys/class/nfc/*; do
        [ -d "$nfc" ] || continue
        add_device nfc physical "$(basename "$nfc")" "$nfc" "" "" "" "" "" "{}"
    done
    print_block ""
}

collect_pci() {
    print_section "PCI DEVICES"

    if path_has_binary lspci; then
        run_sh_checked 'lspci -nnk 2>/dev/null | head -80' lspci head
        print_block ""
    fi

    for pci in /sys/bus/pci/devices/*; do
        [ -d "$pci" ] || continue
        [ -f "$pci/vendor" ] || continue

        class_id=$(sysfs_read "$pci/class")
        if should_skip_pci_device "$class_id"; then
            continue
        fi

        name=$(basename "$pci")
        vendor_id=$(sysfs_read "$pci/vendor")
        device_id=$(sysfs_read "$pci/device")
        driver=$(driver_name_for_sysfs "$pci")
        revision=$(sysfs_read "$pci/revision")

        details=$(json_object class "$class_id" vendor_id "$vendor_id" device_id "$device_id" revision "$revision")
        add_device pci physical "$name" "$pci" "$driver" "$vendor_id" "$device_id" "" "" "$details"
        print_block "  $name class=$class_id driver=$driver"
    done
    print_block ""
}

collect_platform() {
    glob_has_dirs /sys/bus/platform/devices/* || return 0
    print_section "PLATFORM DEVICES"
    for plat in /sys/bus/platform/devices/*; do
        [ -e "$plat" ] || [ -L "$plat" ] || continue
        name=$(basename "$plat")
        driver=$(driver_name_for_sysfs "$plat")
        ofname=$(sysfs_read "$plat/of_node/name")
        modalias=$(sysfs_read "$plat/modalias")
        add_device platform physical "$name" "$plat" "$driver" "" "$ofname" "" "" \
            "$(json_object modalias "$modalias" of_name "$ofname")"
        print_block "  $name driver=$driver"
    done
    print_block ""
}

collect_power() {
    glob_has_dirs /sys/class/power_supply/* || return 0
    print_section "POWER SUPPLY"
    for ps in /sys/class/power_supply/*; do
        [ -d "$ps" ] || continue
        dev=$(basename "$ps")
        ptype=$(sysfs_read "$ps/type")
        status=$(sysfs_read "$ps/status")
        capacity=$(sysfs_read "$ps/capacity")
        add_device power physical "$dev" "$ps" "" "" "$ptype" "" "$status" \
            "$(json_object capacity "$capacity")"
    done
    print_block ""
}

collect_sensor() {
    glob_has_dirs /sys/class/hwmon/hwmon* /sys/bus/iio/devices/iio* || return 0

    print_section "SENSORS"
    if [ -d /sys/class/hwmon ]; then
        for hw in /sys/class/hwmon/hwmon*; do
            [ -d "$hw" ] || continue
            name=$(sysfs_read "$hw/name")
            add_device sensor physical "$(basename "$hw")" "$hw" "" "" "$name" "" "" "{}"
            print_block "  $(basename "$hw"): $name"
        done
    fi
    if [ -d /sys/bus/iio/devices ]; then
        for iio in /sys/bus/iio/devices/iio*; do
            [ -d "$iio" ] || continue
            iname=$(sysfs_read "$iio/name")
            add_device sensor physical "$(basename "$iio")" "$iio" "" "" "$iname" "" "" "{}"
        done
    fi
    print_block ""
}

collect_serial() {
    print_section "SERIAL DEVICES"

    run_sh_checked 'ls -l /dev/tty[SU]* /dev/ttyUSB* /dev/ttyACM* 2>/dev/null' ls
    print_block ""

    for pattern in /sys/class/tty/ttyS* /sys/class/tty/ttyUSB* /sys/class/tty/ttyACM*; do
        for tty in $pattern; do
            [ -e "$tty/device" ] || continue
            name=$(basename "$tty")
            driver=$(driver_name_for_sysfs "$tty/device")
            add_device serial physical "$name" "/dev/$name" "$driver" "" "" "" "" "{}"
            print_block "Device: $name"
        done
    done

    if path_has_binary setserial; then
        run_cmd setserial -g /dev/ttyS*
    fi
    print_block ""
}

collect_spi() {
    glob_has_dirs /sys/bus/spi/devices/* || return 0
    print_section "SPI DEVICES"
    for spi in /sys/bus/spi/devices/*; do
        [ -e "$spi" ] || [ -L "$spi" ] || continue
        name=$(basename "$spi")
        driver=$(driver_name_for_sysfs "$spi")
        modalias=$(sysfs_read "$spi/modalias")
        add_device spi physical "$name" "$spi" "$driver" "" "" "" "" \
            "$(json_object modalias "$modalias")"
        print_block "  $name driver=$driver"
    done
    print_block ""
}

collect_storage() {
    print_section "BLOCK DEVICES (STORAGE)"

    if path_has_binary lsblk; then
        run_cmd lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,VENDOR,MODEL,TRAN
        print_block ""
    fi

    for block in /sys/block/*; do
        [ -d "$block" ] || continue
        dev=$(basename "$block")
        kind=physical
        case "$dev" in
            loop* | dm-* | ram*) kind=virtual ;;
        esac
        if ! should_include_kind "$kind"; then
            continue
        fi
        vendor=$(sysfs_read "$block/device/vendor")
        model=$(sysfs_read "$block/device/model")
        size=$(sysfs_read "$block/size")
        removable=$(sysfs_read "$block/removable")
        driver=$(driver_name_for_sysfs "$block/device")
        details=$(json_object size_sectors "$size" removable "$removable")
        add_device storage "$kind" "$dev" "/dev/$dev" "$driver" "$vendor" "$model" "" "" "$details"
    done

    run_sh_checked 'cat /proc/partitions 2>/dev/null | head -30' cat head
    print_block ""
}

collect_thunderbolt() {
    [ -d /sys/bus/thunderbolt/devices ] || return 0
    glob_has_dirs /sys/bus/thunderbolt/devices/* || return 0
    print_section "THUNDERBOLT / USB4"
    for tb in /sys/bus/thunderbolt/devices/*; do
        [ -d "$tb" ] || continue
        name=$(basename "$tb")
        uid=$(sysfs_read "$tb/uid")
        authorized=$(sysfs_read "$tb/authorized")
        add_device thunderbolt physical "$name" "$tb" "" "" "" "$uid" "$authorized" \
            "$(json_object uid "$uid" authorized "$authorized")"
    done
    if path_has_binary boltctl; then
        run_cmd boltctl list
    fi
    print_block ""
}

collect_usb() {
    print_section "USB DEVICES"

    if diagnostics_enabled; then
        if path_has_binary lsusb; then
            print_block "USB Devices (lsusb):"
            run_cmd lsusb
            print_block ""
            print_block "USB Topology (lsusb -t):"
            run_cmd lsusb -t
            print_block ""
        else
            print_note "lsusb not in PATH (install usbutils)"
        fi
    fi

    print_block "USB Devices from /sys/bus/usb/devices:"
    for device in /sys/bus/usb/devices/*; do
        [ -d "$device" ] || continue
        [ -f "$device/product" ] || [ -f "$device/manufacturer" ] || [ -f "$device/idVendor" ] || continue

        devname=$(basename "$device")
        manufacturer=$(sysfs_read "$device/manufacturer")
        product=$(sysfs_read "$device/product")
        vendor_id=$(sysfs_read "$device/idVendor")
        product_id=$(sysfs_read "$device/idProduct")
        speed=$(sysfs_read "$device/speed")
        serial=$(sysfs_read "$device/serial")
        driver=$(driver_name_for_sysfs "$device")
        state="speed=${speed}Mbps"

        print_block "Device: $devname"
        print_block ""

        details=$(json_object sysfs "$device" vendor_id "$vendor_id" product_id "$product_id" speed_mbps "$speed")
        add_device usb physical "$devname" "$device" "$driver" "$manufacturer" "$product" "$serial" "$state" "$details"

        if [ "$VERBOSITY" -ge 2 ] && path_has_binary udevadm; then
            require_binary udevadm
            require_binary head
            udev_out=$(udevadm info --query=all --name="$device" 2>/dev/null | head -20)
            if [ -n "$udev_out" ]; then
                print_block "  udevadm ($devname):"
                printf '%s\n' "$udev_out" | while IFS= read -r _udev_line; do
                    print_block "    $_udev_line"
                done
            fi
        fi
    done

    run_sh_checked 'ls -l /dev/bus/usb/*/* 2>/dev/null | head -20' ls head
    print_block ""
}

collect_wifi() {
    if ! glob_has_dirs /sys/class/ieee80211/*; then
        if ! diagnostics_enabled; then
            return 0
        fi
    fi

    print_section "WI-FI DEVICES"

    if diagnostics_enabled; then
        if path_has_binary iw || path_has_binary iwconfig; then
            require_binary_one_of iw iwconfig
            if path_has_binary iw; then
                run_cmd iw dev
                run_sh_checked 'iw phy 2>/dev/null | head -80' iw head
            else
                run_cmd iwconfig
            fi
            print_block ""
        fi
        if path_has_binary nmcli; then
            run_sh_checked 'nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | grep -i wifi || true' nmcli grep
            print_block ""
        fi
    fi

    if [ -d /sys/class/ieee80211 ]; then
        for phy in /sys/class/ieee80211/*; do
            [ -d "$phy" ] || continue
            phyname=$(basename "$phy")
            mac=$(sysfs_read "$phy/macaddress")
            for iface in "$phy"/device/net/*; do
                [ -d "$iface" ] || continue
                ifname=$(basename "$iface")
                operstate=$(sysfs_read "/sys/class/net/${ifname}/operstate")
                driver=$(driver_name_for_sysfs "$phy/device")
                details=$(json_object phy "$phyname" mac "$mac")
                add_device wifi wireless "$ifname" "/sys/class/net/${ifname}" "$driver" "" "" "" "$operstate" "$details"
            done
        done
        print_block ""
    fi
}

collect_wwan() {
    if ! glob_has_dirs /sys/class/net/wwan*; then
        path_has_binary mmcli || return 0
    fi

    print_section "CELLULAR / WWAN"
    if path_has_binary mmcli; then
        run_cmd mmcli -L
        print_block ""
    fi
    run_sh_checked 'ls -l /dev/cdc-wdm* /dev/qmi* /dev/mhi* 2>/dev/null' ls

    for wwan in /sys/class/net/wwan*; do
        [ -d "$wwan" ] || continue
        _wname=$(basename "$wwan")
        _wstate=$(sysfs_read "$wwan/operstate")
        _wdriver=$(driver_name_for_sysfs "$wwan/device")
        add_device wwan physical "$_wname" "$wwan" "$_wdriver" "" "" "" "$_wstate" "{}"
    done
    print_block ""
}

emit_json() {
    hostname=$(hostname 2>/dev/null || printf '%s\n' unknown)
    kernel=$(uname -r 2>/dev/null)
    user=$(whoami 2>/dev/null)
    timestamp=$(utc_timestamp)

    counts=""
    if [ -f "$BUS_COUNTS_FILE" ] && [ -s "$BUS_COUNTS_FILE" ]; then
        counts=$(awk '
            { c[$1]++ }
            END { for (b in c) printf "%d\t%s\n", c[b], b }
        ' "$BUS_COUNTS_FILE" | sort -t '	' -k1,1rn -k2,2 | awk '
            BEGIN { first = 1 }
            {
                if (!first) printf ","
                first = 0
                printf "\"%s\":%s", $2, $1
            }
        ')
    fi

    printf '{'
    printf '"meta":{"version":"%s","hostname":"%s","kernel":"%s","user":"%s","timestamp":"%s","verbosity":%s,"physical_only":%s,"full_dump":%s,"pci_all":%s,"posix":%s},' \
        "$(_json_esc_one "$SCRIPT_VERSION")" \
        "$(_json_esc_one "$hostname")" \
        "$(_json_esc_one "$kernel")" \
        "$(_json_esc_one "$user")" \
        "$(_json_esc_one "$timestamp")" \
        "$VERBOSITY" \
        "$(json_bool "$PHYSICAL_ONLY")" \
        "$(json_bool "$FULL_DUMP")" \
        "$(json_bool "$PCI_ALL")" \
        "$(json_bool "$FORCE_POSIX")"
    printf '"devices":['
    if [ -f "$DEVICES_FILE" ] && [ -s "$DEVICES_FILE" ]; then
        first=1
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            if [ "$first" -eq 1 ]; then
                first=0
            else
                printf ','
            fi
            printf '%s' "$line"
        done <"$DEVICES_FILE"
    fi
    printf '],'
    printf '"summary":{"total_devices":%s,"counts_by_bus":{%s}}' "$DEVICE_COUNT" "$counts"
    printf '}\n'
}

emit_device_list() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0
    [ ! -f "$HUMAN_LIST_FILE" ] && return 0

    printf '\n'
    printf '%s\n' "-------------------------------------"
    printf '%s\n' "DEVICES FOUND"
    printf '%s\n' "-------------------------------------"
    printf '%-10s %-10s %-18s %-10s %-12s %-20s %-14s %s\n' \
        "BUS" "KIND" "NAME" "DRIVER" "SERIAL" "VENDOR" "PRODUCT" "STATE"
    printf '%-10s %-10s %-18s %-10s %-12s %-20s %-14s %s\n' \
        "--------" "--------" "----------------" "--------" "--------" "----------------" "--------" "-----"

    awk -F '\t' 'NF >= 9 {
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
            $1, $2, $3, $5, $8, $6, $7, $9, $4
    }' "$HUMAN_LIST_FILE" | sort -t '	' -k1,1 -k3,3 | awk -F '\t' '{
        bus = $1; kind = $2; name = $3; driver = $4; serial = $5
        vendor = $6; product = $7; state = $8; path = $9
        if (length(vendor) > 18) vendor = substr(vendor, 1, 17) "..."
        if (length(product) > 12) product = substr(product, 1, 11) "..."
        printf "%-10s %-10s %-18s %-10s %-12s %-20s %-14s %s\n",
            bus, kind, name, driver, serial, vendor, product, state
    }'

    printf '\n'
    printf '%s\n' "  Paths:"
    awk -F '\t' 'NF >= 9 {
        printf "%s\t%s\t%s\n", $3, $1, $9
    }' "$HUMAN_LIST_FILE" | sort -t '	' -k2,2 -k1,1 | awk -F '\t' '{
        printf "    [%s] %s -> %s\n", $2, $1, $3
    }'
    printf '\n'
    return 0
}

emit_device_names() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0
    [ "$VERBOSITY" -lt 1 ] && return 0
    [ ! -f "$HUMAN_LIST_FILE" ] && return 0

    printf '\n'
    printf '%s\n' "-------------------------------------"
    printf '%s\n' "DEVICES FOUND"
    printf '%s\n' "-------------------------------------"
    awk -F '\t' 'NF >= 3 { printf "%s\t%s\t%s\n", $3, $1, $2 }' "$HUMAN_LIST_FILE" |
        sort -t '	' -k1,1 -k2,2 |
        awk -F '\t' '{ printf "  %s  (%s / %s)\n", $1, $2, $3 }'
    printf '\n'
    return 0
}

emit_human_summary() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0

    printf '\n'
    printf '%s\n' "-------------------------------------"
    printf '%s\n' "SUMMARY"
    printf '%s\n' "-------------------------------------"
    printf '%s\n' "  Total recorded devices: $DEVICE_COUNT"

    if [ -f "$HUMAN_LIST_FILE" ] && [ -s "$HUMAN_LIST_FILE" ]; then
        printf '%s\n' "  Counts by bus:"
        awk -F '\t' 'NF >= 1 { c[$1]++ } END {
            for (b in c) printf "%d\t%s\n", c[b], b
        }' "$HUMAN_LIST_FILE" | sort -t '	' -k1,1rn -k2,2 | awk -F '\t' '{
            printf "    %4d  %s\n", $1, $2
        }'
    fi
    return 0
}

emit_human_report() {
    emit_human_summary
    if [ "$VERBOSITY" -eq 1 ]; then
        emit_device_names
    fi
    if [ "$VERBOSITY" -ge 2 ]; then
        emit_device_list
    fi
    printf '%s\n' "====================================="
    printf '%s\n' "   SCAN COMPLETE"
    printf '%s\n' "====================================="
}

run_all_collectors() {
    build_wireless_iface_cache

    collect_usb
    collect_serial
    collect_bluetooth
    collect_wifi
    collect_network
    collect_storage
    collect_input
    collect_pci

    collect_thunderbolt
    collect_wwan
    collect_can
    collect_nfc
    collect_display
    collect_audio
    collect_camera
    collect_sensor
    collect_infiniband
    collect_fibre_channel
    collect_iscsi
    collect_power
    collect_firewire
    collect_platform
    collect_i2c
    collect_spi
    collect_mtp

    if diagnostics_enabled; then
        collect_kernel_context
    fi

    if [ "$VERBOSITY" -ge 2 ] && [ "$FULL_DUMP" -eq 1 ]; then
        collect_full_dev
        collect_full_sys
    fi
}

print_scan_header() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0
    printf '%s\n' "====================================="
    printf '%s\n' "   DEVICE DISCOVERY SCRIPT"
    printf '%s\n' "====================================="
    printf '%s\n' "Date: $(date)"
    printf '%s\n' "Kernel: $(uname -r)"
    printf '%s\n' "Running as: $(whoami)"
    printf '%s\n' "Version: ${SCRIPT_VERSION} (modular)"
    case "$VERBOSITY" in
        0) printf '%s\n' "Output: summary only (-v for names, -vv for full diagnostics)" ;;
        1) printf '%s\n' "Output: summary and device names" ;;
        2) printf '%s\n' "Output: full diagnostics (-vv)" ;;
    esac
    if [ "$PHYSICAL_ONLY" -eq 1 ]; then
        printf '%s\n' "Filter: physical devices only"
    fi
    if [ "$PCI_ALL" -eq 0 ]; then
        printf '%s\n' "PCI: endpoints only (use --pci-all for bridges)"
    fi
    if [ "$FULL_DUMP" -eq 1 ]; then
        printf '%s\n' "Extra: full /dev and /sys dumps"
    fi
    if [ "$FORCE_POSIX" -eq 1 ]; then
        printf '%s\n' "Mode: strict POSIX"
    fi
    printf '%s\n' "====================================="
    return 0
}

main() {
    parse_args "$@"

    init_scan_temp_files
    trap '_cleanup_temp_files' EXIT HUP INT TERM

    init_path_cache

    check_privileges "$@"

    require_core_utilities
    if [ "$FORCE_POSIX" -eq 1 ]; then
        enforce_posix_mode
    fi

    print_scan_header
    run_all_collectors

    if [ "$OUTPUT_JSON" -eq 1 ]; then
        emit_json
    else
        emit_human_report
    fi

    _cleanup_temp_files
    trap '' EXIT HUP INT TERM
}
main "$@"
