collect_audio() {
    glob_has_dirs /sys/class/sound/card* || return 0
    print_section "AUDIO"
    for snd in /sys/class/sound/card*; do
        [ -d "$snd" ] || continue
        card=$(basename "$snd")
        id=$(sysfs_read "$snd/id")
        add_device audio physical "$card" "$snd" "" "" "$id" "" "" "{}"
    done
    if path_has_binary aplay; then
        run_cmd aplay -l
    fi
    run_sh_checked 'ls -l /dev/snd/* 2>/dev/null | head -15' ls head
    print_block ""
}
