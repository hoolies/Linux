# Run all bus / type collectors in order.

run_all_collectors() {
    build_wireless_iface_cache

    collect_usb
    collect_serial
    collect_bluetooth
    collect_wifi
    collect_network
    collect_storage
    collect_input
    collect_pci

    collect_thunderbolt
    collect_wwan
    collect_can
    collect_nfc
    collect_display
    collect_audio
    collect_camera
    collect_sensor
    collect_infiniband
    collect_fibre_channel
    collect_iscsi
    collect_power
    collect_firewire
    collect_platform
    collect_i2c
    collect_spi
    collect_mtp

    if diagnostics_enabled; then
        collect_kernel_context
    fi

    if [ "$VERBOSITY" -ge 2 ] && [ "$FULL_DUMP" -eq 1 ]; then
        collect_full_dev
        collect_full_sys
    fi
}

print_scan_header() {
    [ "$OUTPUT_JSON" -eq 1 ] && return
    echo "====================================="
    echo "   DEVICE DISCOVERY SCRIPT"
    echo "====================================="
    echo "Date: $(date)"
    echo "Kernel: $(uname -r)"
    echo "Running as: $(whoami)"
    echo "Version: ${SCRIPT_VERSION} (modular)"
    case "$VERBOSITY" in
        0) echo "Output: summary only (-v for names, -vv for full diagnostics)" ;;
        1) echo "Output: summary and device names" ;;
        2) echo "Output: full diagnostics (-vv)" ;;
    esac
    [ "$PHYSICAL_ONLY" -eq 1 ] && echo "Filter: physical devices only"
    [ "$PCI_ALL" -eq 0 ] && echo "PCI: endpoints only (use --pci-all for bridges)"
    [ "$FULL_DUMP" -eq 1 ] && echo "Extra: full /dev and /sys dumps"
    [ "$FORCE_POSIX" -eq 1 ] && echo "Mode: strict POSIX"
    echo "====================================="
}
