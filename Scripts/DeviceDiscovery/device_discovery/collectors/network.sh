collect_network() {
    print_section "ETHERNET / NETWORK INTERFACES"

    if path_has_binary ip; then
        run_cmd ip -d link show
        run_cmd ip addr show
        run_sh_checked 'ip route show 2>/dev/null | head -30' ip head
        print_block ""
    fi

    if path_has_binary ifconfig; then
        run_cmd ifconfig -a
        print_block ""
    fi

    if path_has_binary bridge; then
        run_cmd bridge link show
        print_block ""
    fi

    for bond in /proc/net/bonding/*; do
        [ -f "$bond" ] || continue
        run_diagnostic head -15 "$bond"
    done

    for net in /sys/class/net/*; do
        [ -d "$net" ] || continue
        iface=$(basename "$net")
        case "$iface" in
            can*|vcan*) continue ;;
        esac
        kind=$(net_iface_kind "$iface")
        if ! should_include_kind "$kind"; then
            continue
        fi
        mac=$(sysfs_read "$net/address")
        operstate=$(sysfs_read "$net/operstate")
        driver=$(driver_name_for_sysfs "$net/device")
        speed=$(sysfs_read "$net/speed")
        mtu=$(sysfs_read "$net/mtu")

        print_block "  $iface  kind=$kind  state=$operstate"

        if [ "$kind" != "wireless" ]; then
            details=$(json_object mtu "$mtu" speed_mbps "$speed" mac "$mac")
            add_device network "$kind" "$iface" "$net" "$driver" "" "" "" "$operstate" "$details"
        fi
    done
    print_block ""

    if path_has_binary resolvectl; then
        run_sh_checked 'resolvectl status 2>/dev/null | head -25' resolvectl head
    elif [ -f /etc/resolv.conf ]; then
        run_sh_checked "grep -v '^#' /etc/resolv.conf 2>/dev/null | head -10" grep head
    fi
    run_sh_checked 'cat /proc/net/dev 2>/dev/null | head -20' cat head
    print_block ""
}
