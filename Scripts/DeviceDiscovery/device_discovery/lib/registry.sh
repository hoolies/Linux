# Device registry (filtering, stable ids, dedupe, human TSV).

should_include_kind() {
    kind=$1
    if [ "$PHYSICAL_ONLY" -eq 0 ]; then
        return 0
    fi
    case "$kind" in
        physical|wireless) return 0 ;;
        *) return 1 ;;
    esac
}

# Return 0 if this stable id was already recorded.
seen_device_id() {
    _id=$1
    [ -f "$SEEN_IDS_FILE" ] || return 1
    grep -Fxq "$_id" "$SEEN_IDS_FILE" 2>/dev/null
}

remember_device_id() {
    printf '%s\n' "$1" >> "$SEEN_IDS_FILE"
}

add_device() {
    bus=$1
    kind=$2
    name=$3
    path=${4:-}
    driver=${5:-}
    vendor=${6:-}
    product=${7:-}
    serial=${8:-}
    state=${9:-}
    details='{}'
    if [ $# -gt 9 ]; then
        shift 9
        details=$1
    fi
    case $details in
        \{*) ;;
        *) details='{}' ;;
    esac

    if ! should_include_kind "$kind"; then
        return 0
    fi

    id=$(stable_device_id "$bus" "$path" "$name")
    if seen_device_id "$id"; then
        return 0
    fi
    remember_device_id "$id"

    DEVICE_COUNT=$((DEVICE_COUNT + 1))

    printf '    {"id":"%s","bus":"%s","kind":"%s","name":"%s","path":"%s","driver":"%s","vendor":"%s","product":"%s","serial":"%s","state":"%s","details":%s}\n' \
        "$(_json_esc_one "$id")" \
        "$(_json_esc_one "$bus")" \
        "$(_json_esc_one "$kind")" \
        "$(_json_esc_one "$name")" \
        "$(_json_esc_one "$path")" \
        "$(_json_esc_one "$driver")" \
        "$(_json_esc_one "$vendor")" \
        "$(_json_esc_one "$product")" \
        "$(_json_esc_one "$serial")" \
        "$(_json_esc_one "$state")" \
        "$details" >> "$DEVICES_FILE"

    if [ -n "$BUS_COUNTS_FILE" ]; then
        printf '%s\n' "$bus" >> "$BUS_COUNTS_FILE"
    fi

    if [ "$OUTPUT_JSON" -eq 0 ] && [ -n "$HUMAN_LIST_FILE" ]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$(sanitize_field "$bus")" \
            "$(sanitize_field "$kind")" \
            "$(sanitize_field "$name")" \
            "$(sanitize_field "$path")" \
            "$(sanitize_field "$driver")" \
            "$(sanitize_field "$vendor")" \
            "$(sanitize_field "$product")" \
            "$(sanitize_field "$serial")" \
            "$(sanitize_field "$state")" >> "$HUMAN_LIST_FILE"
    fi
}
