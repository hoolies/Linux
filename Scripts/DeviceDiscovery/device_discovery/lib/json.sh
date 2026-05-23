# JSON encoding.

utc_timestamp() {
    _saved_tz=${TZ-}
    TZ=UTC
    export TZ
    date '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date
    if [ -n "$_saved_tz" ]; then
        TZ=$_saved_tz
        export TZ
    else
        unset TZ
    fi
}

json_bool() {
    if [ "$1" -eq 1 ]; then
        printf 'true'
    else
        printf 'false'
    fi
}

_json_esc_one() {
    printf '%s' "$1" | sed '
        s/\\/\\\\/g
        s/"/\\"/g
        s/	/\\t/g
        s/\r/\\r/g
        s/\n/\\n/g
    '
}

json_object() {
    _out=""
    _sep=""
    while [ $# -ge 2 ]; do
        _key=$1
        _val=$2
        shift 2
        _jk=$(_json_esc_one "$_key")
        _jv=$(_json_esc_one "$_val")
        _out="${_out}${_sep}\"${_jk}\":\"${_jv}\""
        _sep=","
    done
    printf '{%s}' "$_out"
}
