collect_display() {
    glob_has_dirs /sys/class/drm/card*-* || return 0
    print_section "DISPLAY (DRM)"
    for conn in /sys/class/drm/card*-*; do
        [ -f "$conn/status" ] || continue
        name=$(basename "$conn")
        status=$(sysfs_read "$conn/status")
        add_device display physical "$name" "$conn" "" "" "" "" "$status" "{}"
        print_block "  $name: $status"
    done
    if path_has_binary xrandr; then
        run_sh_checked 'xrandr --query 2>/dev/null | head -30' xrandr head
    fi
    print_block ""
}
