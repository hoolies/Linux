# Main entry (sourced after load.sh).

main() {
    parse_args "$@"

    init_scan_temp_files
    trap '_cleanup_temp_files' EXIT HUP INT TERM

    init_path_cache

    check_privileges "$@"

    require_core_utilities
    if [ "$FORCE_POSIX" -eq 1 ]; then
        enforce_posix_mode
    fi

    print_scan_header
    run_all_collectors

    if [ "$OUTPUT_JSON" -eq 1 ]; then
        emit_json
    else
        emit_human_report
    fi

    _cleanup_temp_files
    trap '' EXIT HUP INT TERM
}
