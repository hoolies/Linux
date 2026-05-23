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
