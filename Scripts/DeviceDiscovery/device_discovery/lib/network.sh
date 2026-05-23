# Network interface classification and TCP reachability probes.

# Return 0 if $1 looks like a safe host literal for connect probes.
tcp_probe_valid_host() {
    _host=$1
    [ -n "$_host" ] || return 1
    case "$_host" in
        *[!a-zA-Z0-9.:\[\]-]*) return 1 ;;
    esac
    return 0
}

# Return 0 if $1 is a decimal TCP port in range.
tcp_probe_valid_port() {
    _port=$1
    case "$_port" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ "$_port" -ge 1 ] 2>/dev/null && [ "$_port" -le 65535 ]
}

# Print probe backend: nc, bash, or nothing.
tcp_port_probe_backend() {
    if path_has_binary nc; then
        printf '%s' nc
        return 0
    fi
    if path_has_binary bash; then
        printf '%s' bash
        return 0
    fi
    return 1
}

# Bash /dev/tcp connect probe; host and port must already be validated.
_tcp_port_open_bash() {
    _host=$1
    _port=$2
    _timeout=$3
    DD_TCP_HOST=$_host DD_TCP_PORT=$_port
    export DD_TCP_HOST DD_TCP_PORT
    if path_has_binary timeout; then
        # shellcheck disable=SC2016 -- expanded by bash, not sh
        timeout "$_timeout" bash -c 'echo >"/dev/tcp/${DD_TCP_HOST}/${DD_TCP_PORT}"' \
            >/dev/null 2>&1
        return $?
    fi
    # shellcheck disable=SC2016
    bash -c 'echo >"/dev/tcp/${DD_TCP_HOST}/${DD_TCP_PORT}"' >/dev/null 2>&1
}

# Return 0 if host:port accepts TCP, 1 if not, 2 if args invalid, 127 if no backend.
tcp_port_open() {
    _host=$1
    _port=$2
    _timeout=${3:-2}

    tcp_probe_valid_host "$_host" || return 2
    tcp_probe_valid_port "$_port" || return 2

    if path_has_binary nc; then
        if path_has_binary timeout; then
            timeout "$_timeout" nc -z "$_host" "$_port" >/dev/null 2>&1
        else
            nc -z -w "$_timeout" "$_host" "$_port" >/dev/null 2>&1
        fi
        return $?
    fi

    if path_has_binary bash; then
        _tcp_port_open_bash "$_host" "$_port" "$_timeout"
        return $?
    fi

    return 127
}

build_wireless_iface_cache() {
    WIRELESS_IFACES=""
    if [ ! -d /sys/class/ieee80211 ]; then
        return 0
    fi
    for phy in /sys/class/ieee80211/*; do
        [ -d "$phy" ] || continue
        for _net in "$phy"/device/net/*; do
            [ -d "$_net" ] || continue
            _iface=$(basename "$_net")
            case " ${WIRELESS_IFACES} " in
                *" ${_iface} "*) ;;
                *) WIRELESS_IFACES="${WIRELESS_IFACES} ${_iface}" ;;
            esac
        done
    done
    for _net in /sys/class/net/*; do
        [ -L "${_net}/phy80211" ] || continue
        _iface=$(basename "$_net")
        case " ${WIRELESS_IFACES} " in
            *" ${_iface} "*) ;;
            *) WIRELESS_IFACES="${WIRELESS_IFACES} ${_iface}" ;;
        esac
    done
}

iface_is_wireless() {
    _iface=$1
    case " ${WIRELESS_IFACES} " in
        *" ${_iface} "*) return 0 ;;
    esac
    return 1
}

net_iface_kind() {
    iface=$1
    netpath="/sys/class/net/${iface}"

    case "$iface" in
        lo) printf '%s' virtual; return ;;
        docker*|veth*|virbr*|kube-*|flannel*|cali*|cni*|podman*)
            printf '%s' virtual
            return
            ;;
        tun*|tap*|wg*|tailscale*|ts*|nordlynx*|ppp*)
            printf '%s' tunnel
            return
            ;;
    esac

    if [ -d "${netpath}/bridge" ] || [ -f "${netpath}/bridge_id" ]; then
        printf '%s' bridge
        return
    fi

    if [ -d "/proc/net/bonding/${iface}" ] 2>/dev/null; then
        printf '%s' bond
        return
    fi

    case "$iface" in
        bond*) printf '%s' bond; return ;;
        br-*) printf '%s' bridge; return ;;
        *@*|*.vlan*|vlan*) printf '%s' vlan; return ;;
        can*|vcan*) printf '%s' physical; return ;;
    esac

    if iface_is_wireless "$iface"; then
        printf '%s' wireless
        return
    fi

    if diagnostics_enabled && path_has_binary iw; then
        if iw dev "$iface" info >/dev/null 2>&1; then
            printf '%s' wireless
            return
        fi
    fi

    if [ -L "${netpath}/device" ]; then
        printf '%s' physical
        return
    fi

    printf '%s' virtual
}
