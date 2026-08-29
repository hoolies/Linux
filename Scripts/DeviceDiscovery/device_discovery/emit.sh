# JSON and human report emission.

emit_json() {
    hostname=$(hostname 2>/dev/null || printf '%s\n' unknown)
    kernel=$(uname -r 2>/dev/null)
    user=$(whoami 2>/dev/null)
    timestamp=$(utc_timestamp)

    counts=""
    if [ -f "$BUS_COUNTS_FILE" ] && [ -s "$BUS_COUNTS_FILE" ]; then
        counts=$(awk '
            { c[$1]++ }
            END { for (b in c) printf "%d\t%s\n", c[b], b }
        ' "$BUS_COUNTS_FILE" | sort -t '	' -k1,1rn -k2,2 | awk '
            BEGIN { first = 1 }
            {
                if (!first) printf ","
                first = 0
                printf "\"%s\":%s", $2, $1
            }
        ')
    fi

    printf '{'
    printf '"meta":{"version":"%s","hostname":"%s","kernel":"%s","user":"%s","timestamp":"%s","verbosity":%s,"physical_only":%s,"full_dump":%s,"pci_all":%s,"posix":%s},' \
        "$(_json_esc_one "$SCRIPT_VERSION")" \
        "$(_json_esc_one "$hostname")" \
        "$(_json_esc_one "$kernel")" \
        "$(_json_esc_one "$user")" \
        "$(_json_esc_one "$timestamp")" \
        "$VERBOSITY" \
        "$(json_bool "$PHYSICAL_ONLY")" \
        "$(json_bool "$FULL_DUMP")" \
        "$(json_bool "$PCI_ALL")" \
        "$(json_bool "$FORCE_POSIX")"
    printf '"devices":['
    if [ -f "$DEVICES_FILE" ] && [ -s "$DEVICES_FILE" ]; then
        first=1
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            if [ "$first" -eq 1 ]; then
                first=0
            else
                printf ','
            fi
            printf '%s' "$line"
        done <"$DEVICES_FILE"
    fi
    printf '],'
    printf '"summary":{"total_devices":%s,"counts_by_bus":{%s}}' "$DEVICE_COUNT" "$counts"
    printf '}\n'
}

emit_device_list() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0
    [ ! -f "$HUMAN_LIST_FILE" ] && return 0

    printf '\n'
    printf '%s\n' "-------------------------------------"
    printf '%s\n' "DEVICES FOUND"
    printf '%s\n' "-------------------------------------"
    printf '%-10s %-10s %-18s %-10s %-12s %-20s %-14s %s\n' \
        "BUS" "KIND" "NAME" "DRIVER" "SERIAL" "VENDOR" "PRODUCT" "STATE"
    printf '%-10s %-10s %-18s %-10s %-12s %-20s %-14s %s\n' \
        "--------" "--------" "----------------" "--------" "--------" "----------------" "--------" "-----"

    awk -F '\t' 'NF >= 9 {
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
            $1, $2, $3, $5, $8, $6, $7, $9, $4
    }' "$HUMAN_LIST_FILE" | sort -t '	' -k1,1 -k3,3 | awk -F '\t' '{
        bus = $1; kind = $2; name = $3; driver = $4; serial = $5
        vendor = $6; product = $7; state = $8; path = $9
        if (length(vendor) > 18) vendor = substr(vendor, 1, 17) "..."
        if (length(product) > 12) product = substr(product, 1, 11) "..."
        printf "%-10s %-10s %-18s %-10s %-12s %-20s %-14s %s\n",
            bus, kind, name, driver, serial, vendor, product, state
    }'

    printf '\n'
    printf '%s\n' "  Paths:"
    awk -F '\t' 'NF >= 9 {
        printf "%s\t%s\t%s\n", $3, $1, $9
    }' "$HUMAN_LIST_FILE" | sort -t '	' -k2,2 -k1,1 | awk -F '\t' '{
        printf "    [%s] %s -> %s\n", $2, $1, $3
    }'
    printf '\n'
    return 0
}

emit_device_names() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0
    [ "$VERBOSITY" -lt 1 ] && return 0
    [ ! -f "$HUMAN_LIST_FILE" ] && return 0

    printf '\n'
    printf '%s\n' "-------------------------------------"
    printf '%s\n' "DEVICES FOUND"
    printf '%s\n' "-------------------------------------"
    awk -F '\t' 'NF >= 3 { printf "%s\t%s\t%s\n", $3, $1, $2 }' "$HUMAN_LIST_FILE" |
        sort -t '	' -k1,1 -k2,2 |
        awk -F '\t' '{ printf "  %s  (%s / %s)\n", $1, $2, $3 }'
    printf '\n'
    return 0
}

emit_human_summary() {
    [ "$OUTPUT_JSON" -eq 1 ] && return 0

    printf '\n'
    printf '%s\n' "-------------------------------------"
    printf '%s\n' "SUMMARY"
    printf '%s\n' "-------------------------------------"
    printf '%s\n' "  Total recorded devices: $DEVICE_COUNT"

    if [ -f "$HUMAN_LIST_FILE" ] && [ -s "$HUMAN_LIST_FILE" ]; then
        printf '%s\n' "  Counts by bus:"
        awk -F '\t' 'NF >= 1 { c[$1]++ } END {
            for (b in c) printf "%d\t%s\n", c[b], b
        }' "$HUMAN_LIST_FILE" | sort -t '	' -k1,1rn -k2,2 | awk -F '\t' '{
            printf "    %4d  %s\n", $1, $2
        }'
    fi
    return 0
}

emit_human_report() {
    emit_human_summary
    if [ "$VERBOSITY" -eq 1 ]; then
        emit_device_names
    fi
    if [ "$VERBOSITY" -ge 2 ]; then
        emit_device_list
    fi
    printf '%s\n' "====================================="
    printf '%s\n' "   SCAN COMPLETE"
    printf '%s\n' "====================================="
}
