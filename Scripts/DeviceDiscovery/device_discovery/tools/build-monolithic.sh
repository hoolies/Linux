#!/usr/bin/env sh
# Rebuild ../device_discovery.monolithic.sh from modular sources.

set -eu
export LC_ALL=C
unalias -a 2>/dev/null || true
unset -f sed chmod wc cat dirname 2>/dev/null || true

readonly PROGNAME="${0##*/}"

usage() {
    cat <<EOF
Usage: $PROGNAME [OPTION]...
Rebuild device_discovery.monolithic.sh from modular sources.

Mandatory arguments to long options are mandatory for short options too.

  -h, --help            display this help and exit
EOF
}

unrecognized_option() {
    printf '%s: unrecognized option %s\n' "$PROGNAME" "$1" >&2
    printf "Try '%s --help' for more information.\n" "$PROGNAME" >&2
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                unrecognized_option "$1"
                exit 2
                ;;
            *)
                unrecognized_option "$1"
                exit 2
                ;;
        esac
    done
    if [ "$#" -gt 0 ]; then
        unrecognized_option "$1"
        exit 2
    fi
}

script_dir() {
    CDPATH=''
    cd -- "$(dirname -- "$0")" && pwd
}

write_monolithic() {
    dd_root="$1"
    out="$2"
    {
        cat <<HDR
#!/usr/bin/env sh
# Device Discovery — monolithic single-file (generated from device_discovery/)
# Regenerate: device_discovery/tools/build-monolithic.sh

set -eu
export LC_ALL=C
unalias -a 2>/dev/null || true
SCRIPT_VERSION=2.0.0-monolithic
PROGNAME=\${0##*/}
DD_ENTRY=\${0:-device_discovery.monolithic.sh}

HDR
        sed '1,4d' "$dd_root/config.sh"
        for f in common output json paths sysfs network registry privileges fs temp; do
            sed '1{/^#/d;}' "$dd_root/lib/${f}.sh"
            printf '\n'
        done
        for f in "$dd_root"/collectors/*.sh; do
            sed '1{/^#/d;}' "$f"
            printf '\n'
        done
        sed '1{/^#/d;}' "$dd_root/emit.sh"
        printf '\n'
        sed '1{/^#/d;}' "$dd_root/scan.sh"
        printf '\n'
        sed '1,2d' "$dd_root/main.sh"
        printf '%s\n' 'main "$@"'
    } >"$out"
    chmod +x -- "$out"
    printf '%s: wrote %s (%s lines)\n' "$PROGNAME" "$out" "$(wc -l <"$out")"
}

main() {
    parse_args "$@"
    tools_dir="$(script_dir)"
    dd_root="$(CDPATH='' && cd -- "$tools_dir/.." && pwd)"
    out="$dd_root/../device_discovery.monolithic.sh"
    write_monolithic "$dd_root" "$out"
}

main "$@"
