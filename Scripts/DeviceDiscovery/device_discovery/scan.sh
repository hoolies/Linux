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
    [ "$OUTPUT_JSON" -eq 1 ] && return 0
    printf '%s\n' "====================================="
    printf '%s\n' "   DEVICE DISCOVERY SCRIPT"
    printf '%s\n' "====================================="
    printf '%s\n' "Date: $(date)"
    printf '%s\n' "Kernel: $(uname -r)"
    printf '%s\n' "Running as: $(whoami)"
    printf '%s\n' "Version: ${SCRIPT_VERSION} (modular)"
    case "$VERBOSITY" in
        0) printf '%s\n' "Output: summary only (-v for names, -vv for full diagnostics)" ;;
        1) printf '%s\n' "Output: summary and device names" ;;
        2) printf '%s\n' "Output: full diagnostics (-vv)" ;;
    esac
    if [ "$PHYSICAL_ONLY" -eq 1 ]; then
        printf '%s\n' "Filter: physical devices only"
    fi
    if [ "$PCI_ALL" -eq 0 ]; then
        printf '%s\n' "PCI: endpoints only (use --pci-all for bridges)"
    fi
    if [ "$FULL_DUMP" -eq 1 ]; then
        printf '%s\n' "Extra: full /dev and /sys dumps"
    fi
    if [ "$FORCE_POSIX" -eq 1 ]; then
        printf '%s\n' "Mode: strict POSIX"
    fi
    printf '%s\n' "====================================="
    return 0
}
