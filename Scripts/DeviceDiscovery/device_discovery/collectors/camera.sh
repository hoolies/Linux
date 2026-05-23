collect_camera() {
    glob_has_dirs /sys/class/video4linux/* || return 0
    print_section "CAMERAS (V4L)"
    for video in /sys/class/video4linux/*; do
        [ -d "$video" ] || continue
        name=$(basename "$video")
        vname=$(sysfs_read "$video/name")
        add_device camera physical "$name" "$video" "" "" "$vname" "" "" "{}"
        print_block "  $name: $vname"
    done
    print_block ""
}
