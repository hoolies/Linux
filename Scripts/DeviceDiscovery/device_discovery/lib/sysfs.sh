# Sysfs read and driver resolution.

sysfs_read() {
    f=$1
    if [ -f "$f" ]; then
        cat "$f" 2>/dev/null | tr -d '\n'
    fi
}

read_symlink_target() {
    _path=$1
    if [ "$FORCE_POSIX" -eq 0 ] && path_has_binary readlink; then
        _target=$(readlink "$_path" 2>/dev/null)
        if [ -n "$_target" ]; then
            printf '%s' "$_target"
            return 0
        fi
    fi
    if ! path_has_binary ls; then
        return 0
    fi
    _line=$(ls -ld "$_path" 2>/dev/null) || return 0
    case "$_line" in
        *" -> "*) printf '%s' "${_line#* -> }" ;;
    esac
}

driver_name_for_sysfs() {
    _devpath=$1
    [ -n "$_devpath" ] || return 0
    if [ -f "$DRIVER_CACHE_FILE" ]; then
        _driver=$(awk -F '\t' -v p="$_devpath" '$1 == p { print $2; exit }' "$DRIVER_CACHE_FILE" 2>/dev/null)
        if [ -n "$_driver" ]; then
            printf '%s' "$_driver"
            return 0
        fi
    fi
    _driver=""
    _driver_link=${_devpath}/driver
    if [ -L "$_driver_link" ]; then
        _target=$(read_symlink_target "$_driver_link")
        _driver=${_target##*/}
    fi
    printf '%s\t%s\n' "$_devpath" "$_driver" >> "$DRIVER_CACHE_FILE"
    printf '%s' "$_driver"
}

# Stable id: bus + slug from sysfs path or name.
stable_device_id() {
    _bus=$1
    _path=$2
    _name=$3
    if [ -n "$_path" ]; then
        _slug=$(printf '%s' "$_path" | sed 's|^/sys/||; s|/|_|g; s|\.|_|g; s|_|_|g')
    else
        _slug=$(printf '%s' "$_name" | sed 's|/|_|g; s|\.|_|g')
    fi
    printf '%s__%s' "$_bus" "$_slug"
}

pci_is_bridge_class() {
    _class=$1
    case "$_class" in
        0x0604*|0x060000|0x060100) return 0 ;;
    esac
    return 1
}

should_skip_pci_device() {
    _class=$1
    if [ "$PCI_ALL" -eq 1 ]; then
        return 1
    fi
    if pci_is_bridge_class "$_class"; then
        return 0
    fi
    return 1
}
