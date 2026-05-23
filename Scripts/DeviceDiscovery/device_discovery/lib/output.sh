# Human-readable output helpers.

sanitize_field() {
    printf '%s' "$1" | tr '\t\n\r' '   '
}

print_section() {
    [ "$OUTPUT_JSON" -eq 1 ] && return
    [ "$VERBOSITY" -lt 2 ] && return
    echo ""
    echo "-------------------------------------"
    echo "$1"
    echo "-------------------------------------"
}

print_note() {
    [ "$OUTPUT_JSON" -eq 1 ] && return
    [ "$VERBOSITY" -lt 2 ] && return
    echo "$1"
}

print_block() {
    [ "$OUTPUT_JSON" -eq 1 ] && return
    [ "$VERBOSITY" -lt 2 ] && return
    echo "$1"
}

