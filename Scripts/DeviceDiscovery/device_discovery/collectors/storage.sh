collect_storage() {
    print_section "BLOCK DEVICES (STORAGE)"

    if path_has_binary lsblk; then
        run_cmd lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,VENDOR,MODEL,TRAN
        print_block ""
    fi

    for block in /sys/block/*; do
        [ -d "$block" ] || continue
        dev=$(basename "$block")
        kind=physical
        case "$dev" in
            loop*|dm-*|ram*) kind=virtual ;;
        esac
        if ! should_include_kind "$kind"; then
            continue
        fi
        vendor=$(sysfs_read "$block/device/vendor")
        model=$(sysfs_read "$block/device/model")
        size=$(sysfs_read "$block/size")
        removable=$(sysfs_read "$block/removable")
        driver=$(driver_name_for_sysfs "$block/device")
        details=$(json_object size_sectors "$size" removable "$removable")
        add_device storage "$kind" "$dev" "/dev/$dev" "$driver" "$vendor" "$model" "" "" "$details"
    done

    run_sh_checked 'cat /proc/partitions 2>/dev/null | head -30' cat head
    print_block ""
}
