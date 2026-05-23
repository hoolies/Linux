collect_usb() {
    print_section "USB DEVICES"

    if diagnostics_enabled; then
        if path_has_binary lsusb; then
            print_block "USB Devices (lsusb):"
            run_cmd lsusb
            print_block ""
            print_block "USB Topology (lsusb -t):"
            run_cmd lsusb -t
            print_block ""
        else
            print_note "lsusb not in PATH (install usbutils)"
        fi
    fi

    print_block "USB Devices from /sys/bus/usb/devices:"
    for device in /sys/bus/usb/devices/*; do
        [ -d "$device" ] || continue
        [ -f "$device/product" ] || [ -f "$device/manufacturer" ] || [ -f "$device/idVendor" ] || continue

        devname=$(basename "$device")
        manufacturer=$(sysfs_read "$device/manufacturer")
        product=$(sysfs_read "$device/product")
        vendor_id=$(sysfs_read "$device/idVendor")
        product_id=$(sysfs_read "$device/idProduct")
        speed=$(sysfs_read "$device/speed")
        serial=$(sysfs_read "$device/serial")
        driver=$(driver_name_for_sysfs "$device")
        state="speed=${speed}Mbps"

        print_block "Device: $devname"
        print_block ""

        details=$(json_object sysfs "$device" vendor_id "$vendor_id" product_id "$product_id" speed_mbps "$speed")
        add_device usb physical "$devname" "$device" "$driver" "$manufacturer" "$product" "$serial" "$state" "$details"

        if [ "$VERBOSITY" -ge 2 ] && path_has_binary udevadm; then
            require_binary udevadm
            require_binary head
            udev_out=$(udevadm info --query=all --name="$device" 2>/dev/null | head -20)
            if [ -n "$udev_out" ]; then
                print_block "  udevadm ($devname):"
                echo "$udev_out" | while IFS= read -r _udev_line; do
                    print_block "    $_udev_line"
                done
            fi
        fi
    done

    run_sh_checked 'ls -l /dev/bus/usb/*/* 2>/dev/null | head -20' ls head
    print_block ""
}
