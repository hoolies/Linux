collect_spi() {
    glob_has_dirs /sys/bus/spi/devices/* || return 0
    print_section "SPI DEVICES"
    for spi in /sys/bus/spi/devices/*; do
        [ -e "$spi" ] || [ -L "$spi" ] || continue
        name=$(basename "$spi")
        driver=$(driver_name_for_sysfs "$spi")
        modalias=$(sysfs_read "$spi/modalias")
        add_device spi physical "$name" "$spi" "$driver" "" "" "" "" \
            "$(json_object modalias "$modalias")"
        print_block "  $name driver=$driver"
    done
    print_block ""
}
