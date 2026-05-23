collect_kernel_context() {
    print_section "KERNEL MODULES (device-related)"
    if path_has_binary lsmod; then
        run_sh_checked "lsmod 2>/dev/null | grep -iE 'usb|serial|bluetooth|btusb|eth|net|wifi|cfg80211|thunderbolt|can|nfc|drm|snd|i2c|spi|nvme|iscsi' | head -40" lsmod grep head
        print_block ""
    fi

    print_section "UDEV RUNTIME"
    if [ -d /run/udev/data ]; then
        run_sh_checked 'ls -lh /run/udev/data/ 2>/dev/null | head -15' ls head
        print_block ""
    fi

    print_section "RECENT KERNEL MESSAGES"
    if path_has_binary dmesg; then
        run_sh_checked "dmesg 2>/dev/null | grep -iE 'usb|serial|bluetooth|eth|network|tty|wifi|wlan|thunderbolt|can|nfc|iscsi|i2c' | tail -30" dmesg grep tail
        print_block ""
    fi
}
