collect_power() {
    glob_has_dirs /sys/class/power_supply/* || return 0
    print_section "POWER SUPPLY"
    for ps in /sys/class/power_supply/*; do
        [ -d "$ps" ] || continue
        dev=$(basename "$ps")
        ptype=$(sysfs_read "$ps/type")
        status=$(sysfs_read "$ps/status")
        capacity=$(sysfs_read "$ps/capacity")
        add_device power physical "$dev" "$ps" "" "" "$ptype" "" "$status" \
            "$(json_object capacity "$capacity")"
    done
    print_block ""
}
