collect_pci() {
    print_section "PCI DEVICES"

    if path_has_binary lspci; then
        run_sh_checked 'lspci -nnk 2>/dev/null | head -80' lspci head
        print_block ""
    fi

    for pci in /sys/bus/pci/devices/*; do
        [ -d "$pci" ] || continue
        [ -f "$pci/vendor" ] || continue

        class_id=$(sysfs_read "$pci/class")
        if should_skip_pci_device "$class_id"; then
            continue
        fi

        name=$(basename "$pci")
        vendor_id=$(sysfs_read "$pci/vendor")
        device_id=$(sysfs_read "$pci/device")
        driver=$(driver_name_for_sysfs "$pci")
        revision=$(sysfs_read "$pci/revision")

        details=$(json_object class "$class_id" vendor_id "$vendor_id" device_id "$device_id" revision "$revision")
        add_device pci physical "$name" "$pci" "$driver" "$vendor_id" "$device_id" "" "" "$details"
        print_block "  $name class=$class_id driver=$driver"
    done
    print_block ""
}
