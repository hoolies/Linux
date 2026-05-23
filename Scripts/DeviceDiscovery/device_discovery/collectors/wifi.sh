collect_wifi() {
    if ! glob_has_dirs /sys/class/ieee80211/*; then
        if ! diagnostics_enabled; then
            return 0
        fi
    fi

    print_section "WI-FI DEVICES"

    if diagnostics_enabled; then
        if path_has_binary iw || path_has_binary iwconfig; then
            require_binary_one_of iw iwconfig
            if path_has_binary iw; then
                run_cmd iw dev
                run_sh_checked 'iw phy 2>/dev/null | head -80' iw head
            else
                run_cmd iwconfig
            fi
            print_block ""
        fi
        if path_has_binary nmcli; then
            run_sh_checked 'nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | grep -i wifi || true' nmcli grep
            print_block ""
        fi
    fi

    if [ -d /sys/class/ieee80211 ]; then
        for phy in /sys/class/ieee80211/*; do
            [ -d "$phy" ] || continue
            phyname=$(basename "$phy")
            mac=$(sysfs_read "$phy/macaddress")
            for iface in "$phy"/device/net/*; do
                [ -d "$iface" ] || continue
                ifname=$(basename "$iface")
                operstate=$(sysfs_read "/sys/class/net/${ifname}/operstate")
                driver=$(driver_name_for_sysfs "$phy/device")
                details=$(json_object phy "$phyname" mac "$mac")
                add_device wifi wireless "$ifname" "/sys/class/net/${ifname}" "$driver" "" "" "" "$operstate" "$details"
            done
        done
        print_block ""
    fi
}
