#!/usr/bin/env sh
# Rebuild ../device_discovery.monolithic.sh from modular sources.
# shellcheck shell=sh
set -u

DD_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT=$DD_ROOT/../device_discovery.monolithic.sh

{
    cat <<HDR
#!/usr/bin/env sh
# shellcheck shell=sh
# Device Discovery — monolithic single-file (generated from device_discovery/)
# Regenerate: device_discovery/tools/build-monolithic.sh

set -u
SCRIPT_VERSION=2.0.0-monolithic
DD_ENTRY=\${0:-device_discovery.monolithic.sh}

HDR
    sed '1,4d' "$DD_ROOT/config.sh"
    for f in common output json paths sysfs network registry privileges fs temp; do
        sed '1{/^#/d;}' "$DD_ROOT/lib/${f}.sh"
        echo ""
    done
    for f in "$DD_ROOT"/collectors/*.sh; do
        sed '1{/^#/d;}' "$f"
        echo ""
    done
    sed '1{/^#/d;}' "$DD_ROOT/emit.sh"
    echo ""
    sed '1{/^#/d;}' "$DD_ROOT/scan.sh"
    echo ""
    sed '1,2d' "$DD_ROOT/main.sh"
    echo 'main "$@"'
} >"$OUT"

chmod +x "$OUT"
echo "Wrote $OUT ($(wc -l <"$OUT") lines)"
