# Human-readable output helpers.

sanitize_field() {
    printf '%s' "$1" | tr '\t\n\r' '   '
}

print_section() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0
    [ "$VERBOSITY" -lt 2 ] && return 0
    printf '\n'
    printf '%s\n' "-------------------------------------"
    printf '%s\n' "$1"
    printf '%s\n' "-------------------------------------"
    return 0
}

print_note() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0
    [ "$VERBOSITY" -lt 2 ] && return 0
    printf '%s\n' "$1"
    return 0
}

print_block() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0
    [ "$VERBOSITY" -lt 2 ] && return 0
    printf '%s\n' "$1"
    return 0
}
