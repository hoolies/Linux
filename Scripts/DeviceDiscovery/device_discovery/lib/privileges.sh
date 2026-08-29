# Root / sudo handling.

print_nonroot_notice() {
    _fd=$1
    {
        printf '%s\n' "NOTICE: Not running as root — some checks may be incomplete."
        printf '\n'
        if path_has_binary dmesg; then
            printf '%s\n' "  - dmesg              kernel ring buffer"
        fi
        if path_has_binary bluetoothctl; then
            printf '%s\n' "  - bluetoothctl       paired devices"
        fi
        if path_has_binary mmcli; then
            printf '%s\n' "  - mmcli              cellular modems"
        fi
        if path_has_binary udevadm; then
            printf '%s\n' "  - udevadm            restricted device attributes"
        fi
        if path_has_binary iscsiadm; then
            printf '%s\n' "  - iscsiadm           iSCSI sessions"
        fi
        printf '\n'
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
            printf '%s\n' "Continuing without sudo (non-interactive)." >&2
        else
            printf '%s\n' "Continuing without sudo (non-interactive)."
        fi
        return 0
    fi

    if [ "$OUTPUT_JSON" -eq 1 ]; then
        printf "Re-run with sudo for full output? (y/n): " >&2
    else
        printf "Re-run with sudo for full output? (y/n): "
    fi
    IFS= read -r _response
    printf '\n'
    case "$_response" in
        [Yy]*)
            require_binary sudo
            exec sudo "$DD_ENTRY" "$@"
            ;;
        *)
            if [ "$OUTPUT_JSON" -eq 1 ]; then
                printf '%s\n' "Continuing without sudo." >&2
            else
                printf '%s\n' "Continuing without sudo."
            fi
            ;;
    esac
}
