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
