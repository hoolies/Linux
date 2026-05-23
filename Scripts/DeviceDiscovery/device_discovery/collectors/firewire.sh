collect_firewire() {
    glob_has_dirs /sys/bus/firewire/devices/* || return 0
    print_section "FIREWIRE"
    for _fw in /sys/bus/firewire/devices/*; do
        [ -e "$_fw" ] || [ -L "$_fw" ] || continue
        _fwname=$(basename "$_fw")
        add_device firewire physical "$_fwname" "$_fw" "" "" "" "" "" "{}"
    done
    print_block ""
}
