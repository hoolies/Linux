# Shared collector helpers.

# Return 0 if any glob expands to at least one directory.
glob_has_dirs() {
    for _glob in "$@"; do
        for _entry in $_glob; do
            if [ -d "$_entry" ]; then
                return 0
            fi
        done
    done
    return 1
}
