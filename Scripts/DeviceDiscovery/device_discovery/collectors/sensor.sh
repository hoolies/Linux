collect_sensor() {
    glob_has_dirs /sys/class/hwmon/hwmon* /sys/bus/iio/devices/iio* || return 0

    print_section "SENSORS"
    if [ -d /sys/class/hwmon ]; then
        for hw in /sys/class/hwmon/hwmon*; do
            [ -d "$hw" ] || continue
            name=$(sysfs_read "$hw/name")
            add_device sensor physical "$(basename "$hw")" "$hw" "" "" "$name" "" "" "{}"
            print_block "  $(basename "$hw"): $name"
        done
    fi
    if [ -d /sys/bus/iio/devices ]; then
        for iio in /sys/bus/iio/devices/iio*; do
            [ -d "$iio" ] || continue
            iname=$(sysfs_read "$iio/name")
            add_device sensor physical "$(basename "$iio")" "$iio" "" "" "$iname" "" "" "{}"
        done
    fi
    print_block ""
}
