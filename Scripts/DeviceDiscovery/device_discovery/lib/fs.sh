# Directory listing helpers.

count_dir_entries() {
    _dir=$1
    _count=0
    if [ ! -d "$_dir" ]; then
        printf '0'
        return 0
    fi
    for _entry in "$_dir"/*; do
        if [ -e "$_entry" ] || [ -L "$_entry" ]; then
            _count=$((_count + 1))
        fi
    done
    printf '%s' "$_count"
}

list_dir_long() {
    _dir=$1
    _max=$2
    require_binary find
    require_binary ls
    [ -d "$_dir" ] || return 0
    if [ -n "$_max" ] && [ "$_max" -gt 0 ]; then
        require_binary head
        find "$_dir" -mindepth 1 -maxdepth 1 -exec ls -ld {} + 2>/dev/null | head -n "$_max"
    else
        find "$_dir" -mindepth 1 -maxdepth 1 -exec ls -ld {} + 2>/dev/null
    fi
}

list_dir_names() {
    _dir=$1
    require_binary find
    require_binary basename
    [ -d "$_dir" ] || return 0
    find "$_dir" -mindepth 1 -maxdepth 1 2>/dev/null | while IFS= read -r _path; do
        print_block "  $(basename "$_path")"
    done
}
