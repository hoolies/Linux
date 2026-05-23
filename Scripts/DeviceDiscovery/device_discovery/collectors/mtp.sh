collect_mtp() {
    diagnostics_enabled || return 0
    print_section "MTP / GVFS MOUNTS"
    run_sh_checked 'ls -d /run/user/*/gvfs/* 2>/dev/null | head -10' ls head
    if path_has_binary mtp-detect; then
        run_sh_checked 'mtp-detect 2>/dev/null | head -20' mtp-detect head
    fi
    print_block ""
}
