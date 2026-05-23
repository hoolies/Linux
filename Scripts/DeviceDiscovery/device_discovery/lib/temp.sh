# Temporary files (mktemp when available).

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
