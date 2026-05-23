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
