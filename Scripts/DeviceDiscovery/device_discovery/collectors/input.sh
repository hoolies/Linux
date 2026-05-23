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
