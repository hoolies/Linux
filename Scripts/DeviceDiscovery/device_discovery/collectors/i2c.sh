collect_i2c() {
    glob_has_dirs /sys/bus/i2c/devices/* || return 0
    print_section "I2C DEVICES"
    for i2c in /sys/bus/i2c/devices/*; do
        [ -e "$i2c" ] || [ -L "$i2c" ] || continue
        name=$(basename "$i2c")
        driver=$(driver_name_for_sysfs "$i2c")
        iname=$(sysfs_read "$i2c/name")
        modalias=$(sysfs_read "$i2c/modalias")
        add_device i2c physical "$name" "$i2c" "$driver" "" "$iname" "" "" \
            "$(json_object modalias "$modalias")"
        print_block "  $name: $iname"
    done
    print_block ""
}
