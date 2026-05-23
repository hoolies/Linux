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
