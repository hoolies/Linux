collect_platform() {
    glob_has_dirs /sys/bus/platform/devices/* || return 0
    print_section "PLATFORM DEVICES"
    for plat in /sys/bus/platform/devices/*; do
        [ -e "$plat" ] || [ -L "$plat" ] || continue
        name=$(basename "$plat")
        driver=$(driver_name_for_sysfs "$plat")
        ofname=$(sysfs_read "$plat/of_node/name")
        modalias=$(sysfs_read "$plat/modalias")
        add_device platform physical "$name" "$plat" "$driver" "" "$ofname" "" "" \
            "$(json_object modalias "$modalias" of_name "$ofname")"
        print_block "  $name driver=$driver"
    done
    print_block ""
}
