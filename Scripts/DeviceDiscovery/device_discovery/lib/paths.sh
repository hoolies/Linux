# PATH probing, cache, and command execution.

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
