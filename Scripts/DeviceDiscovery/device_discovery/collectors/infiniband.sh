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
