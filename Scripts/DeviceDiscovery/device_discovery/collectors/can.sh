collect_can() {
    glob_has_dirs /sys/class/net/can* /sys/class/net/vcan* || return 0

    print_section "CAN BUS"
    if path_has_binary ip; then
        run_sh_checked 'ip -d link show type can 2>/dev/null || true' ip
    fi
    for can in /sys/class/net/can* /sys/class/net/vcan*; do
        [ -d "$can" ] || continue
        name=$(basename "$can")
        operstate=$(sysfs_read "$can/operstate")
        _kind=physical
        case "$name" in
            vcan*) _kind=virtual ;;
        esac
        if ! should_include_kind "$_kind"; then
            continue
        fi
        add_device can "$_kind" "$name" "$can" "" "" "" "" "$operstate" "{}"
        print_block "  $name state=$operstate"
    done
    print_block ""
}
