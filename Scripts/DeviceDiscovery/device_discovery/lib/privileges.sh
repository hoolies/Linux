# Root / sudo handling.

print_nonroot_notice() {
    _fd=$1
    {
        echo "NOTICE: Not running as root — some checks may be incomplete."
        echo ""
        if path_has_binary dmesg; then
            echo "  - dmesg              kernel ring buffer"
        fi
        if path_has_binary bluetoothctl; then
            echo "  - bluetoothctl       paired devices"
        fi
        if path_has_binary mmcli; then
            echo "  - mmcli              cellular modems"
        fi
        if path_has_binary udevadm; then
            echo "  - udevadm            restricted device attributes"
        fi
        if path_has_binary iscsiadm; then
            echo "  - iscsiadm           iSCSI sessions"
        fi
        echo ""
    } >&"$_fd"
}

check_privileges() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi

    if [ "$OUTPUT_JSON" -eq 1 ]; then
        print_nonroot_notice 2
    else
        print_nonroot_notice 1
    fi

    if [ "$NONINTERACTIVE" -eq 1 ] || [ ! -t 0 ] || [ ! -t 1 ]; then
        if [ "$OUTPUT_JSON" -eq 1 ]; then
            echo "Continuing without sudo (non-interactive)." >&2
        else
            echo "Continuing without sudo (non-interactive)."
        fi
        return 0
    fi

    if [ "$OUTPUT_JSON" -eq 1 ]; then
        printf "Re-run with sudo for full output? (y/n): " >&2
    else
        printf "Re-run with sudo for full output? (y/n): "
    fi
    IFS= read -r _response
    echo ""
    case "$_response" in
        [Yy]*)
            require_binary sudo
            exec sudo "$DD_ENTRY" "$@"
            ;;
        *)
            if [ "$OUTPUT_JSON" -eq 1 ]; then
                echo "Continuing without sudo." >&2
            else
                echo "Continuing without sudo."
            fi
            ;;
    esac
}
