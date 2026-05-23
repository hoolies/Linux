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
