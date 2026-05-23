collect_nfc() {
    glob_has_dirs /sys/class/nfc/* || return 0
    print_section "NFC"
    for nfc in /sys/class/nfc/*; do
        [ -d "$nfc" ] || continue
        add_device nfc physical "$(basename "$nfc")" "$nfc" "" "" "" "" "" "{}"
    done
    print_block ""
}
