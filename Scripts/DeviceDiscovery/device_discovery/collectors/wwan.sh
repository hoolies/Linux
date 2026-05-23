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
